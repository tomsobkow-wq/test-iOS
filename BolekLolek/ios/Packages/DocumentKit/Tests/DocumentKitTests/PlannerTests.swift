import AgentCore
import XCTest
@testable import DocumentKit

final class PlannerTests: XCTestCase {
    private func planner() async throws -> DocumentPlanner {
        let store = DocumentStore(fileURL: nil)
        _ = try await DocumentIngestor.ingest(data: Data(Fixtures.mbankCSV().utf8), fileName: "mbank-marzec.csv", into: store)
        return DocumentPlanner(store: store)
    }

    private func args(_ call: ToolCall) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) as? [String: Any] ?? [:]
    }

    private func need(_ text: String, _ planner: DocumentPlanner, _ language: ConversationLanguage = .pl) async throws -> ToolCall {
        let calls = await planner.plan(userText: text, language: language)
        return try XCTUnwrap(calls.first, "no tool planned for: \(text)")
    }

    func testPolishStatementQuestionsMapToTheRightQueries() async throws {
        let p = try await planner()
        var call = try await need("Ile wydałem na zakupy spożywcze w marcu?", p)
        XCTAssertEqual(call.name, "statement_transactions"); XCTAssertEqual(args(call)["category"] as? String, "groceries"); XCTAssertEqual(args(call)["direction"] as? String, "out")

        call = try await need("Ile zapłaciłem za Ubera?", p)
        XCTAssertEqual(args(call)["merchant"] as? String, "Uber", "the Polish genitive 'Ubera' must find Uber")

        call = try await need("Ile razy płaciłem w Biedronce?", p)
        XCTAssertEqual(args(call)["merchant"] as? String, "Biedronka")

        call = try await need("Ile wpłynęło na moje konto w marcu?", p)
        XCTAssertEqual(call.name, "statement_transactions"); XCTAssertEqual(args(call)["direction"] as? String, "in")

        call = try await need("Jakie mam subskrypcje i ile kosztują?", p)
        XCTAssertEqual(args(call)["category"] as? String, "subscriptions")

        call = try await need("Ile gotówki wypłaciłem z bankomatu?", p)
        XCTAssertEqual(args(call)["category"] as? String, "cash")

        call = try await need("Ile zapłaciłem opłat bankowych?", p)
        XCTAssertEqual(args(call)["category"] as? String, "fees")

        call = try await need("Ile kosztuje mnie Orange?", p)
        XCTAssertEqual(args(call)["merchant"] as? String, "Orange")
    }

    func testSuperlativesBalanceAndTotals() async throws {
        let p = try await planner()
        var call = try await need("Jaka była moja największa płatność?", p)
        XCTAssertEqual(call.name, "statement_transactions"); XCTAssertEqual(args(call)["sort"] as? String, "amount"); XCTAssertEqual(args(call)["limit"] as? Int, 3)

        call = try await need("Jakie było saldo na koniec miesiąca?", p)
        XCTAssertEqual(call.name, "document_summary")
        call = try await need("Ile wydałem łącznie w marcu?", p)
        XCTAssertEqual(call.name, "document_summary")
        call = try await need("Streść mi ten wyciąg", p)
        XCTAssertEqual(call.name, "document_summary")
        call = try await need("Czy wydałem więcej niż zarobiłem?", p)
        XCTAssertEqual(call.name, "document_summary")
        call = try await need("Na co wydaję najwięcej pieniędzy?", p)
        XCTAssertEqual(call.name, "statement_breakdown")
        XCTAssertEqual(args(call)["by"] as? String, "category")
    }

    func testAmbiguousFoodGivesTheCategoryBreakdown() async throws {
        let call = try await need("Ile wydaję na jedzenie?", try await planner())
        XCTAssertEqual(call.name, "statement_breakdown")
    }

    func testEnglishQuestions() async throws {
        let store = DocumentStore(fileURL: nil)
        _ = try await DocumentIngestor.ingest(data: Data(Fixtures.revolutCSV().utf8), fileName: "revolut-march.csv", into: store)
        let p = DocumentPlanner(store: store)
        var call = try await need("How much did I spend at Tesco?", p, .en)
        XCTAssertEqual(args(call)["merchant"] as? String, "Tesco")
        call = try await need("How much money came in this month?", p, .en)
        XCTAssertEqual(args(call)["direction"] as? String, "in")
        call = try await need("What was my biggest expense?", p, .en)
        XCTAssertEqual(args(call)["sort"] as? String, "amount")
        call = try await need("How much did I pay for subscriptions?", p, .en)
        XCTAssertEqual(args(call)["category"] as? String, "subscriptions")
        call = try await need("Explain my statement", p, .en)
        XCTAssertEqual(call.name, "document_summary")
    }

    func testSmallTalkAndNoDocumentsAreLeftToTheModel() async throws {
        let p = try await planner()
        for text in ["Cześć!", "Opowiedz dowcip", "Jaka jest pogoda w Krakowie?", "Ustaw budzik na 6:30", "Hello, who are you?"] {
            let planned = await p.plan(userText: text, language: .pl)
            XCTAssertTrue(planned.isEmpty, "\(text) → \(planned.map(\.name))")
        }
        let none = await DocumentPlanner(store: DocumentStore(fileURL: nil)).plan(userText: "Ile wydałem na zakupy?", language: .pl)
        XCTAssertTrue(none.isEmpty)
    }

    func testMonthSelectionOnAMultiMonthStatement() async throws {
        func tx(_ id: Int, _ day: String, _ minor: Int) -> Transaction {
            Transaction(id: id, date: DateParsing.parse(day, order: .dayFirst)!, minorUnits: minor, currency: "PLN", text: "Biedronka", merchant: "Biedronka", category: "groceries", balanceMinor: nil)
        }
        let statement = ParsedStatement(bank: nil, accountHint: nil, currency: "PLN", transactions: [tx(0, "2026-02-03", -1000), tx(1, "2026-03-04", -2000)], openingMinor: nil, closingMinor: nil, periodStart: nil, periodEnd: nil, warnings: [], reconciliation: .unknown)
        let store = DocumentStore(fileURL: nil)
        await store.add(StoredDocument(id: "d1", name: "s.csv", kind: .statement, addedAt: Date(), pageCount: nil, chunks: [], statement: ParsedStatement(bank: nil, accountHint: nil, currency: "PLN", transactions: statement.transactions, openingMinor: nil, closingMinor: nil, periodStart: statement.transactions.first?.date, periodEnd: statement.transactions.last?.date, warnings: [], reconciliation: .unknown), summary: nil, characterCount: 1))
        let planned = await DocumentPlanner(store: store).plan(userText: "Ile wydałem na zakupy spożywcze w lutym?", language: .pl)
        let call = try XCTUnwrap(planned.first)
        XCTAssertEqual(args(call)["from"] as? String, "2026-02-01")
        XCTAssertEqual(args(call)["to"] as? String, "2026-02-28")
    }

    func testDocumentQuestionsRetrievePassagesAndSummariesUseTheSummary() async throws {
        let store = DocumentStore(fileURL: nil)
        let text = "UMOWA NAJMU\n\nCzynsz wynosi 2400,00 zł miesięcznie, płatny do 10 dnia każdego miesiąca.\n\nKaucja wynosi 4800,00 zł i zostanie zwrócona w ciągu 30 dni po zakończeniu najmu.\n\nWypowiedzenie wymaga formy pisemnej z trzymiesięcznym okresem."
        let doc = try await DocumentIngestor.ingest(data: Data(text.utf8), fileName: "umowa.txt", into: store)
        let p = DocumentPlanner(store: store)
        var call = try await need("Ile wynosi kaucja w umowie?", p)
        XCTAssertEqual(call.name, "document_search")
        call = try await need("Streść tę umowę", p)
        XCTAssertEqual(call.name, "document_summary"); XCTAssertEqual(args(call)["document_id"] as? String, doc.id)
        let small = await p.plan(userText: "Cześć, co słychać?", language: .pl)
        XCTAssertTrue(small.isEmpty)
    }
}
