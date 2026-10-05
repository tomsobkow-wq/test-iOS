import Foundation

/// Weather from Open-Meteo: free, no account and no key. It is told a city name or coordinates and nothing else, over a
/// memory-only connection. (Apple's own WeatherKit needs a signing capability that a plain developer build cannot have.)
public struct OpenMeteoWeather: WeatherProviding {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public typealias CurrentLocation = @Sendable () async throws -> (latitude: Double, longitude: Double, name: String?)

    private let currentLocation: CurrentLocation
    private let transport: Transport
    private static let session = URLSession(configuration: .ephemeral)

    public init(currentLocation: @escaping CurrentLocation, transport: Transport? = nil) {
        self.currentLocation = currentLocation
        self.transport = transport ?? { request in
            var request = request
            request.timeoutInterval = 15
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ToolError("The weather service did not answer.") }
            return (data, http)
        }
    }

    public func weather(for place: String?) async throws -> WeatherReport {
        let latitude: Double, longitude: Double
        var name: String
        if let place {
            let found = try await geocode(place)
            (latitude, longitude, name) = found
        } else {
            let here = try await currentLocation()
            (latitude, longitude, name) = (here.latitude, here.longitude, here.name ?? "your location")
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let json = try await get(components.url!)
        guard let current = json["current"] as? [String: Any], let temperature = current["temperature_2m"] as? Double else {
            throw ToolError("The weather service sent nothing usable. Try again in a moment.")
        }
        let daily = json["daily"] as? [String: Any]
        func first(_ key: String) -> Double? { (daily?[key] as? [Any])?.first as? Double }
        let chance = (daily?["precipitation_probability_max"] as? [Any])?.first.flatMap { ($0 as? NSNumber)?.intValue }

        var note: String?
        if let nowText = current["time"] as? String,
           let hourly = json["hourly"] as? [String: Any],
           let times = hourly["time"] as? [String], let probabilities = hourly["precipitation_probability"] as? [Any] {
            // Local ISO times compare correctly as text ("2026-10-05T14:00").
            for (index, time) in times.enumerated() where time > nowText && index < probabilities.count {
                if let value = (probabilities[index] as? NSNumber)?.intValue, value >= 50 {
                    note = "rain likely from \(time.suffix(5))"
                    break
                }
            }
        }
        return WeatherReport(
            place: name,
            temperatureC: temperature,
            feelsLikeC: current["apparent_temperature"] as? Double,
            condition: Self.condition(code: (current["weather_code"] as? NSNumber)?.intValue ?? -1),
            highC: first("temperature_2m_max"),
            lowC: first("temperature_2m_min"),
            precipitationChancePercent: chance,
            note: note
        )
    }

    private func geocode(_ place: String) async throws -> (Double, Double, String) {
        // "Warsaw, Poland" works better as "Warsaw": the service searches by place name.
        let query = place.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? place
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "format", value: "json")]
        let json = try await get(components.url!)
        guard let result = (json["results"] as? [[String: Any]])?.first,
              let latitude = result["latitude"] as? Double, let longitude = result["longitude"] as? Double else {
            throw ToolError("Could not find a place called \"\(place)\".")
        }
        return (latitude, longitude, (result["name"] as? String) ?? query)
    }

    private func get(_ url: URL) async throws -> [String: Any] {
        guard let host = url.host, host.hasSuffix("open-meteo.com") else { throw ToolError("Refused to call an unexpected address.") }
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport(URLRequest(url: url)) } catch {
            throw ToolError("The weather service is not reachable right now. Weather needs an internet connection.")
        }
        guard (200..<300).contains(response.statusCode) else { throw ToolError("The weather service answered with an error (\(response.statusCode)).") }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// WMO weather codes in plain words.
    static func condition(code: Int) -> String {
        switch code {
        case 0: "clear sky"
        case 1: "mostly clear"
        case 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "fog"
        case 51...57: "drizzle"
        case 61...67: "rain"
        case 71...77: "snow"
        case 80...82: "rain showers"
        case 85, 86: "snow showers"
        case 95: "thunderstorm"
        case 96, 99: "thunderstorm with hail"
        default: "unknown conditions"
        }
    }
}
