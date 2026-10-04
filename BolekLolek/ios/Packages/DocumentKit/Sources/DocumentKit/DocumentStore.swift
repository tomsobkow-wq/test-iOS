import Foundation

public struct StoredDocument: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable { case statement, text }

    public let id: String
    public var name: String
    public var kind: Kind
    public var addedAt: Date
    public var pageCount: Int?
    public var chunks: [DocumentChunk]
    public var statement: ParsedStatement?
    /// A written summary (statements: the narrated digest; text: the map-reduce summary).
    public var summary: String?
    public var characterCount: Int

    public var oneLine: String {
        switch kind {
        case .statement:
            let s = statement
            let range = [s?.periodStart, s?.periodEnd].compactMap { $0 }.map(DateParsing.isoString).joined(separator: " to ")
            return "[\(id)] bank statement \"\(name)\", \(s?.transactions.count ?? 0) transactions, \(range)"
        case .text:
            return "[\(id)] document \"\(name)\", \(characterCount) characters\(pageCount.map { ", \($0) pages" } ?? "")"
        }
    }
}

/// Documents the user added, kept on the device only.
public actor DocumentStore {
    private let fileURL: URL?
    private var documents: [StoredDocument]
    private var indexes: [String: SearchIndex] = [:]

    /// Pass `nil` for an in-memory store (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode([StoredDocument].self, from: data) {
            documents = loaded
        } else {
            documents = []
        }
    }

    public var all: [StoredDocument] { documents }
    public var isEmpty: Bool { documents.isEmpty }

    public func add(_ document: StoredDocument) {
        documents.removeAll { $0.id == document.id }
        documents.append(document)
        indexes[document.id] = nil
        save()
    }

    public func document(id: String?) -> StoredDocument? {
        guard let id, !id.isEmpty else { return documents.last }
        return documents.first { $0.id == id } ?? documents.first { $0.name.folded.contains(id.folded) }
    }

    public func setSummary(_ summary: String, for id: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].summary = summary
        save()
    }

    public func remove(id: String) -> Bool {
        let before = documents.count
        documents.removeAll { $0.id == id }
        indexes[id] = nil
        save()
        return documents.count < before
    }

    public func removeAll() {
        documents = []
        indexes = [:]
        save()
    }

    public func search(_ query: String, in id: String?, limit: Int) -> [(document: StoredDocument, chunk: DocumentChunk, score: Double)] {
        let targets = id == nil ? documents : documents.filter { $0.id == id }
        var results: [(StoredDocument, DocumentChunk, Double)] = []
        for document in targets where !document.chunks.isEmpty {
            let index = indexes[document.id] ?? SearchIndex(chunks: document.chunks)
            indexes[document.id] = index
            results += index.search(query, limit: limit).map { (document, $0.chunk, $0.score) }
        }
        return results.sorted { $0.2 > $1.2 }.prefix(limit).map { ($0.0, $0.1, $0.2) }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(documents) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Readable after the first unlock so imports work with the phone locked, protected otherwise.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
