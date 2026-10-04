import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum IngestError: LocalizedError, Sendable {
    case unsupported(String)
    case noText
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case let .unsupported(ext): "Lolek cannot read .\(ext) files yet. PDF, CSV, text and photos work."
        case .noText: "I could not find any readable text in that file."
        case .tooLarge: "That file is too large (the limit is 25 MB)."
        }
    }
}

/// Reads text out of an image. On the phone this is Apple's Vision framework, which handles Polish.
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> String
}

#if canImport(Vision)
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["pl-PL", "en-US"]
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    continuation.resume(returning: Self.reading(request.results ?? []))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Vision returns text fragments. Put the ones on the same visual line back together, left to right,
    /// so a table row stays one line ("02.03.2026 BIEDRONKA -45,60 4 954,40").
    static func reading(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Fragment { let text: String; let box: CGRect }
        let fragments = observations.compactMap { observation -> Fragment? in
            observation.topCandidates(1).first.map { Fragment(text: $0.string, box: observation.boundingBox) }
        }.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Fragment]] = []
        for fragment in fragments {
            if let last = rows.last?.first, abs(last.box.midY - fragment.box.midY) < max(last.box.height, fragment.box.height) * 0.6 {
                rows[rows.count - 1].append(fragment)
            } else { rows.append([fragment]) }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }
}
#endif

public struct ExtractedText: Sendable {
    public let pages: [String]
    public var joined: String { pages.joined(separator: "\n") }
}

public enum DocumentIngestor {
    public static let maxBytes = 25 * 1024 * 1024

    /// Reads the file, decides whether it is a bank statement or an ordinary document, and stores it.
    @discardableResult
    public static func ingest(
        data: Data, fileName: String, into store: DocumentStore, recognizer: (any TextRecognizing)? = nil
    ) async throws -> StoredDocument {
        guard data.count <= maxBytes else { throw IngestError.tooLarge }
        let extracted = try await extractText(data: data, fileName: fileName, recognizer: recognizer)
        let text = extracted.joined
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { throw IngestError.noText }

        let existing = await store.all
        let nextNumber = (existing.compactMap { Int($0.id.dropFirst()) }.max() ?? 0) + 1
        let id = "d\(nextNumber)"

        if let statement = StatementParser.parse(text), statement.transactions.count >= 3 {
            return await add(StoredDocument(
                id: id, name: fileName, kind: .statement, addedAt: Date(), pageCount: extracted.pages.count > 1 ? extracted.pages.count : nil,
                chunks: [], statement: statement, summary: nil, characterCount: text.count
            ), to: store)
        }

        var chunks: [DocumentChunk] = []
        for (index, page) in extracted.pages.enumerated() {
            chunks += Chunker.chunk(page, page: extracted.pages.count > 1 ? index + 1 : nil, firstID: chunks.count)
        }
        return await add(StoredDocument(
            id: id, name: fileName, kind: .text, addedAt: Date(), pageCount: extracted.pages.count > 1 ? extracted.pages.count : nil,
            chunks: chunks, statement: nil, summary: nil, characterCount: text.count
        ), to: store)
    }

    private static func add(_ document: StoredDocument, to store: DocumentStore) async -> StoredDocument {
        await store.add(document)
        return document
    }

    public static func extractText(data: Data, fileName: String, recognizer: (any TextRecognizing)?) async throws -> ExtractedText {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "csv", "tsv", "txt", "text", "md", "log":
            return ExtractedText(pages: [TextDecoding.decode(data)])
        case "pdf":
            return try await readPDF(data, recognizer: recognizer)
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp":
            #if canImport(CoreGraphics) && canImport(ImageIO)
            guard let recognizer, let image = cgImage(from: data) else { throw IngestError.noText }
            return ExtractedText(pages: [try await recognizer.recognize(image)])
            #else
            throw IngestError.unsupported(ext)
            #endif
        default:
            // Unknown extension: if it decodes as text, treat it as text.
            let text = TextDecoding.decode(data)
            if text.unicodeScalars.filter({ $0.value < 9 }).isEmpty, text.count > 20 { return ExtractedText(pages: [text]) }
            throw IngestError.unsupported(ext.isEmpty ? "this type of" : ext)
        }
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    #endif

    private static func readPDF(_ data: Data, recognizer: (any TextRecognizing)?) async throws -> ExtractedText {
        #if canImport(PDFKit) && canImport(CoreGraphics)
        guard let document = PDFDocument(data: data) else { throw IngestError.noText }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            let embedded = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // A scanned page has little or no embedded text: read the picture instead.
            if embedded.count < 40, let recognizer, let page = document.page(at: index), let image = render(page) {
                pages.append((try? await recognizer.recognize(image)) ?? embedded)
            } else {
                pages.append(embedded)
            }
        }
        return ExtractedText(pages: pages)
        #else
        throw IngestError.unsupported("pdf")
        #endif
    }

    #if canImport(PDFKit) && canImport(CoreGraphics)
    /// A page as an image, large enough for OCR to read small print (about 200 dpi).
    static func render(_ page: PDFPage, scale: CGFloat = 2.8) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0, width * height < 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
    #endif
}
