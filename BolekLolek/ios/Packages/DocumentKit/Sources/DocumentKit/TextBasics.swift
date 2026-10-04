import Foundation

/// Reading files the way Polish banks write them, and small text helpers shared by the parsers.
public enum TextDecoding {
    /// UTF-8 (with or without BOM) first, then the encodings Polish banks still export in.
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
        // Windows-1250 is by far the most common for Polish CSV exports; ISO-8859-2 is the other.
        for encoding in [String.Encoding.windowsCP1250, .isoLatin2, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    /// Lowercased with Polish and other diacritics removed: "Płatność" -> "platnosc".
    var folded: String {
        // ł and Ł do not decompose, so handle them first.
        replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" }).joined(separator: " ")
    }
}

public enum MoneyFormat {
    public static func text(_ minorUnits: Int, currency: String, signed: Bool = false) -> String {
        let sign = minorUnits < 0 ? "-" : (signed && minorUnits > 0 ? "+" : "")
        let absolute = abs(minorUnits)
        return String(format: "%@%d.%02d %@", sign, absolute / 100, absolute % 100, currency)
    }
}
