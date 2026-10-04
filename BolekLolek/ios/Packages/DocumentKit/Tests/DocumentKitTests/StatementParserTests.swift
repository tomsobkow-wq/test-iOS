import XCTest
@testable import DocumentKit

final class StatementParserTests: XCTestCase {
    private func check(_ statement: ParsedStatement?, truth: [TruthRow], opening: Int, label: String, categories: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let parsed = try XCTUnwrap(statement, "\(label): not parsed", file: file, line: line)
        XCTAssertEqual(parsed.transactions.count, truth.count, "\(label): transaction count", file: file, line: line)
        XCTAssertEqual(parsed.transactions.map(\.minorUnits), truth.map(\.minor), "\(label): amounts and signs", file: file, line: line)
        XCTAssertEqual(parsed.transactions.map { DateParsing.isoString($0.date) }, truth.map(\.day), "\(label): dates", file: file, line: line)
        XCTAssertEqual(parsed.reconciliation, .matches, "\(label): reconciliation \(parsed.warnings)", file: file, line: line)
        if categories {
            for (tx, row) in zip(parsed.transactions, truth) {
                if let category = row.category { XCTAssertEqual(tx.category, category, "\(label): category of \(row.text)", file: file, line: line) }
                if let merchant = row.merchant { XCTAssertEqual(tx.merchant, merchant, "\(label): merchant of \(row.text)", file: file, line: line) }
            }
        }
    }

    // MARK: CSV exports

    func testMBankStyleCSV() throws {
        let parsed = StatementParser.parse(Fixtures.mbankCSV())
        try check(parsed, truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "mBank CSV")
        XCTAssertEqual(parsed?.bank, "mBank")
        XCTAssertEqual(parsed?.openingMinor, Fixtures.polishOpening)
        XCTAssertEqual(parsed?.currency, "PLN")
    }

    func testPKOStyleCSVNewestFirst() throws {
        let parsed = StatementParser.parse(Fixtures.pkoCSV())
        try check(parsed, truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "PKO CSV")
    }

    func testINGStyleCSVWithCounterpartyAndNoiseColumns() throws {
        let parsed = StatementParser.parse(Fixtures.ingCSV())
        try check(parsed, truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "ING CSV", categories: false)
        XCTAssertEqual(parsed?.transactions.first?.category, "income")
    }

    func testRevolutStyleEnglishCSV() throws {
        let parsed = StatementParser.parse(Fixtures.revolutCSV())
        try check(parsed, truth: Fixtures.english, opening: Fixtures.englishOpening, label: "Revolut CSV")
        XCTAssertEqual(parsed?.currency, "GBP")
        XCTAssertEqual(parsed?.bank, "Revolut")
    }

    func testChaseStyleMonthFirstDatesWithoutBalance() throws {
        let parsed = try XCTUnwrap(StatementParser.parse(Fixtures.chaseCSV()))
        XCTAssertEqual(parsed.transactions.map { DateParsing.isoString($0.date) }, Fixtures.english.map(\.day), "03/15/2026 must read as 15 March")
        XCTAssertEqual(parsed.transactions.map(\.minorUnits), Fixtures.english.map(\.minor))
        XCTAssertEqual(parsed.reconciliation, .unknown, "no balances to check against")
    }

    func testWindows1250EncodedCSVIsDecoded() throws {
        let csv = Fixtures.mbankCSV()
        let data = try XCTUnwrap(csv.data(using: .windowsCP1250))
        XCTAssertNil(String(data: data, encoding: .utf8), "test needs bytes that are not valid UTF-8")
        let decoded = TextDecoding.decode(data)
        XCTAssertTrue(decoded.contains("PŁATNOŚĆ KARTĄ BIEDRONKA"))
        try check(StatementParser.parse(decoded), truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "cp1250 CSV")
    }

    // MARK: Text from PDFs

    func testPolishPDFText() throws {
        let parsed = StatementParser.parse(Fixtures.polishPDFText())
        try check(parsed, truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "PL PDF text")
        XCTAssertEqual(parsed?.openingMinor, Fixtures.polishOpening)
        XCTAssertEqual(parsed?.accountHint, "…2874")
    }

    func testUKPDFTextSignsComeFromTheRunningBalance() throws {
        let parsed = StatementParser.parse(Fixtures.ukPDFText())
        try check(parsed, truth: Fixtures.english, opening: Fixtures.englishOpening, label: "UK PDF text")
        XCTAssertEqual(parsed?.transactions.first?.minorUnits, 215_000, "the salary has no sign but the balance went up")
    }

    func testMultilinePDFText() throws {
        try check(StatementParser.parse(Fixtures.multilinePDFText()), truth: Fixtures.polish, opening: Fixtures.polishOpening, label: "multiline PDF text")
    }

    func testNonStatementsAreRejected() {
        XCTAssertNil(StatementParser.parse("Umowa najmu lokalu mieszkalnego zawarta w dniu 1 marca 2026 roku pomiędzy Janem Kowalskim a Anną Nowak.\nCzynsz wynosi 2400,00 zł miesięcznie.\nKaucja 4800,00 zł."))
        XCTAssertNil(StatementParser.parse("hello"))
    }

    func testDamagedStatementIsFlaggedNotTrusted() throws {
        // Drop one line from the middle: the parse still works but must not claim to reconcile.
        var lines = Fixtures.polishPDFText().components(separatedBy: "\n")
        let index = try XCTUnwrap(lines.firstIndex { $0.contains("UBER") })
        lines.remove(at: index)
        let parsed = try XCTUnwrap(StatementParser.parse(lines.joined(separator: "\n")))
        XCTAssertEqual(parsed.reconciliation, .mismatch)
        XCTAssertFalse(parsed.warnings.isEmpty)
    }

    // MARK: Building blocks

    func testSignedMoneyFormats() {
        XCTAssertEqual(SignedMoney.parse("-45,60")?.minorUnits, -4560)
        XCTAssertEqual(SignedMoney.parse("−1 234,50 zł")?.minorUnits, -123_450)
        XCTAssertEqual(SignedMoney.parse("(45.60)")?.minorUnits, -4560)
        XCTAssertEqual(SignedMoney.parse("45.60-")?.minorUnits, -4560)
        XCTAssertEqual(SignedMoney.parse("45.60 DR")?.minorUnits, -4560)
        XCTAssertEqual(SignedMoney.parse("45.60 CR")?.minorUnits, 4560)
        XCTAssertEqual(SignedMoney.parse("+2 500,00")?.minorUnits, 250_000)
        XCTAssertEqual(SignedMoney.parse("£1,234.50")?.minorUnits, 123_450)
        XCTAssertEqual(SignedMoney.parse("$-45.60")?.minorUnits, -4560)
        XCTAssertNil(SignedMoney.parse("abc"))
    }

    func testDateFormatsPolishAndEnglish() {
        let utc = { (s: String, order: DayOrder) in DateParsing.parse(s, order: order).map(DateParsing.isoString) }
        XCTAssertEqual(utc("2026-03-02", .dayFirst), "2026-03-02")
        XCTAssertEqual(utc("02.03.2026", .dayFirst), "2026-03-02")
        XCTAssertEqual(utc("02-03-26", .dayFirst), "2026-03-02")
        XCTAssertEqual(utc("03/02/2026", .monthFirst), "2026-03-02")
        XCTAssertEqual(utc("2 marca 2026", .dayFirst), "2026-03-02")
        XCTAssertEqual(utc("2 października 2026", .dayFirst), "2026-10-02")
        XCTAssertEqual(utc("12 Mar 2026", .dayFirst), "2026-03-12")
        XCTAssertEqual(utc("Mar 12, 2026", .dayFirst), "2026-03-12")
        XCTAssertEqual(utc("2026-03-02 14:31:05", .dayFirst), "2026-03-02")
        XCTAssertNil(utc("31.02.2026", .dayFirst), "there is no 31 February")
        XCTAssertEqual(DateParsing.detectOrder(["03/02/2026", "03/15/2026"]), .monthFirst)
        XCTAssertEqual(DateParsing.detectOrder(["15/03/2026", "03/02/2026"]), .dayFirst)
    }

    func testMerchantCleaning() {
        XCTAssertEqual(Merchants.cleanName("PŁATNOŚĆ KARTĄ 02.03 KAWIARNIA POD LIPĄ 5521 WARSZAWA PL"), "Restaurant or café")
        XCTAssertEqual(Merchants.cleanName("PŁATNOŚĆ KARTĄ SKLEP ROWEROWY KOWALSKI 9981234 GDAŃSK"), "Sklep Rowerowy Kowalski")
        XCTAssertEqual(Merchants.cleanName("Przelew zewnętrzny PHU Janusz Nowak"), "PHU Janusz Nowak")
        XCTAssertEqual(Merchants.cleanName("Card payment to ACME WIDGETS LTD 4412"), "Acme Widgets LTD")
    }

    func testCSVReaderHandlesQuotesAndDelimiters() {
        XCTAssertEqual(CSVReader.rows("a;b;c\n1;\"x;y\";3\n"), [["a", "b", "c"], ["1", "x;y", "3"]])
        XCTAssertEqual(CSVReader.rows("a,b\n\"he said \"\"hi\"\"\",2\n"), [["a", "b"], ["he said \"hi\"", "2"]])
    }
}
