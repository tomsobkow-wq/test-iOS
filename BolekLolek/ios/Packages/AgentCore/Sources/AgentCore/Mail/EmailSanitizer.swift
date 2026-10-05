import Foundation

/// Cleans email text before the model (or the screen) sees it. Muse's connector does the same for the same reason:
/// a verification code, reset link or magic link in an inbox must never be something an agent can read out or act on,
/// and a hostile email must not be able to smuggle one into a reply. Long tracking links are shortened to their site.
public enum EmailSanitizer {
    private static let sensitiveWords = ["reset", "verify", "verification", "confirm", "magic", "token", "auth", "login", "signin", "sign-in",
                                         "password", "passwd", "activate", "otp", "code=", "session", "unsubscribe", "oauth", "invite", "claim"]

    public static func clean(_ text: String) -> String {
        var out = hideCodes(in: text)
        out = replaceLinks(in: out)
        return out
    }

    private static func hideCodes(in text: String) -> String {
        let keyword = "(?:(?<!zip\\s)(?<!postal\\s)code|kod(?!\\s+(?:pocztow\\w*|postal))|otp|passcode|pin|verification|verify|weryfikac\\w*|jednorazow\\w*|one[- ]time|security code|hasło)"
        // "code is 482913", "kod: 4829-13", "Your verification code: 123 456"
        let patterns = [
            "(?i)(\(keyword)[^\\n\\d]{0,30})(\\d(?:[ -]?\\d){3,7})\\b",
            "(?i)(\(keyword)[^\\n]{0,20}?:\\s*)((?=[A-Z0-9]*\\d)[A-Z0-9]{6,8})\\b",
        ]
        var out = text
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1[code removed]")
        }
        return out
    }

    private static func replaceLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"')\\]]+") else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let link = ns.substring(with: match.range)
            let lowered = link.lowercased()
            if sensitiveWords.contains(where: { lowered.contains($0) }) {
                out += "[sensitive link removed]"
            } else if let host = URL(string: link)?.host {
                out += "[link: \(host.replacingOccurrences(of: "www.", with: ""))]"
            } else {
                out += "[link]"
            }
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
