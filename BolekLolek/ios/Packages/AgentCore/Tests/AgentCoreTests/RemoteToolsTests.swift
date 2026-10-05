import XCTest
@testable import AgentCore

final class RemoteToolsTests: XCTestCase {
    private let config = BackendConfig(baseURL: URL(string: "http://192.168.1.20:8787/")!, token: "secret-token-123456")

    private func client(status: Int = 200, json: String, record: RequestBox? = nil) -> BackendClient {
        BackendClient(config: config) { request in
            record?.set(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
    }

    final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URLRequest?
        func set(_ request: URLRequest) { lock.lock(); stored = request; lock.unlock() }
        var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private let toolsJSON = """
    {"tools":[
      {"name":"search_flights","description":"Search flights.","risk":"read","parameters":{"type":"object","properties":{"from":{"type":"string"}}}},
      {"name":"watch_flight_price","description":"Watch a fare.","risk":"write","parameters":{"type":"object","properties":{}}}
    ]}
    """

    func testDiscoveryBuildsBolekOnlyToolsWithRisk() async throws {
        let tools = await RemoteTool.discover(client: client(json: toolsJSON))
        XCTAssertEqual(tools.map(\.name), ["search_flights", "watch_flight_price"])
        XCTAssertTrue(tools.allSatisfy { $0.tier == .bolek })
        XCTAssertEqual(tools[0].risk, .read)
        XCTAssertEqual(tools[1].risk, .writeExternal)
        XCTAssertTrue(tools[1].risk.needsApproval)
        XCTAssertTrue(tools[0].parametersSchema.contains("\"from\""))
    }

    func testUnknownRiskIsTreatedAsWrite() async throws {
        let json = #"{"tools":[{"name":"x","description":"d","parameters":{"type":"object"}}]}"#
        let tools = await RemoteTool.discover(client: client(json: json))
        XCTAssertEqual(tools.first?.risk, .writeExternal)
    }

    func testUnauthorisedOrUnreachableServerGivesNoToolsInsteadOfFailing() async {
        let denied = await RemoteTool.discover(client: client(status: 401, json: #"{"error":"unauthorized"}"#))
        XCTAssertTrue(denied.isEmpty)
        let down = BackendClient(config: config) { _ in throw URLError(.cannotConnectToHost) }
        let none = await RemoteTool.discover(client: down)
        XCTAssertTrue(none.isEmpty)
    }

    func testCallSendsTokenAndArgumentsAsObject() async throws {
        let box = RequestBox()
        let tool = RemoteTool(
            spec: .init(name: "search_flights", description: "d", risk: "read", parametersSchema: "{}"),
            client: client(json: #"{"ok":true,"content":"Cheapest: 120 EUR"}"#, record: box)
        )
        let result = try await tool.run(argumentsJSON: #"{"from":"Warsaw","to":"Rome"}"#)
        XCTAssertEqual(result, "Cheapest: 120 EUR")
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.20:8787/v1/tools/call")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token-123456")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "search_flights")
        XCTAssertEqual((body["arguments"] as? [String: Any])?["to"] as? String, "Rome")
    }

    func testServerExplanationBecomesToolErrorTheModelCanRelay() async {
        let tool = RemoteTool(
            spec: .init(name: "search_flights", description: "d", risk: "read", parametersSchema: "{}"),
            client: client(json: #"{"ok":false,"content":"Flight search is not set up on the server yet."}"#)
        )
        do {
            _ = try await tool.run(argumentsJSON: "{}")
            XCTFail("expected an error")
        } catch let error as ToolError {
            XCTAssertEqual(error.message, "Flight search is not set up on the server yet.")
        } catch { XCTFail("wrong error \(error)") }
    }

    func testAlertsDecodeAndSeenIsPosted() async throws {
        let box = RequestBox()
        let alerts = try await client(json: #"{"alerts":[{"id":4,"watchId":"ab","createdAt":1,"title":"Price drop: WAW to FCO","body":"89.00 EUR (your limit 100.00 EUR).","priceMinor":8900,"currency":"EUR","seen":false}]}"#).alerts(since: 3)
        XCTAssertEqual(alerts, [BackendAlert(id: 4, title: "Price drop: WAW to FCO", body: "89.00 EUR (your limit 100.00 EUR).")])
        XCTAssertEqual(alerts.first?.message, "Price drop: WAW to FCO\n89.00 EUR (your limit 100.00 EUR).")
        try await client(json: #"{"ok":true}"#, record: box).markAlertsSeen(upTo: 4)
        XCTAssertEqual(box.request?.httpMethod, "POST")
        XCTAssertEqual(box.request?.url?.path, "/v1/alerts/seen")
    }

    func testEveryRequestCarriesThePhonesCountryLanguageAndCurrency() async throws {
        let box = RequestBox()
        let client = BackendClient(config: config, hints: LocaleHints(country: "AU", language: "en", currency: "AUD"), transport: { request in
            box.set(request)
            return (Data(#"{"ok":true,"content":"x"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await client.call("search_products", argumentsJSON: #"{"query":"electric bike"}"#)
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Country"), "AU")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Language"), "en")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Currency"), "AUD")
    }

    func testMissingHintsAreSimplyNotSent() async throws {
        let box = RequestBox()
        let client = BackendClient(config: config, hints: LocaleHints(country: nil, language: nil, currency: nil), transport: { request in
            box.set(request)
            return (Data(#"{"ok":true,"content":"x"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await client.call("search_news", argumentsJSON: "{}")
        XCTAssertNil(box.request?.value(forHTTPHeaderField: "X-Country"))
    }

    func testSourcesComeBackWithTheAnswerAndOnlySafeLinksSurvive() async throws {
        let json = #"{"ok":true,"content":"found","sources":[{"title":"2021 R18","site":"Bikesales","url":"https://www.bikesales.com.au/r18"},{"title":"x","site":"Plain","url":"http://plain.example/a"},{"title":"x","site":"Creds","url":"https://u:p@evil.example/"},{"title":"x","site":"Local","url":"https://localhost/"},{"title":"dup","site":"Bikesales","url":"https://www.bikesales.com.au/r18"},{"title":"x","site":"Js","url":"javascript:alert(1)"}]}"#
        let collector = SourceCollector()
        let tool = RemoteTool(spec: .init(name: "web_search", description: "d", risk: "read", parametersSchema: "{}"), client: client(json: json), sources: collector)
        let text = try await tool.run(argumentsJSON: "{}")
        XCTAssertEqual(text, "found")
        XCTAssertEqual(collector.take().map(\.url), ["https://www.bikesales.com.au/r18"])
        XCTAssertTrue(collector.take().isEmpty, "taking starts over")
    }

    func testOlderServersWithoutSourcesStillWork() async throws {
        let reply = try await client(json: #"{"ok":true,"content":"x"}"#).callWithSources("web_search", argumentsJSON: "{}")
        XCTAssertEqual(reply.content, "x")
        XCTAssertTrue(reply.sources.isEmpty)
    }

    func testAlertLinksDecodeAndBadOnesAreDropped() throws {
        let json = #"{"id":9,"title":"New results: BMW R18","body":"1 new result.","links":[{"title":"2023 R18","site":"Gumtree","url":"https://gumtree.example/3"},{"title":"bad","site":"Evil","url":"http://evil.example/"}]}"#
        let alert = try JSONDecoder().decode(BackendAlert.self, from: Data(json.utf8))
        XCTAssertEqual(alert.links, [SourceLink(title: "2023 R18", site: "Gumtree", url: "https://gumtree.example/3")])
        let plain = try JSONDecoder().decode(BackendAlert.self, from: Data(#"{"id":1,"title":"t","body":"b"}"#.utf8))
        XCTAssertTrue(plain.links.isEmpty)
    }

    func testOnlyRealHttpsSitesCanBeOpened() {
        func openable(_ url: String) -> Bool { SourceLink(title: "t", site: "s", url: url).openURL != nil }
        XCTAssertTrue(openable("https://www.carsales.com.au/cars/x?id=1"))
        XCTAssertFalse(openable("http://www.carsales.com.au/"))
        XCTAssertFalse(openable("https://localhost/"))
        XCTAssertFalse(openable("https://192.168.1.5/"))
        XCTAssertFalse(openable("https://user@site.example/"))
        XCTAssertFalse(openable("https://exa mple.com/"))
        XCTAssertFalse(openable("mailto:a@b.example"))
        XCTAssertFalse(openable("tel:123"))
        XCTAssertEqual(SourceLink(title: "t", site: "", url: "https://a.example/x").label, "a.example")
    }
}
