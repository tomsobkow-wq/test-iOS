import Foundation

/// Maps tools open Apple Maps; the user taps Start there. Nothing is sent anywhere by the app itself.
public enum MapsToolbox {
    public static func tools(opener: any URLOpening) -> [any Tool] { [ShowOnMapTool(opener: opener), GetDirectionsTool(opener: opener)] }
}

public struct ShowOnMapTool: Tool {
    public let name = "show_on_map"
    public let description = LocalizedText(
        en: "Show a place, address or kind of place (for example \"pharmacy near me\") in the Maps app.",
        pl: "Pokaż miejsce, adres lub rodzaj miejsca (np. \"apteka w pobliżu\") w aplikacji Mapy."
    )
    public let parametersSchema = #"{"type":"object","properties":{"place":{"type":"string"}},"required":["place"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let opener: any URLOpening

    public init(opener: any URLOpening) { self.opener = opener }
    struct Args: Decodable { let place: String }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let place = args.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { throw ToolError("Which place should I show?") }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: String(place.prefix(200)))]
        guard let url = components.url, await opener.open(url) else { throw ToolError("Could not open Maps.") }
        return "Maps is open showing \(place)."
    }
}

public struct GetDirectionsTool: Tool {
    public let name = "get_directions"
    public let description = LocalizedText(
        en: "Open directions to a destination in the Maps app, from the user's location or from `from`. mode is driving, walking or transit. The user taps Start in Maps.",
        pl: "Otwórz trasę do celu w aplikacji Mapy, z lokalizacji użytkownika lub z `from`. mode to driving, walking lub transit. Użytkownik sam naciska Start w Mapach."
    )
    public let parametersSchema = #"{"type":"object","properties":{"destination":{"type":"string"},"from":{"type":"string","description":"Optional start; default is the user's location"},"mode":{"type":"string","enum":["driving","walking","transit"]}},"required":["destination"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let opener: any URLOpening

    public init(opener: any URLOpening) { self.opener = opener }
    struct Args: Decodable { let destination: String; let from: String?; let mode: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let destination = args.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { throw ToolError("Where to?") }
        let mode = ["driving": "d", "walking": "w", "transit": "r"][(args.mode ?? "driving").lowercased()] ?? "d"
        var items = [URLQueryItem(name: "daddr", value: String(destination.prefix(200))), URLQueryItem(name: "dirflg", value: mode)]
        if let from = args.from?.trimmingCharacters(in: .whitespacesAndNewlines), !from.isEmpty { items.append(URLQueryItem(name: "saddr", value: String(from.prefix(200)))) }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = items
        guard let url = components.url, await opener.open(url) else { throw ToolError("Could not open Maps.") }
        let word = ["d": "driving", "w": "walking", "r": "transit"][mode] ?? "driving"
        return "Maps is open with \(word) directions to \(destination). The user taps Start there."
    }
}
