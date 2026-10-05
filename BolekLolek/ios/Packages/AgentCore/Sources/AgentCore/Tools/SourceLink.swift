import Foundation

/// A page Bolek's answer is based on, drawn by the app as a button that opens it in Safari.
/// The server sends these separately from the model's text, and the phone checks them again: only plain https
/// links to a real site name (no credentials, no bare hosts) can become buttons.
public struct SourceLink: Codable, Sendable, Equatable, Hashable {
    public let title: String
    public let site: String
    public let url: String

    public init(title: String, site: String, url: String) {
        self.title = title
        self.site = site
        self.url = url
    }

    /// The address to open, or nil when it is not a safe https link.
    public var openURL: URL? {
        guard let components = URLComponents(string: url), components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host, host.contains("."), !host.hasSuffix("."),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              host.contains(where: \.isLetter) else { return nil }
        return components.url
    }

    /// What the button says: the site, which is what a person judges a link by.
    public var label: String { site.isEmpty ? (URL(string: url)?.host ?? url) : site }

    /// Keeps only the links the app may show, without repeats, at most `limit`.
    public static func displayable(_ links: [SourceLink], limit: Int = 6) -> [SourceLink] {
        var seen = Set<String>()
        var result: [SourceLink] = []
        for link in links where link.openURL != nil && seen.insert(link.url).inserted {
            result.append(link)
            if result.count == limit { break }
        }
        return result
    }
}

/// Collects the sources tools report during one turn, so the chat can attach them to the answer.
public final class SourceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var links: [SourceLink] = []

    public init() {}

    public func add(_ new: [SourceLink]) {
        lock.lock(); defer { lock.unlock() }
        links = SourceLink.displayable(links + new)
    }

    /// Returns what was collected and starts over.
    public func take() -> [SourceLink] {
        lock.lock(); defer { lock.unlock() }
        defer { links = [] }
        return links
    }

    public func reset() { _ = take() }
}
