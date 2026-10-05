import XCTest
@testable import AgentCore

private final class Urls: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    func add(_ url: URL) { lock.lock(); list.append(url); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return list }
}

private struct RecordingOpener: URLOpening {
    let urls: Urls
    func open(_ url: URL) async -> Bool { urls.add(url); return true }
}

private struct OneContact: ContactsProviding {
    func find(name: String) async throws -> [ContactInfo] { [ContactInfo(name: "Test Person", phoneNumbers: ["+48 000 000 000"])] }
}

final class OpenMeteoWeatherTests: XCTestCase {
    private func provider(urls: Urls = Urls(), forecast: String? = nil, geocode: String = #"{"results":[{"name":"Warsaw","latitude":52.23,"longitude":21.01}]}"#) -> OpenMeteoWeather {
        let forecastJSON = forecast ?? """
        {"current":{"time":"2026-10-05T14:00","temperature_2m":12.4,"apparent_temperature":10.1,"weather_code":61},
         "daily":{"temperature_2m_max":[14.2,15.0],"temperature_2m_min":[7.8,8.0],"precipitation_probability_max":[80,20]},
         "hourly":{"time":["2026-10-05T13:00","2026-10-05T15:00","2026-10-05T16:00"],"precipitation_probability":[90,30,70]}}
        """
        return OpenMeteoWeather(currentLocation: { (51.5, -0.12, "London") }) { request in
            urls.add(request.url!)
            let body = request.url!.host!.hasPrefix("geocoding") ? geocode : forecastJSON
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testNamedPlaceGivesTemperatureConditionAndNextRain() async throws {
        let urls = Urls()
        let report = try await provider(urls: urls).weather(for: "Warsaw, Poland")
        XCTAssertEqual(report.place, "Warsaw")
        XCTAssertEqual(report.temperatureC, 12.4, accuracy: 0.01)
        XCTAssertEqual(report.condition, "rain")
        XCTAssertEqual(report.highC, 14.2)
        XCTAssertEqual(report.lowC, 7.8)
        XCTAssertEqual(report.precipitationChancePercent, 80)
        XCTAssertEqual(report.note, "rain likely from 16:00", "13:00 is in the past and 15:00 is only 30%")
        XCTAssertTrue(urls.all.allSatisfy { $0.host?.hasSuffix("open-meteo.com") == true })
        XCTAssertTrue(urls.all[0].absoluteString.contains("name=Warsaw"), "only the city name is sent, not the country")
    }

    func testCurrentLocationUsesTheDeviceFixAndSendsOnlyRoundedCoordinates() async throws {
        let urls = Urls()
        let report = try await provider(urls: urls).weather(for: nil)
        XCTAssertEqual(report.place, "London")
        XCTAssertEqual(urls.all.count, 1, "no place lookup is needed")
        XCTAssertTrue(urls.all[0].absoluteString.contains("latitude=51.500"))
    }

    func testUnknownPlaceIsAnHonestError() async {
        do { _ = try await provider(geocode: #"{"generationtime_ms":0.2}"#).weather(for: "Zzyzxville"); XCTFail() } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("Could not find a place called"))
        } catch { XCTFail() }
    }

    func testNoNetworkIsSaidPlainly() async {
        let offline = OpenMeteoWeather(currentLocation: { (0, 0, nil) }) { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await offline.weather(for: "Warsaw"); XCTFail() } catch let error as ToolError {
            XCTAssertTrue(error.message.contains("needs an internet connection"))
        } catch { XCTFail() }
    }

    func testWeatherCodesAreWords() {
        XCTAssertEqual(OpenMeteoWeather.condition(code: 0), "clear sky")
        XCTAssertEqual(OpenMeteoWeather.condition(code: 95), "thunderstorm")
        XCTAssertEqual(OpenMeteoWeather.condition(code: 73), "snow")
        XCTAssertEqual(OpenMeteoWeather.condition(code: 999), "unknown conditions")
    }
}

final class MapsToolTests: XCTestCase {
    func testDirectionsOpenAppleMapsWithTheRightMode() async throws {
        let urls = Urls()
        let tool = GetDirectionsTool(opener: RecordingOpener(urls: urls))
        let reply = try await tool.run(argumentsJSON: #"{"destination":"Zamek Królewski, Warszawa","mode":"walking"}"#)
        let url = try XCTUnwrap(urls.all.first)
        XCTAssertEqual(url.host, "maps.apple.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "daddr" }?.value, "Zamek Królewski, Warszawa")
        XCTAssertEqual(items.first { $0.name == "dirflg" }?.value, "w")
        XCTAssertNil(items.first { $0.name == "saddr" }, "default start is the user's own location")
        XCTAssertTrue(reply.contains("walking") && reply.contains("taps Start"))
    }

    func testShowOnMapAndEmptyInput() async throws {
        let urls = Urls()
        let tool = ShowOnMapTool(opener: RecordingOpener(urls: urls))
        _ = try await tool.run(argumentsJSON: #"{"place":"apteka w pobliżu"}"#)
        XCTAssertEqual(URLComponents(url: urls.all[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "apteka w pobliżu")
        do { _ = try await tool.run(argumentsJSON: #"{"place":"  "}"#); XCTFail() } catch is ToolError {} catch { XCTFail() }
    }

    func testMapsToolsBelongToBothAssistantsAndAreReadOnly() {
        for tool in MapsToolbox.tools(opener: RecordingOpener(urls: Urls())) {
            XCTAssertEqual(tool.tier, .both)
            XCTAssertFalse(tool.risk.needsApproval)
        }
    }
}

final class CallAndTextSafetyTests: XCTestCase {
    func testCallOnlyOpensTheConfirmScreenAndAsksTheUserFirst() async throws {
        let urls = Urls()
        let tool = CallContactTool(contacts: OneContact(), opener: RecordingOpener(urls: urls))
        XCTAssertTrue(tool.risk.needsApproval, "the app asks before it even opens the call screen")
        let reply = try await tool.run(argumentsJSON: #"{"to":"Test Person"}"#)
        XCTAssertEqual(urls.all.count, 1)
        XCTAssertEqual(urls.all[0].scheme, "tel", "tel: shows iOS's own 'Call?' confirmation; the app cannot dial silently")
        XCTAssertTrue(reply.contains("confirms on the call screen"))
    }

    func testTextOnlyPreparesADraft() async throws {
        let urls = Urls()
        let tool = TextContactTool(contacts: OneContact(), opener: RecordingOpener(urls: urls))
        XCTAssertTrue(tool.risk.needsApproval)
        let reply = try await tool.run(argumentsJSON: #"{"to":"Test Person","body":"Hello"}"#)
        XCTAssertEqual(urls.all[0].scheme, "sms")
        XCTAssertTrue(reply.contains("still has to tap Send"))
    }
}
