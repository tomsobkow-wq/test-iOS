import CoreGraphics
import CoreText
import XCTest
@testable import DocumentKit

#if canImport(AppKit)
import AppKit
#endif

/// Builds real PDFs and images so ingestion is tested on actual files, not strings.
enum TestFiles {
    static let pageSize = CGSize(width: 595, height: 842)

    private static func draw(lines: [String], in context: CGContext, fontSize: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        var y = pageSize.height - 50
        for line in lines {
            let attributed = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 40, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            y -= fontSize * 1.5
        }
    }

    /// A PDF with real, selectable text, split over pages.
    static func textPDF(lines: [String], linesPerPage: Int = 45) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for start in stride(from: 0, to: lines.count, by: linesPerPage) {
            context.beginPDFPage(nil)
            draw(lines: Array(lines[start..<min(start + linesPerPage, lines.count)]), in: context, fontSize: 10)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func bitmap(lines: [String], fontSize: CGFloat = 16, scale: CGFloat = 2) -> CGImage {
        let width = Int(pageSize.width * scale), height = Int(pageSize.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        draw(lines: lines, in: context, fontSize: fontSize)
        return context.makeImage()!
    }

    /// A "scanned" PDF: the page is only a picture, with no text inside.
    static func scannedPDF(lines: [String], fontSize: CGFloat = 14) -> Data {
        let image = bitmap(lines: lines, fontSize: fontSize)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

final class IngestionTests: XCTestCase {
    let contract = [
        "UMOWA NAJMU LOKALU MIESZKALNEGO",
        "zawarta w dniu 1 marca 2026 roku pomiędzy Janem Kowalskim a Anną Nowak.",
        "",
        "1. Czynsz najmu wynosi 2400,00 zł miesięcznie, płatny do 10 dnia każdego miesiąca.",
        "2. Najemca wpłaca kaucję w wysokości 4800,00 zł, zwracaną w ciągu 30 dni od końca umowy.",
        "3. Umowa zostaje zawarta na czas określony do 28 lutego 2027 roku.",
    ]

    func testTextPDFStatementIsRecognised() async throws {
        let store = DocumentStore(fileURL: nil)
        let pdf = TestFiles.textPDF(lines: Fixtures.polishPDFText().components(separatedBy: "\n"), linesPerPage: 12)
        let document = try await DocumentIngestor.ingest(data: pdf, fileName: "wyciag-03.pdf", into: store, recognizer: VisionTextRecognizer())
        XCTAssertEqual(document.kind, .statement)
        XCTAssertEqual(document.statement?.transactions.map(\.minorUnits), Fixtures.polish.map(\.minor))
        XCTAssertEqual(document.statement?.reconciliation, .matches)
        XCTAssertGreaterThan(document.pageCount ?? 0, 1)
        XCTAssertEqual(document.id, "d1")
    }

    func testTextPDFContractBecomesSearchableChunksWithPages() async throws {
        let store = DocumentStore(fileURL: nil)
        let lines = contract + (1...60).map { "Postanowienie dodatkowe numer \($0) dotyczy utrzymania lokalu w należytym stanie technicznym." }
        let document = try await DocumentIngestor.ingest(data: TestFiles.textPDF(lines: lines, linesPerPage: 30), fileName: "umowa.pdf", into: store)
        XCTAssertEqual(document.kind, .text)
        XCTAssertGreaterThan(document.chunks.count, 1)
        XCTAssertNotNil(document.chunks.first?.page)
        let hits = await store.search("kaucja ile wynosi", in: nil, limit: 1)
        XCTAssertTrue(hits.first?.chunk.text.contains("4800,00") == true, hits.first?.chunk.text ?? "no hit")
        XCTAssertEqual(hits.first?.chunk.page, 1)
    }

    func testScannedPDFIsReadWithOCR() async throws {
        let store = DocumentStore(fileURL: nil)
        let pdf = TestFiles.scannedPDF(lines: contract)
        // No recognizer: there is nothing to extract from a picture.
        do { _ = try await DocumentIngestor.ingest(data: pdf, fileName: "skan.pdf", into: store); XCTFail("expected noText") }
        catch { XCTAssertTrue(error is IngestError) }
        let document = try await DocumentIngestor.ingest(data: pdf, fileName: "skan.pdf", into: store, recognizer: VisionTextRecognizer())
        let text = document.chunks.map(\.text).joined(separator: " ")
        for expected in ["UMOWA", "kaucj", "4800", "2400"] { XCTAssertTrue(text.contains(expected), "OCR missed \(expected): \(text)") }
    }

    func testPhotoOfStatementIsReadWithOCR() async throws {
        let png = TestFiles.png(TestFiles.bitmap(lines: Fixtures.polishPDFText().components(separatedBy: "\n"), fontSize: 11))
        let store = DocumentStore(fileURL: nil)
        let document = try await DocumentIngestor.ingest(data: png, fileName: "zdjecie-wyciagu.png", into: store, recognizer: VisionTextRecognizer())
        XCTAssertEqual(document.kind, .statement, "OCR text should still parse as a statement: \(document.chunks.map(\.text))")
        let parsed = try XCTUnwrap(document.statement)
        print("OCR statement: \(parsed.transactions.count)/\(Fixtures.polish.count) transactions, reconciliation \(parsed.reconciliation), warnings \(parsed.warnings)")
        XCTAssertGreaterThanOrEqual(parsed.transactions.count, Fixtures.polish.count - 2)
    }

    func testCSVFileAndEncodingsAndErrors() async throws {
        let store = DocumentStore(fileURL: nil)
        let data = try XCTUnwrap(Fixtures.mbankCSV().data(using: .windowsCP1250))
        let doc = try await DocumentIngestor.ingest(data: data, fileName: "historia.csv", into: store)
        XCTAssertEqual(doc.kind, .statement)
        XCTAssertEqual(doc.statement?.transactions.count, 17)

        let second = try await DocumentIngestor.ingest(data: Data(Fixtures.revolutCSV().utf8), fileName: "revolut.csv", into: store)
        XCTAssertEqual(second.id, "d2")

        do { _ = try await DocumentIngestor.ingest(data: Data([1, 2, 3, 0, 0]), fileName: "x.xyz", into: store); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("cannot read")) }
        do { _ = try await DocumentIngestor.ingest(data: Data("   ".utf8), fileName: "empty.txt", into: store); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("readable text")) }
    }

    func testPlainTextNotesAreStoredAsDocuments() async throws {
        let store = DocumentStore(fileURL: nil)
        let doc = try await DocumentIngestor.ingest(data: Data(contract.joined(separator: "\n\n").utf8), fileName: "umowa.txt", into: store)
        XCTAssertEqual(doc.kind, .text)
        XCTAssertFalse(doc.chunks.isEmpty)
    }
}
