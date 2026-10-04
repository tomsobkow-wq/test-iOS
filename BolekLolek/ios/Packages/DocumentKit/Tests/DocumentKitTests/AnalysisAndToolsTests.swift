import AgentCore
import XCTest
@testable import DocumentKit

final class AnalysisAndToolsTests: XCTestCase {
    private func polishStore() async throws -> (DocumentStore, ParsedStatement) {
        let statement = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        let store = DocumentStore(fileURL: nil)
        await store.add(StoredDocument(id: "d1", name: "mbank-marzec.csv", kind: .statement, addedAt: Date(), pageCount: nil, chunks: [], statement: statement, summary: nil, characterCount: 0))
        return (store, statement)
    }

    private func sum(_ rows: [TruthRow], where predicate: (TruthRow) -> Bool) -> Int { rows.filter(predicate).reduce(0) { $0 + $1.minor } }

    // MARK: Digest

    func testDigestNumbersMatchIndependentArithmetic() throws {
        let statement = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        let digest = StatementAnalyzer.digest(statement)
        let truth = Fixtures.polish
        let moneyIn = sum(truth) { $0.minor > 0 }
        let moneyOut = -sum(truth) { $0.minor < 0 }
        XCTAssertTrue(digest.contains("Money in: \(MoneyFormat.text(moneyIn, currency: "PLN"))"), digest)
        XCTAssertTrue(digest.contains("Money out: \(MoneyFormat.text(moneyOut, currency: "PLN"))"), digest)
        XCTAssertTrue(digest.contains("equals the closing balance"), digest)
        let spending = -sum(truth) { $0.minor < 0 && $0.category != "savings" }
        XCTAssertTrue(digest.contains("Spending, not counting savings"), digest)
        XCTAssertTrue(digest.contains(MoneyFormat.text(spending, currency: "PLN")), digest)
        XCTAssertTrue(digest.contains("Orange 210.00 PLN"), "top merchants by spend: \(digest)")
        XCTAssertFalse(digest.contains("Biedronka"), "small merchants are for the query tool, not the digest")
        XCTAssertTrue(digest.contains("Netflix"), digest)
        XCTAssertTrue(digest.contains("bank fees 35.00 PLN"), digest)
        XCTAssertTrue(digest.contains("cash withdrawals 120.00 PLN"), digest)
        XCTAssertLessThan(digest.count, 2_400, "the digest must stay small enough for a 4B model (about 600 tokens)")
    }

    func testDigestWarnsLoudlyWhenNumbersDoNotAddUp() throws {
        var lines = Fixtures.polishPDFText().components(separatedBy: "\n")
        lines.remove(at: try XCTUnwrap(lines.firstIndex { $0.contains("LIDL") }))
        let statement = try XCTUnwrap(StatementParser.parse(lines.joined(separator: "\n")))
        let digest = StatementAnalyzer.digest(statement)
        XCTAssertTrue(digest.contains("WARNING"), digest)
    }

    func testRecurringPaymentsAreFoundAcrossMonths() {
        func tx(_ id: Int, _ day: String, _ minor: Int, _ merchant: String) -> Transaction {
            Transaction(id: id, date: DateParsing.parse(day, order: .dayFirst)!, minorUnits: minor, currency: "PLN", text: merchant, merchant: merchant, category: "subscriptions", balanceMinor: nil)
        }
        let statement = ParsedStatement(bank: nil, accountHint: nil, currency: "PLN", transactions: [
            tx(0, "2026-01-03", -5299, "Netflix"), tx(1, "2026-02-03", -5299, "Netflix"), tx(2, "2026-03-04", -5299, "Netflix"),
            tx(3, "2026-01-10", -1500, "Kiosk"), tx(4, "2026-03-20", -4000, "Kiosk"),
        ], openingMinor: nil, closingMinor: nil, periodStart: nil, periodEnd: nil, warnings: [], reconciliation: .unknown)
        let found = StatementAnalyzer.recurring(statement)
        XCTAssertEqual(found.map(\.merchant), ["Netflix"])
        XCTAssertEqual(found.first?.every, "monthly")
        XCTAssertEqual(found.first?.count, 3)
        XCTAssertTrue(StatementAnalyzer.digest(statement).contains("By month"))
    }

    // MARK: Tools

    func testTransactionsToolGivesExactTotals() async throws {
        let (store, _) = try await polishStore()
        let tool = StatementTransactionsTool(store: store)
        let groceries = try await tool.run(argumentsJSON: #"{"category":"groceries"}"#)
        let expected = -sum(Fixtures.polish) { $0.category == "groceries" }
        XCTAssertTrue(groceries.contains("Matches: 3 transactions; money out \(MoneyFormat.text(expected, currency: "PLN"))"), groceries)

        let uber = try await tool.run(argumentsJSON: #"{"search":"uber"}"#)
        XCTAssertTrue(uber.contains("64.90 PLN"), uber)

        let big = try await tool.run(argumentsJSON: #"{"direction":"out","min_amount":"1 000,00","sort":"amount"}"#)
        XCTAssertTrue(big.contains("Matches: 2 transactions"), big)
        XCTAssertTrue(big.hasPrefix("2026-03-05"), "sorted by amount, rent first: \(big)")

        let march = try await tool.run(argumentsJSON: #"{"from":"2026-03-10","to":"2026-03-15","direction":"out"}"#)
        let window = -sum(Fixtures.polish) { $0.day >= "2026-03-10" && $0.day <= "2026-03-15" && $0.minor < 0 }
        XCTAssertTrue(march.contains(MoneyFormat.text(window, currency: "PLN")), march)

        let none = try await tool.run(argumentsJSON: #"{"merchant":"Nonexistent Shop"}"#)
        XCTAssertEqual(none, "No transactions match.")
    }

    func testToolRejectsInventedCategoriesWithAHelpfulMessage() async throws {
        let (store, _) = try await polishStore()
        do {
            _ = try await StatementTransactionsTool(store: store).run(argumentsJSON: #"{"category":"food"}"#)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("groceries"), error.localizedDescription)
        }
    }

    func testBreakdownByCategoryAndMonth() async throws {
        let (store, _) = try await polishStore()
        let byCategory = try await StatementBreakdownTool(store: store).run(argumentsJSON: #"{"by":"category","direction":"out"}"#)
        XCTAssertTrue(byCategory.hasPrefix("housing: out 2400.00 PLN"), byCategory)
        let byMonth = try await StatementBreakdownTool(store: store).run(argumentsJSON: #"{"by":"month"}"#)
        XCTAssertTrue(byMonth.contains("2026-03: out"), byMonth)
    }

    func testListSummaryAndDelete() async throws {
        let (store, _) = try await polishStore()
        let list = try await ListDocumentsTool(store: store).run(argumentsJSON: "{}")
        XCTAssertTrue(list.contains("[d1] bank statement \"mbank-marzec.csv\", 17 transactions"), list)
        let summary = try await DocumentSummaryTool(store: store).run(argumentsJSON: "{}")
        XCTAssertTrue(summary.hasPrefix("Statement mBank"), summary)
        XCTAssertEqual(DeleteDocumentTool(store: store).risk, .destructive, "deleting asks first")
        _ = try await DeleteDocumentTool(store: store).run(argumentsJSON: #"{"document_id":"d1"}"#)
        let after = await store.isEmpty
        XCTAssertTrue(after)
    }

    func testDocumentToolsAreHiddenUntilThereIsSomethingToUse() async throws {
        let empty = DocumentStore(fileURL: nil)
        for tool in DocumentToolbox.tools(store: empty) {
            let available = await (tool as! any ConditionallyAvailable).isAvailable()
            XCTAssertFalse(available, tool.name)
        }
        let (store, _) = try await polishStore()
        let names = await DocumentToolbox.tools(store: store).asyncFilter { await ($0 as! any ConditionallyAvailable).isAvailable() }.map(\.name)
        XCTAssertTrue(names.contains("statement_transactions"))
        XCTAssertFalse(names.contains("document_search"), "no text documents yet")
        XCTAssertTrue(DocumentToolbox.tools(store: store).allSatisfy { $0.tier == .lolek }, "documents stay on the phone")
    }

    func testAgentSessionOnlyOffersDocumentToolsWhenDocumentsExist() async throws {
        actor Seen { var tools: [[String]] = []; func add(_ t: [String]) { tools.append(t) } }
        struct Spy: ModelProvider {
            let seen: Seen
            var profile: ModelProfile { .qwen35_4B }
            func respond(to request: ModelRequest) async throws -> ModelResponse {
                await seen.add(request.tools.map(\.name))
                return ModelResponse(text: "ok")
            }
        }
        struct Allow: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }
        let seen = Seen()
        let store = DocumentStore(fileURL: nil)
        let session = AgentSession(mode: .lolek, provider: Spy(seen: seen), registry: ToolRegistry(DocumentToolbox.tools(store: store)), approvalHandler: Allow(), language: .en)
        _ = try await session.send("hi")
        let statement = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        await store.add(StoredDocument(id: "d1", name: "s", kind: .statement, addedAt: Date(), pageCount: nil, chunks: [], statement: statement, summary: nil, characterCount: 0))
        _ = try await session.send("hi again")
        let log = await seen.tools
        XCTAssertEqual(log.first, [], "no documents, no document tools in the prompt")
        XCTAssertTrue(try XCTUnwrap(log.last).contains("statement_transactions"))
    }

    // MARK: Search

    func testSearchFindsInflectedPolishWordsAndEnglish() {
        let contract = """
        Umowa najmu lokalu mieszkalnego zawarta w dniu 1 marca 2026 roku pomiędzy Janem Kowalskim a Anną Nowak.

        Czynsz najmu wynosi 2400,00 zł miesięcznie i płatny jest do 10 dnia każdego miesiąca na rachunek wynajmującego.

        Najemca wpłaca kaucję w wysokości 4800,00 zł, która zostanie zwrócona w ciągu 30 dni po zakończeniu umowy.

        Umowa zostaje zawarta na czas określony do 28 lutego 2027 roku. Wypowiedzenie wymaga formy pisemnej.
        """
        let index = SearchIndex(chunks: contract.components(separatedBy: "\n\n").enumerated().map { DocumentChunk(id: $0.offset, text: $0.element, page: nil) })
        XCTAssertEqual(index.search("kaucja", limit: 1).first?.chunk.id, 2, "kaucję in the text, kaucja in the question")
        XCTAssertEqual(index.search("ile wynosi czynsz?", limit: 1).first?.chunk.id, 1)
        XCTAssertEqual(index.search("do kiedy obowiązuje umowa", limit: 1).first?.chunk.id, 3)
        XCTAssertTrue(index.search("zupełnie coś innego o rowerach", limit: 1).isEmpty)

        let english = SearchIndex(chunks: [
            DocumentChunk(id: 0, text: "The tenant pays a deposit of 1,200 pounds which is refunded within 30 days.", page: nil),
            DocumentChunk(id: 1, text: "Termination requires written notice of two months.", page: nil),
        ])
        XCTAssertEqual(english.search("how much is the deposit", limit: 1).first?.chunk.id, 0)
        XCTAssertEqual(english.search("notice period for terminating", limit: 1).first?.chunk.id, 1)
    }

    func testChunkerKeepsEverythingAndStaysSmall() {
        let paragraph = (1...40).map { "To jest zdanie numer \($0) w długim dokumencie testowym." }.joined(separator: " ")
        let text = (1...6).map { _ in paragraph }.joined(separator: "\n\n")
        let chunks = Chunker.chunk(text)
        XCTAssertGreaterThan(chunks.count, 6)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 1_900 }, "chunk sizes: \(chunks.map { $0.text.count })")
        let joined = chunks.map(\.text).joined(separator: " ")
        for n in [1, 17, 40] { XCTAssertTrue(joined.contains("zdanie numer \(n) w"), "sentence \(n) lost") }
    }

    func testStorePersistsAndReloads() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let statement = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        let store = DocumentStore(fileURL: url)
        await store.add(StoredDocument(id: "d1", name: "a.csv", kind: .statement, addedAt: Date(), pageCount: nil, chunks: [], statement: statement, summary: nil, characterCount: 10))
        await store.setSummary("Podsumowanie", for: "d1")
        let reloaded = DocumentStore(fileURL: url)
        let doc = await reloaded.document(id: "d1")
        XCTAssertEqual(doc?.summary, "Podsumowanie")
        XCTAssertEqual(doc?.statement?.transactions.count, 17)
    }
}

extension Sequence {
    func asyncFilter(_ predicate: (Element) async -> Bool) async -> [Element] {
        var out: [Element] = []
        for element in self where await predicate(element) { out.append(element) }
        return out
    }
}
