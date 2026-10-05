import Foundation

public struct DocumentChunk: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let text: String
    /// 1-based page when the source had pages.
    public let page: Int?
}

/// Splits a long text into pieces a 4B model can read comfortably (about 350 tokens), at paragraph and
/// sentence boundaries, with a little overlap so nothing falls between two pieces.
public enum Chunker {
    public static func chunk(_ text: String, targetCharacters: Int = 1400, overlapCharacters: Int = 160, page: Int? = nil, firstID: Int = 0) -> [DocumentChunk] {
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n").map { $0.collapsedWhitespace }.filter { !$0.isEmpty }
        // Break paragraphs that are longer than a chunk into sentences.
        var pieces: [String] = []
        for paragraph in paragraphs {
            if paragraph.count <= targetCharacters { pieces.append(paragraph); continue }
            var sentence = ""
            for part in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                sentence += (sentence.isEmpty ? "" : " ") + part
                if sentence.count >= targetCharacters / 2, ".!?;".contains(part.last ?? " ") { pieces.append(sentence); sentence = "" }
                else if sentence.count >= targetCharacters { pieces.append(sentence); sentence = "" }
            }
            if !sentence.isEmpty { pieces.append(sentence) }
        }
        var chunks: [DocumentChunk] = []
        var current = ""
        for piece in pieces {
            if !current.isEmpty, current.count + piece.count + 1 > targetCharacters {
                chunks.append(DocumentChunk(id: firstID + chunks.count, text: current, page: page))
                current = String(current.suffix(overlapCharacters))
                if let space = current.firstIndex(of: " ") { current = String(current[current.index(after: space)...]) }
            }
            current += (current.isEmpty ? "" : "\n") + piece
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(DocumentChunk(id: firstID + chunks.count, text: current, page: page))
        }
        return chunks
    }
}

/// Light word-stemming for Polish and English, enough for search: "umowy", "umowie", "umowę" all become "umow".
public enum Stemmer {
    private static let polishSuffixes = ["ami", "ach", "owi", "ego", "emu", "ymi", "imi", "owie", "iem", "om", "ie", "ow", "ą", "ę", "y", "i", "a", "e", "u", "o", "ą"].map { $0.folded }
    private static let englishSuffixes = ["ing", "ed", "es", "s"]
    static let stopwords: Set<String> = Set([
        "i", "w", "z", "na", "do", "nie", "to", "jest", "sie", "o", "ze", "a", "po", "za", "od", "dla", "jak", "czy", "co", "ale", "lub", "oraz", "przez", "przy",
        "ten", "ta", "te", "tym", "jej", "jego", "ich", "mi", "mnie", "ma", "sa", "byl", "bylo", "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is",
        "are", "was", "were", "be", "by", "with", "at", "as", "it", "this", "that", "from", "what", "which", "who", "how", "my", "me", "you", "your",
    ])

    public static func tokens(_ text: String) -> [String] {
        text.folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !stopwords.contains($0) && ($0.count > 1 || $0.first?.isNumber == true) }.map(stem)
    }

    static func stem(_ word: String) -> String {
        guard word.count > 4, word.contains(where: \.isLetter), !word.contains(where: \.isNumber) else { return word }
        var stem = word
        for suffix in polishSuffixes + englishSuffixes where stem.count - suffix.count >= 4 && stem.hasSuffix(suffix) {
            stem = String(stem.dropLast(suffix.count))
            break
        }
        return String(stem.prefix(7))
    }
}

/// BM25 over chunks. Small, fast, runs on the phone, no model needed.
public struct SearchIndex: Sendable {
    private let chunks: [DocumentChunk]
    private let termFrequencies: [[String: Int]]
    private let documentFrequency: [String: Int]
    private let lengths: [Int]
    private let averageLength: Double

    public init(chunks: [DocumentChunk]) {
        self.chunks = chunks
        let tokenized = chunks.map { Stemmer.tokens($0.text) }
        termFrequencies = tokenized.map { Dictionary(tokenized: $0) }
        var df: [String: Int] = [:]
        for terms in termFrequencies { for term in terms.keys { df[term, default: 0] += 1 } }
        documentFrequency = df
        lengths = tokenized.map(\.count)
        averageLength = max(1, Double(lengths.reduce(0, +)) / Double(max(1, lengths.count)))
    }

    public func search(_ query: String, limit: Int = 3) -> [(chunk: DocumentChunk, score: Double)] {
        let terms = Stemmer.tokens(query)
        guard !terms.isEmpty, !chunks.isEmpty else { return [] }
        let n = Double(chunks.count)
        var scored: [(DocumentChunk, Double)] = []
        for (index, frequencies) in termFrequencies.enumerated() {
            var score = 0.0
            for term in terms {
                guard let tf = frequencies[term].map(Double.init) else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                score += idf * (tf * 2.2) / (tf + 1.2 * (0.25 + 0.75 * Double(lengths[index]) / averageLength))
            }
            if score > 0 { scored.append((chunks[index], score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { ($0.0, $0.1) }
    }
}

private extension Dictionary where Key == String, Value == Int {
    init(tokenized tokens: [String]) {
        self.init()
        for token in tokens { self[token, default: 0] += 1 }
    }
}
