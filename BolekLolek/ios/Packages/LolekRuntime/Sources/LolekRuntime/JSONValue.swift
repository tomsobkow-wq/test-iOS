import Foundation

/// JSON that keeps object key order and prints like Python's `json.dumps`
/// (`ensure_ascii=False`, separators `", "` and `": "`). The chat templates the models
/// were trained with print tool definitions that way, so we match it exactly.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool { lhs.pythonDump() == rhs.pythonDump() }

    // MARK: Printing

    func pythonDump() -> String {
        switch self {
        case .null: "null"
        case let .bool(value): value ? "true" : "false"
        case let .int(value): String(value)
        case let .double(value): Self.formatDouble(value)
        case let .string(value): Self.quote(value)
        case let .array(items): "[" + items.map { $0.pythonDump() }.joined(separator: ", ") + "]"
        case let .object(pairs): "{" + pairs.map { Self.quote($0.key) + ": " + $0.value.pythonDump() }.joined(separator: ", ") + "}"
        }
    }

    /// What Python's `str()` gives for the same value: used for template parameter values.
    func pythonStr() -> String {
        switch self {
        case .null: "None"
        case let .bool(value): value ? "True" : "False"
        case let .string(value): value
        case .int, .double: pythonDump()
        case .array, .object: pythonDump()
        }
    }

    private static func formatDouble(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(format: "%.1f", value) }
        return String(value)
    }

    private static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    // MARK: Parsing

    static func parse(_ text: String) -> JSONValue? {
        var parser = Parser(chars: Array(text.unicodeScalars))
        parser.skipSpace()
        guard let value = parser.value() else { return nil }
        parser.skipSpace()
        return parser.index == parser.chars.count ? value : nil
    }

    subscript(key: String) -> JSONValue? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    private struct Parser {
        let chars: [Unicode.Scalar]
        var index = 0

        mutating func skipSpace() {
            while index < chars.count, " \n\r\t".unicodeScalars.contains(chars[index]) { index += 1 }
        }

        mutating func value() -> JSONValue? {
            guard index < chars.count else { return nil }
            switch chars[index] {
            case "{": return object()
            case "[": return array()
            case "\"": return string().map(JSONValue.string)
            case "t": return literal("true", .bool(true))
            case "f": return literal("false", .bool(false))
            case "n": return literal("null", .null)
            default: return number()
            }
        }

        mutating func literal(_ word: String, _ value: JSONValue) -> JSONValue? {
            let scalars = Array(word.unicodeScalars)
            guard index + scalars.count <= chars.count, Array(chars[index..<index + scalars.count]) == scalars else { return nil }
            index += scalars.count
            return value
        }

        mutating func number() -> JSONValue? {
            let start = index
            while index < chars.count, "+-0123456789.eE".unicodeScalars.contains(chars[index]) { index += 1 }
            let text = String(String.UnicodeScalarView(chars[start..<index]))
            if let int = Int(text) { return .int(int) }
            if let double = Double(text) { return .double(double) }
            return nil
        }

        mutating func string() -> String? {
            guard chars[index] == "\"" else { return nil }
            index += 1
            var out = String.UnicodeScalarView()
            while index < chars.count {
                let c = chars[index]
                index += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard index < chars.count else { return nil }
                let e = chars[index]
                index += 1
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    guard index + 4 <= chars.count,
                          var code = UInt32(String(String.UnicodeScalarView(chars[index..<index + 4])), radix: 16) else { return nil }
                    index += 4
                    // Surrogate pair.
                    if (0xD800..<0xDC00).contains(code), index + 6 <= chars.count, chars[index] == "\\", chars[index + 1] == "u",
                       let low = UInt32(String(String.UnicodeScalarView(chars[index + 2..<index + 6])), radix: 16), (0xDC00..<0xE000).contains(low) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        index += 6
                    }
                    guard let scalar = Unicode.Scalar(code) else { return nil }
                    out.append(scalar)
                default: out.append(e)
                }
            }
            return nil
        }

        mutating func array() -> JSONValue? {
            index += 1
            var items: [JSONValue] = []
            skipSpace()
            if index < chars.count, chars[index] == "]" { index += 1; return .array(items) }
            while true {
                skipSpace()
                guard let item = value() else { return nil }
                items.append(item)
                skipSpace()
                guard index < chars.count else { return nil }
                if chars[index] == "," { index += 1; continue }
                if chars[index] == "]" { index += 1; return .array(items) }
                return nil
            }
        }

        mutating func object() -> JSONValue? {
            index += 1
            var pairs: [(key: String, value: JSONValue)] = []
            skipSpace()
            if index < chars.count, chars[index] == "}" { index += 1; return .object(pairs) }
            while true {
                skipSpace()
                guard index < chars.count, let key = string() else { return nil }
                skipSpace()
                guard index < chars.count, chars[index] == ":" else { return nil }
                index += 1
                skipSpace()
                guard let v = value() else { return nil }
                pairs.append((key, v))
                skipSpace()
                guard index < chars.count else { return nil }
                if chars[index] == "," { index += 1; continue }
                if chars[index] == "}" { index += 1; return .object(pairs) }
                return nil
            }
        }
    }
}
