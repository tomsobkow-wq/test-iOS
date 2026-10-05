import AgentCore
import XCTest
@testable import DocumentKit

private actor Calls {
    var items: [(system: String, user: String)] = []
    func add(_ system: String, _ user: String) { items.append((system, user)) }
}

final class GroundingTests: XCTestCase {
    func testFormatsOfTheSameNumberAreRecognised() {
        let source = ["Money out: 4745.93 PLN"]
        for answer in ["wydałeś 4745,93 zł", "wydałeś 4 745,93 zł", "you spent 4,745.93", "4745.93"] {
            XCTAssertEqual(NumberGrounding.ungrounded(answer: answer, sources: source), [], answer)
        }
        XCTAssertEqual(NumberGrounding.ungrounded(answer: "wydałeś 4754,93 zł", sources: source), ["4754,93"])
    }

    func testSmallWholeNumbersYearsAndPercentsAreFree() {
        XCTAssertEqual(NumberGrounding.ungrounded(answer: "3 transakcje, 17 marca 2026, 67% budżetu, o 06:30", sources: ["nothing here"]), [])
    }

    func testRoundingIsToleratedButInventionIsNot() {
        let source = ["Money out: 4745.93 PLN"]
        XCTAssertEqual(NumberGrounding.ungrounded(answer: "około 4746 zł", sources: source), [])
        XCTAssertEqual(NumberGrounding.ungrounded(answer: "około 5000 zł", sources: source), ["5000"])
        XCTAssertEqual(NumberGrounding.ungrounded(answer: "1,234 zł", sources: ["1234.00 PLN"]), [], "1,234 is a thousands separator")
    }

    func testUngroundedLinesAreRemoved() {
        let summary = "Umowa najmu.\n- Czynsz 2400,00 zł.\n- Kara 9999,00 zł za zwłokę."
        let cleaned = NumberGrounding.removeUngroundedLines(from: summary, sources: ["Czynsz wynosi 2400,00 zł"])
        XCTAssertEqual(cleaned, "Umowa najmu.\n- Czynsz 2400,00 zł.")
    }
}

final class SummarizerTests: XCTestCase {
    private func chunks(_ n: Int) -> [DocumentChunk] {
        (0..<n).map { i in
            DocumentChunk(id: i, text: i == 17 ? "Umowa: kwota 2400,00 zł, termin płatności 10 dnia, kara umowna 500,00 zł, wypowiedzenie pisemne." : "Postanowienie ogólne numer \(i) dotyczy porządku.", page: nil)
        }
    }

    func testSelectionKeepsEndsAndTheInformativePart() {
        let picked = DocumentSummarizer.select(chunks(30), cap: 12)
        XCTAssertEqual(picked.count, 12)
        XCTAssertTrue([0, 1, 29].allSatisfy { id in picked.contains { $0.id == id } })
        XCTAssertTrue(picked.contains { $0.id == 17 }, "the chunk full of amounts and deadlines must be read")
        XCTAssertEqual(picked.map(\.id), picked.map(\.id).sorted(), "document order is kept")
        XCTAssertEqual(DocumentSummarizer.select(chunks(5), cap: 12).count, 5)
    }

    func testMapReduceCallsAndProgress() async throws {
        let calls = Calls()
        let progress = Calls()
        let summarizer = DocumentSummarizer(strategy: .mapReduce, maxParts: 12) { system, user, _ in
            await calls.add(system, user)
            if system.contains("one part") { return "Fragment \(user.prefix(30)). Czynsz 2400,00 zł." }
            if system.contains("Merge") { return "Scalona notatka. Czynsz 2400,00 zł." }
            return "Umowa najmu.\n- Czynsz 2400,00 zł.\n- Kara 9999,00 zł."
        }
        let summary = try await summarizer.summarize(chunks: chunks(30), language: .pl) { done, total in
            Task { await progress.add("\(done)", "\(total)") }
        }
        let log = await calls.items
        XCTAssertEqual(log.filter { $0.system.contains("one part") }.count, 12, "one model call per selected part")
        XCTAssertEqual(log.filter { $0.system.contains("Merge") }.count, 2, "12 notes are merged in two groups of 6 before the final summary")
        XCTAssertEqual(log.last?.system.contains("Write a clear summary"), true)
        XCTAssertTrue(summary.contains("Czynsz 2400,00 zł"))
        XCTAssertFalse(summary.contains("9999"), "an invented number is stripped")
        XCTAssertTrue(summary.contains("12 najbardziej treściwych z 30"), summary)
    }

    func testShortDocumentIsOneCallPlusFinal() async throws {
        let calls = Calls()
        let summarizer = DocumentSummarizer(strategy: .mapReduce) { system, user, _ in
            await calls.add(system, user)
            return system.contains("one part") ? "Notatka o czynszu 2400,00 zł." : "To jest umowa. Czynsz 2400,00 zł."
        }
        let summary = try await summarizer.summarize(chunks: Array(chunks(18)[16...17]), language: .pl)
        let count = await calls.items.count
        XCTAssertEqual(count, 3, "two parts plus the final merge")
        XCTAssertFalse(summary.contains("najbardziej"), "nothing was skipped, so no caveat")
    }

    func testBoilerplateOnlyDocument() async throws {
        let summarizer = DocumentSummarizer(strategy: .mapReduce) { _, _, _ in "nothing important" }
        let summary = try await summarizer.summarize(chunks: chunks(3), language: .en)
        XCTAssertTrue(summary.contains("nothing important to summarise"))
    }
}

final class ExtractiveSummaryTests: XCTestCase {
    private let contract = """
    UMOWA NAJMU LOKALU MIESZKALNEGO zawarta w Krakowie pomiędzy Janem Kowalskim, zwanym Wynajmującym, a Anną Nowak, zwaną Najemcą.

    Przedmiotem najmu jest lokal mieszkalny składający się z dwóch pokoi, kuchni i łazienki, wyposażony w meble.

    Najemca zobowiązuje się płacić czynsz w wysokości 2400,00 zł miesięcznie, płatny do 10 dnia każdego miesiąca.

    Najemca wpłaca kaucję w wysokości 4800,00 zł, zwracaną w ciągu 30 dni od końca umowy.

    Strony zgodnie oświadczają, że lokal jest czysty i schludny oraz znajduje się w dobrym stanie ogólnym.

    Umowa zostaje zawarta na czas określony do 28 lutego 2027 roku, z trzymiesięcznym okresem wypowiedzenia.
    """

    func testBriefKeepsTheFactSentencesAndTheOpening() {
        let brief = ExtractiveBrief.build(from: Chunker.chunk(contract))
        for fact in ["2400,00 zł", "4800,00 zł", "28 lutego 2027", "trzymiesięcznym", "UMOWA NAJMU"] { XCTAssertTrue(brief.contains(fact), "missing \(fact):\n\(brief)") }
        XCTAssertFalse(brief.contains("czysty i schludny"), "filler sentences are left out when there is a budget")
    }

    func testBriefRespectsTheBudgetAndKeepsDocumentOrder() {
        let long = (1...200).map { "Postanowienie numer \($0) przewiduje płatność w wysokości \($0 * 10),00 zł w terminie \($0) dni." }.joined(separator: " ")
        let brief = ExtractiveBrief.build(from: Chunker.chunk(long), budgetCharacters: 1_200)
        XCTAssertLessThanOrEqual(brief.count, 1_800)
        let numbers = brief.components(separatedBy: "numer ").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
        XCTAssertEqual(numbers, numbers.sorted())
    }

    func testExtractiveSummaryIsOneModelCallOverTheBrief() async throws {
        let calls = Calls()
        let summarizer = DocumentSummarizer { system, user, _ in
            await calls.add(system, user)
            return "To umowa najmu.\n- Czynsz 2400,00 zł miesięcznie.\n- Kara 9999,00 zł."
        }
        let summary = try await summarizer.summarize(chunks: Chunker.chunk(contract), language: .pl)
        let log = await calls.items
        XCTAssertEqual(log.count, 1)
        XCTAssertTrue(log[0].user.contains("4800,00 zł"), "the model is shown the extracted facts")
        XCTAssertTrue(summary.contains("2400,00"))
        XCTAssertFalse(summary.contains("9999"), "an invented amount is dropped")
    }

    func testEmptyModelAnswerFallsBackToTheExtracts() async throws {
        let summarizer = DocumentSummarizer { _, _, _ in "" }
        let summary = try await summarizer.summarize(chunks: Chunker.chunk(contract), language: .pl)
        XCTAssertTrue(summary.contains("2400,00 zł"), "never return nothing")
    }
}

final class InvoiceBriefTests: XCTestCase {
    func testShortFigureLinesSurvive() {
        let invoice = "INVOICE No. 2026/03/114\n\nSeller: Brightside Studio Ltd, 14 Mill Lane, Leeds.\n\nSubtotal: £3,300.00\nVAT at 20%: £660.00\nTotal due: £3,960.00\n\nPayment is due by 11 April 2026."
        let brief = ExtractiveBrief.build(from: Chunker.chunk(invoice))
        for fact in ["£3,300.00", "£660.00", "£3,960.00", "11 April 2026"] { XCTAssertTrue(brief.contains(fact), "missing \(fact):\n\(brief)") }
    }
}

final class NarratorTests: XCTestCase {
    private func statement() throws -> ParsedStatement { try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV())) }

    func testGoodNarrationIsUsedAsIs() async throws {
        let narrator = StatementNarrator { _, _, _ in "W marcu wpłynęło 8545.00 PLN, a wyszło 4745.93 PLN." }
        let result = try await narrator.narrate(try statement(), language: .pl)
        XCTAssertFalse(result.usedFallback)
    }

    func testWrongNumberGetsOneRetry() async throws {
        let calls = Calls()
        let narrator = StatementNarrator { system, user, _ in
            await calls.add(system, user)
            return await calls.items.count == 1 ? "Wydano 4754.93 PLN." : "Wydano 4745.93 PLN."
        }
        let result = try await narrator.narrate(try statement(), language: .pl)
        let log = await calls.items
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(log[1].user.contains("4754.93"), "the retry names the bad number")
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.text.contains("4745.93"))
    }

    func testPersistentlyWrongNumbersFallBackToCodeWrittenText() async throws {
        let narrator = StatementNarrator { _, _, _ in "Wydano 1111.11 PLN." }
        let result = try await narrator.narrate(try statement(), language: .pl)
        XCTAssertTrue(result.usedFallback)
        XCTAssertTrue(result.text.contains("Wydatki: 4745.93 PLN"), result.text)
        XCTAssertTrue(result.text.contains("mieszkanie 2400.00 PLN"), result.text)
        XCTAssertTrue(result.text.contains("17 transakcji"), result.text)
        XCTAssertEqual(NumberGrounding.ungrounded(answer: result.text, sources: [StatementAnalyzer.digest(try statement())]), [], "the fallback itself must be grounded")
    }
}

final class StatementSummaryTextTests: XCTestCase {
    func testPolishPluralsAndFacts() throws {
        let statement = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        let text = StatementSummaryText.make(statement, language: .pl)
        XCTAssertTrue(text.contains("17 transakcji"))
        XCTAssertTrue(text.contains("Saldo początkowe 5000.00 PLN, końcowe 8799.07 PLN"), text)
        XCTAssertTrue(text.contains("opłaty bankowe 35.00 PLN"), text)
        XCTAssertTrue(text.contains("Netflix 52.99 PLN"), text)
        XCTAssertEqual(NumberGrounding.ungrounded(answer: text, sources: [StatementAnalyzer.digest(statement)]), [], "every number comes from the data")
        let english = StatementSummaryText.make(try XCTUnwrap(StatementParser.parse(Fixtures.revolutCSV())), language: .en)
        XCTAssertTrue(english.contains("Money in: 2169.99 GBP"), english)
        XCTAssertFalse(english.contains("transakcji"))
    }
}

final class VerifierLoopTests: XCTestCase {
    private struct Script: ModelProvider {
        let answers: [String]
        let seen: Calls
        var profile: ModelProfile { .qwen35_4B }
        func respond(to request: ModelRequest) async throws -> ModelResponse {
            await seen.add(request.messages.last?.text ?? "", String(request.tools.count))
            let step = await seen.items.count
            // Step 1 calls the statement tool; later steps answer from the script.
            if step == 1 { return ModelResponse(toolCalls: [ToolCall(name: "statement_transactions", argumentsJSON: #"{"category":"groceries"}"#)]) }
            return ModelResponse(text: answers[min(step - 2, answers.count - 1)])
        }
    }
    private struct Allow: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }

    private func session(answers: [String], seen: Calls) async throws -> AgentSession {
        let store = DocumentStore(fileURL: nil)
        let parsed = try XCTUnwrap(StatementParser.parse(Fixtures.mbankCSV()))
        await store.add(StoredDocument(id: "d1", name: "s.csv", kind: .statement, addedAt: Date(), pageCount: nil, chunks: [], statement: parsed, summary: nil, characterCount: 1))
        return AgentSession(mode: .lolek, provider: Script(answers: answers, seen: seen), registry: ToolRegistry(DocumentToolbox.tools(store: store)),
                            approvalHandler: Allow(), language: .pl, verifier: GroundingVerifier())
    }

    func testWrongFigureIsSentBackOnceAndTheCorrectionIsNotStored() async throws {
        let seen = Calls()
        let session = try await session(answers: ["Na jedzenie wydałeś 250,00 zł.", "Na zakupy spożywcze wydałeś 236.20 PLN."], seen: seen)
        let added = try await session.send("Ile wydałem na jedzenie?")
        XCTAssertEqual(added.last?.text, "Na zakupy spożywcze wydałeś 236.20 PLN.")
        let log = await seen.items
        XCTAssertEqual(log.count, 3, "tool call, first answer, one rewrite")
        XCTAssertTrue(log[2].system.contains("250,00"), "the rewrite request names the bad number")
        XCTAssertFalse(added.contains { $0.text.contains("nie ma w danych") }, "the correction stays out of the conversation")
    }

    func testStillWrongAfterTheRewriteGetsACaution() async throws {
        let seen = Calls()
        let session = try await session(answers: ["Wydałeś 250,00 zł.", "Wydałeś 251,00 zł."], seen: seen)
        let added = try await session.send("Ile wydałem na jedzenie?")
        XCTAssertTrue(added.last?.text.contains("Sprawdź dokładne kwoty") == true, added.last?.text ?? "")
    }

    func testCorrectAnswerIsLeftAlone() async throws {
        let seen = Calls()
        let session = try await session(answers: ["Wydałeś 236.20 PLN na 3 transakcje."], seen: seen)
        let added = try await session.send("Ile wydałem na jedzenie?")
        XCTAssertEqual(added.last?.text, "Wydałeś 236.20 PLN na 3 transakcje.")
        let count = await seen.items.count
        XCTAssertEqual(count, 2)
    }
}
