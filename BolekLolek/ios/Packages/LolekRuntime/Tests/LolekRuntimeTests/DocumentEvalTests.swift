import AgentCore
import DocumentKit
import XCTest
@testable import LolekRuntime

/// Measures how well Qwen3.5 4B handles bank statements and documents through the DocumentKit harness.
///     LOLEK_MODEL_DIR=~/Developer/lolek-models swift test --filter DocumentEvalTests
private final class StepBox: @unchecked Sendable { var value = 0 }

final class DocumentEvalTests: XCTestCase {
    // MARK: Data (invented)

    private struct Row { let day: String; let minor: Int; let text: String }
    private static let polishRows = [
        Row(day: "2026-03-01", minor: 850_000, text: "WYNAGRODZENIE MARZEC ACME SP Z O O"), Row(day: "2026-03-02", minor: -4_560, text: "PŁATNOŚĆ KARTĄ BIEDRONKA 1234 WARSZAWA"),
        Row(day: "2026-03-03", minor: -5_299, text: "NETFLIX.COM"), Row(day: "2026-03-04", minor: -12_000, text: "WYPŁATA Z BANKOMATU PKO ATM WARSZAWA"),
        Row(day: "2026-03-05", minor: -240_000, text: "CZYNSZ ZA MARZEC WSPÓLNOTA MIESZKANIOWA"), Row(day: "2026-03-07", minor: -3_840, text: "PŁATNOŚĆ KARTĄ ŻABKA Z1234 KRAKÓW"),
        Row(day: "2026-03-09", minor: -2_900, text: "SPOTIFY P3A8"), Row(day: "2026-03-10", minor: -8_735, text: "PŁATNOŚĆ KARTĄ ORLEN STACJA 4521"),
        Row(day: "2026-03-12", minor: -15_220, text: "PŁATNOŚĆ KARTĄ LIDL 0456"), Row(day: "2026-03-14", minor: -6_490, text: "UBER *TRIP HELP.UBER.COM"),
        Row(day: "2026-03-15", minor: -19_900, text: "ALLEGRO PAYMENT 7384929"), Row(day: "2026-03-18", minor: 4_500, text: "ZWROT ZA ZAMÓWIENIE ALLEGRO"),
        Row(day: "2026-03-20", minor: -3_500, text: "OPŁATA ZA PROWADZENIE RACHUNKU"), Row(day: "2026-03-22", minor: -6_150, text: "PŁATNOŚĆ KARTĄ MCDONALDS 321 WARSZAWA"),
        Row(day: "2026-03-25", minor: -120_000, text: "PRZELEW NA RACHUNEK WŁASNY OSZCZĘDNOŚCI"), Row(day: "2026-03-28", minor: -4_999, text: "PLAY ABONAMENT"),
        Row(day: "2026-03-30", minor: -21_000, text: "ORANGE FAKTURA 55123"),
    ]
    private static let englishRows = [
        Row(day: "2026-03-01", minor: 215_000, text: "SALARY ACME LTD"), Row(day: "2026-03-02", minor: -1_250, text: "CARD PAYMENT TO TESCO STORES 3421"),
        Row(day: "2026-03-03", minor: -1_099, text: "NETFLIX.COM"), Row(day: "2026-03-04", minor: -80_000, text: "STANDING ORDER RENT MR J SMITH"),
        Row(day: "2026-03-06", minor: -2_640, text: "CARD PAYMENT TO SAINSBURY'S 0912"), Row(day: "2026-03-08", minor: -450, text: "TFL TRAVEL CH"),
        Row(day: "2026-03-11", minor: -999, text: "SPOTIFY AB"), Row(day: "2026-03-13", minor: -4_580, text: "CARD PAYMENT TO AMAZON.CO.UK"),
        Row(day: "2026-03-15", minor: -2_000, text: "CASH WITHDRAWAL ATM HIGH STREET"), Row(day: "2026-03-17", minor: 1_999, text: "REFUND AMAZON.CO.UK"),
        Row(day: "2026-03-21", minor: -1_720, text: "CARD PAYMENT TO PRET A MANGER"), Row(day: "2026-03-25", minor: -6_500, text: "DIRECT DEBIT BRITISH GAS"),
        Row(day: "2026-03-29", minor: -1_800, text: "MONTHLY ACCOUNT FEE"),
    ]

    private static func mbankCSV() -> String {
        func pl(_ m: Int) -> String {
            var g = ""; for (i, ch) in String(abs(m) / 100).reversed().enumerated() { if i > 0 && i % 3 == 0 { g = " " + g }; g = String(ch) + g }
            return (m < 0 ? "-" : "") + g + String(format: ",%02d PLN", abs(m) % 100)
        }
        var balance = 500_000
        var out = "mBank S.A.\n\n#Data operacji;#Opis operacji;#Rachunek;#Kategoria;#Kwota;#Saldo po operacji;\n"
        for row in polishRows { balance += row.minor; out += "\(row.day);\"\(row.text)\";\"Konto\";\"Inne\";\(pl(row.minor));\(pl(balance));\n" }
        return out
    }

    private static func revolutCSV() -> String {
        func p(_ m: Int) -> String { (m < 0 ? "-" : "") + String(format: "%d.%02d", abs(m) / 100, abs(m) % 100) }
        var balance = 124_700
        var out = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\n"
        for row in englishRows { balance += row.minor; out += "CARD_PAYMENT,Current,\(row.day) 10:15:00,\(row.day) 10:15:09,\"\(row.text)\",\(p(row.minor)),0.00,GBP,COMPLETED,\(p(balance))\n" }
        return out
    }

    private static let contract = """
    UMOWA NAJMU LOKALU MIESZKALNEGO

    zawarta w Krakowie w dniu 1 marca 2026 roku pomiędzy Janem Kowalskim, zamieszkałym w Krakowie przy ul. Długiej 12, zwanym dalej Wynajmującym, a Anną Nowak, zamieszkałą w Warszawie, zwaną dalej Najemcą.

    § 1. Przedmiotem najmu jest lokal mieszkalny nr 14 o powierzchni 48 m² położony w Krakowie przy ul. Floriańskiej 7, składający się z dwóch pokoi, kuchni i łazienki. Lokal wyposażony jest w meble i sprzęt AGD wymienione w załączniku nr 1.

    § 2. Najemca zobowiązuje się płacić czynsz w wysokości 2400,00 zł miesięcznie, płatny z góry do 10 dnia każdego miesiąca przelewem na rachunek Wynajmującego. Czynsz nie obejmuje opłat za media (prąd, gaz, woda, internet), które Najemca płaci według zużycia.

    § 3. W dniu podpisania umowy Najemca wpłaca kaucję zabezpieczającą w wysokości 4800,00 zł. Kaucja zostanie zwrócona w ciągu 30 dni od zakończenia najmu, po potrąceniu ewentualnych zaległości oraz kosztów napraw wykraczających poza normalne zużycie lokalu.

    § 4. Umowa zostaje zawarta na czas określony od 1 marca 2026 roku do 28 lutego 2027 roku. Każda ze stron może wypowiedzieć umowę z zachowaniem trzymiesięcznego okresu wypowiedzenia. Wypowiedzenie wymaga formy pisemnej pod rygorem nieważności.

    § 5. W przypadku opóźnienia w płatności czynszu dłuższego niż 14 dni Wynajmujący może naliczyć odsetki ustawowe za opóźnienie oraz karę umowną w wysokości 150,00 zł.

    § 6. Najemca nie może podnajmować lokalu ani oddawać go do używania osobom trzecim bez pisemnej zgody Wynajmującego. Zabronione jest również prowadzenie w lokalu działalności gospodarczej.

    § 7. Najemca ma prawo utrzymywać w lokalu jednego psa lub jednego kota. Posiadanie innych zwierząt wymaga pisemnej zgody Wynajmującego.

    § 8. Wynajmujący zobowiązuje się do wykonania napraw wykraczających poza drobne bieżące naprawy w terminie 14 dni od zgłoszenia przez Najemcę.

    § 9. Wszelkie zmiany niniejszej umowy wymagają formy pisemnej. W sprawach nieuregulowanych stosuje się przepisy Kodeksu cywilnego. Spory rozstrzyga sąd właściwy dla miejsca położenia lokalu.

    § 10. Umowę sporządzono w dwóch jednobrzmiących egzemplarzach, po jednym dla każdej ze stron.

    Załącznik nr 1. Protokół zdawczo-odbiorczy. Stan liczników w dniu przekazania lokalu: prąd 12345 kWh, gaz 678 m³, woda zimna 234 m³, woda ciepła 112 m³. Przekazano dwa komplety kluczy.
    """

    private static let invoice = """
    INVOICE No. 2026/03/114

    Issue date: 12 March 2026
    Seller: Brightside Studio Ltd, 14 Mill Lane, Leeds LS1 4AB, VAT no. GB123456789
    Buyer: Harbor Foods Ltd, 8 Quay Street, Manchester M3 4AA

    Description: Website design, 40 hours at £75.00 per hour: £3,000.00
    Description: Hosting and maintenance, 12 months at £25.00 per month: £300.00

    Subtotal: £3,300.00
    VAT at 20%: £660.00
    Total due: £3,960.00

    Payment is due by 11 April 2026. Late payments are charged interest of 2% per month. Please pay by bank transfer to Brightside Studio Ltd, sort code 12-34-56, account number 12345678, quoting the invoice number.
    """

    // MARK: Scoring helpers

    private func numberMatches(_ answer: String, cents expected: Int) -> Bool {
        NumberGrounding.numberCents(in: answer).contains { abs($0 - expected) <= 1 }
    }

    private func setup() async throws -> (LlamaCppProvider, ModelStore) {
        guard let path = ProcessInfo.processInfo.environment["LOLEK_MODEL_DIR"], !path.isEmpty else { throw XCTSkip("set LOLEK_MODEL_DIR") }
        let store = ModelStore(directory: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        guard FileManager.default.fileExists(atPath: store.path(for: LocalModels.qwen35).path) else { throw XCTSkip("Qwen model not found") }
        if !store.isInstalled(LocalModels.qwen35) { try store.markVerified(LocalModels.qwen35) }
        return (LlamaCppProvider(model: LocalModels.qwen35, store: store), store)
    }

    private struct AllowAll: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }

    // MARK: Statement questions

    private struct Question {
        let text: String; let language: ConversationLanguage
        /// Any one of these (in cents) in the answer counts as correct; all of `all` must appear for multi-part answers.
        let anyOf: [Int]; let all: [Int]
        init(_ text: String, _ language: ConversationLanguage, anyOf: [Int] = [], all: [Int] = []) { self.text = text; self.language = language; self.anyOf = anyOf; self.all = all }
    }

    func testStatementQuestionAnswering() async throws {
        let (provider, _) = try await setup()
        let polish = DocumentStore(fileURL: nil), english = DocumentStore(fileURL: nil)
        _ = try await DocumentIngestor.ingest(data: Data(Self.mbankCSV().utf8), fileName: "mbank-marzec.csv", into: polish)
        _ = try await DocumentIngestor.ingest(data: Data(Self.revolutCSV().utf8), fileName: "revolut-march.csv", into: english)

        let polishQuestions = [
            Question("Ile wydałem na zakupy spożywcze w marcu?", .pl, anyOf: [23_620]),
            Question("Ile wpłynęło na moje konto w marcu?", .pl, anyOf: [854_500, 850_000]),
            Question("Jakie mam subskrypcje i ile kosztują?", .pl, all: [5_299, 2_900]),
            Question("Jaka była moja największa płatność?", .pl, anyOf: [240_000]),
            Question("Ile zapłaciłem za Ubera?", .pl, anyOf: [6_490]),
            Question("Ile zapłaciłem opłat bankowych?", .pl, anyOf: [3_500]),
            Question("Ile gotówki wypłaciłem z bankomatu?", .pl, anyOf: [12_000]),
            Question("Jakie było saldo na koniec miesiąca?", .pl, anyOf: [879_907]),
            Question("Ile wydałem łącznie w marcu?", .pl, anyOf: [474_593, 354_593]),
            Question("Ile kosztuje mnie Orange?", .pl, anyOf: [21_000]),
            // Added after the planner was written, to see whether it generalises:
            Question("Ile wydałem na paliwo?", .pl, anyOf: [8_735]),
            Question("Czy płaciłem za Netflixa i ile?", .pl, anyOf: [5_299]),
            Question("Ile zapłaciłem w sumie za rachunki i telefon?", .pl, anyOf: [25_999]),
            Question("Ile odłożyłem na oszczędności?", .pl, anyOf: [120_000]),
            Question("Czy dostałem jakiś zwrot?", .pl, anyOf: [4_500]),
            Question("Ile wydałem w McDonaldzie?", .pl, anyOf: [6_150]),
        ]
        let englishQuestions = [
            Question("How much did I spend at Tesco?", .en, anyOf: [1_250]),
            Question("What was my biggest expense?", .en, anyOf: [80_000]),
            Question("How much did I pay for subscriptions?", .en, anyOf: [2_098], all: []),
            Question("How much money came in this month?", .en, anyOf: [216_999, 215_000]),
            Question("How much cash did I withdraw?", .en, anyOf: [2_000]),
            Question("What did I pay British Gas?", .en, anyOf: [6_500]),
            Question("What did I spend at Pret?", .en, anyOf: [1_720]),
            Question("How much did I pay in fees?", .en, anyOf: [1_800]),
            Question("How much did I spend on groceries?", .en, anyOf: [3_890]),
            Question("Did I get any refunds?", .en, anyOf: [1_999]),
        ]

        var passed = 0, total = 0
        var report: [String] = []
        for (store, questions) in [(polish, polishQuestions), (english, englishQuestions)] {
            let tools = DocumentToolbox.tools(store: store)
            for question in questions {
                let session = AgentSession(mode: .lolek, provider: provider, registry: ToolRegistry(tools), approvalHandler: AllowAll(), language: question.language, verifier: GroundingVerifier(), planner: DocumentPlanner(store: store))
                let started = Date()
                let added = try await session.send(question.text)
                let answer = added.last?.text ?? ""
                let correct = (question.anyOf.isEmpty || question.anyOf.contains { numberMatches(answer, cents: $0) })
                    && question.all.allSatisfy { numberMatches(answer, cents: $0) }
                // "Subscriptions" in English: giving both prices is as good as the total.
                let englishSubs = question.text.contains("subscriptions") && numberMatches(answer, cents: 1_099) && numberMatches(answer, cents: 999)
                let ok = correct || englishSubs
                total += 1; if ok { passed += 1 }
                let calls = added.flatMap(\.toolCalls).map(\.name).joined(separator: ",")
                report.append("  \(ok ? "PASS" : "FAIL") \(question.text) [\(calls)] \(String(format: "%.0f", Date().timeIntervalSince(started)))s → \(answer.replacingOccurrences(of: "\n", with: " ").prefix(150))")
            }
        }
        print("\n=== STATEMENT Q&A: \(passed)/\(total) ===\n" + report.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(passed, total * 3 / 5, "the harness should make a 4B model right most of the time")
    }

    // MARK: Narration

    func testStatementNarration() async throws {
        let (provider, _) = try await setup()
        var report: [String] = []
        for (csv, name, language) in [(Self.mbankCSV(), "mbank-marzec.csv", ConversationLanguage.pl), (Self.revolutCSV(), "revolut-march.csv", .en)] {
            let store = DocumentStore(fileURL: nil)
            let document = try await DocumentIngestor.ingest(data: Data(csv.utf8), fileName: name, into: store)
            let started = Date()
            // What the app shows when a statement is added: written by code. The model's own narration is printed for comparison.
            let coded = StatementSummaryText.make(try XCTUnwrap(document.statement), language: language)
            report.append("[\(name)] code-written summary:\n\(coded)")
            let narration = try await StatementNarrator(generate: provider.documentGenerator(language: language)).narrate(try XCTUnwrap(document.statement), language: language)
            report.append("[\(name)] model narration (fallback used: \(narration.usedFallback), \(String(format: "%.0f", Date().timeIntervalSince(started)))s):\n\(narration.text)")
            XCTAssertEqual(NumberGrounding.ungrounded(answer: narration.text, sources: [StatementAnalyzer.digest(try XCTUnwrap(document.statement))]), [], "whatever is shown must be grounded")
        }
        print("\n=== STATEMENT NARRATION ===\n" + report.joined(separator: "\n\n"))
    }

    // MARK: Documents

    func testDocumentSummaryAndQuestions() async throws {
        let (provider, _) = try await setup()
        let store = DocumentStore(fileURL: nil)
        let contract = try await DocumentIngestor.ingest(data: Data(Self.contract.utf8), fileName: "umowa-najmu.txt", into: store)
        let invoice = try await DocumentIngestor.ingest(data: Data(Self.invoice.utf8), fileName: "invoice-114.txt", into: store)

        var report: [String] = []
        // Summaries: compare the two strategies on the same documents.
        for (document, language, facts) in [
            (contract, ConversationLanguage.pl, [["2400"], ["4800"], ["28 lutego 2027", "2027-02-28", "28.02.2027"], ["trzymiesięczn", "3 miesi", "trzy miesi"], ["150", "14 dni"]]),
            (invoice, .en, [["3,960", "3960"], ["660"], ["11 april 2026", "2026-04-11"], ["3,000", "3000"], ["2%"]]),
        ] {
            for strategy in [DocumentSummarizer.Strategy.extractive, .mapReduce] {
                let started = Date()
                let summary = try await DocumentSummarizer(strategy: strategy, generate: provider.documentGenerator(language: language)).summarize(chunks: document.chunks, language: language)
                let found = facts.filter { alternatives in alternatives.contains { summary.folded.contains($0.folded) } }.count
                report.append("[summary \(document.name), \(strategy)] \(found)/\(facts.count) key facts, \(String(format: "%.0f", Date().timeIntervalSince(started)))s\n\(summary)")
                if strategy == .extractive {
                    await store.setSummary(summary, for: document.id)
                    XCTAssertGreaterThanOrEqual(found, 4, "\(document.name) extractive summary lost key facts:\n\(summary)")
                }
            }
        }

        // Questions through the search tool
        let questions: [(String, ConversationLanguage, [String], [String])] = [
            ("Ile wynosi kaucja?", .pl, ["4800", "4 800"], []), ("Do kiedy trwa umowa najmu?", .pl, ["28 lutego 2027", "28.02.2027", "2027-02-28"], []),
            ("Jaki jest okres wypowiedzenia umowy?", .pl, ["trzy", "3 miesi", "trzymiesięczn"], []),
            // The contract allows one dog or cat: "no" would be a wrong answer.
            ("Czy mogę mieć psa?", .pl, ["tak", "jednego psa", "jeden pies", "możesz mieć"], ["nie możesz", "nie wolno", "zabronion"]),
            ("Jaki był stan licznika prądu przy przekazaniu lokalu?", .pl, ["12345", "12 345"], []),
            // Known limit: keyword search cannot bridge "wynająć komuś" and "podnajem". Counted, not hidden.
            ("Czy mogę wynająć pokój komuś innemu?", .pl, ["zgod", "podnajm"], ["tak, możesz", "prywatnym asystentem"]),
            ("What is the total due on the invoice?", .en, ["3,960", "3960"], []), ("When is the invoice payment due?", .en, ["11 april 2026", "april 11"], []),
            ("How much VAT is on the invoice?", .en, ["660"], []), ("What happens if I pay late?", .en, ["2%", "interest"], []),
        ]
        var qaPassed = 0
        let tools = DocumentToolbox.tools(store: store)
        for (question, language, expected, forbidden) in questions {
            let session = AgentSession(mode: .lolek, provider: provider, registry: ToolRegistry(tools), approvalHandler: AllowAll(), language: language, verifier: GroundingVerifier(), planner: DocumentPlanner(store: store))
            let started = Date()
            let added = try await session.send(question)
            let answer = added.last?.text ?? ""
            let ok = expected.contains { answer.folded.contains($0.folded) } && !forbidden.contains { answer.folded.contains($0.folded) }
            if ok { qaPassed += 1 }
            report.append("  \(ok ? "PASS" : "FAIL") \(question) [\(added.flatMap(\.toolCalls).map(\.name).joined(separator: ","))] \(String(format: "%.0f", Date().timeIntervalSince(started)))s → \(answer.replacingOccurrences(of: "\n", with: " ").prefix(140))")
        }
        print("\n=== DOCUMENTS: Q&A \(qaPassed)/\(questions.count) ===\n" + report.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(qaPassed, questions.count * 8 / 10)
    }
}
