import Foundation

// The iPhone features the assistants can use. AgentCore only knows these
// protocols; the app target implements them with EventKit, Contacts,
// UserNotifications, WeatherKit and the system URL handler. That keeps the
// tool logic testable on a Mac.

public struct WeatherReport: Sendable, Equatable {
    public let place: String
    public let temperatureC: Double
    public let feelsLikeC: Double?
    public let condition: String
    public let highC: Double?
    public let lowC: Double?
    public let precipitationChancePercent: Int?
    /// Free text such as "rain expected from 15:00".
    public let note: String?

    public init(
        place: String, temperatureC: Double, feelsLikeC: Double? = nil, condition: String,
        highC: Double? = nil, lowC: Double? = nil, precipitationChancePercent: Int? = nil, note: String? = nil
    ) {
        self.place = place
        self.temperatureC = temperatureC
        self.feelsLikeC = feelsLikeC
        self.condition = condition
        self.highC = highC
        self.lowC = lowC
        self.precipitationChancePercent = precipitationChancePercent
        self.note = note
    }
}

public protocol WeatherProviding: Sendable {
    /// `place == nil` means the device's current location.
    func weather(for place: String?) async throws -> WeatherReport
}

public struct CalendarEventInfo: Sendable, Equatable {
    /// The calendar's own identifier for the event, used to move or delete it later.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let isAllDay: Bool

    public init(title: String, start: Date, end: Date, location: String? = nil, isAllDay: Bool = false, id: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.isAllDay = isAllDay
    }
}

public protocol CalendarProviding: Sendable {
    func events(from: Date, to: Date) async throws -> [CalendarEventInfo]
    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo
    /// Changes only the fields that are given; the rest of the event stays as it is.
    func updateEvent(id: String, title: String?, start: Date?, end: Date?, location: String?) async throws -> CalendarEventInfo
    func deleteEvent(id: String) async throws
}

extension CalendarProviding {
    public func updateEvent(id: String, title: String?, start: Date?, end: Date?, location: String?) async throws -> CalendarEventInfo {
        throw ToolError("Changing calendar events is not available here.")
    }
    public func deleteEvent(id: String) async throws { throw ToolError("Deleting calendar events is not available here.") }
}

public struct ContactInfo: Sendable, Equatable {
    public let name: String
    public let phoneNumbers: [String]

    public init(name: String, phoneNumbers: [String]) {
        self.name = name
        self.phoneNumbers = phoneNumbers
    }
}

public protocol ContactsProviding: Sendable {
    func find(name: String) async throws -> [ContactInfo]
}

public struct ScheduledNotification: Sendable, Equatable {
    public enum Repeat: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public let title: String
    public let body: String?
    public let fireDate: Date
    public let repeats: Repeat?
    /// Alarms ring loudly and break through Focus where the OS allows it.
    public let isAlarm: Bool
    /// A countdown the user asked for as a timer (shown as "timer" when alarms are listed).
    public let isTimer: Bool

    public init(title: String, body: String? = nil, fireDate: Date, repeats: Repeat? = nil, isAlarm: Bool = false, isTimer: Bool = false) {
        self.isTimer = isTimer
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.repeats = repeats
        self.isAlarm = isAlarm
    }
}

public protocol NotificationScheduling: Sendable {
    func schedule(_ notification: ScheduledNotification) async throws
}

public struct AlarmInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let fireDate: Date
    public let isTimer: Bool

    public init(id: String, title: String, fireDate: Date, isTimer: Bool = false) {
        self.id = id
        self.title = title
        self.fireDate = fireDate
        self.isTimer = isTimer
    }
}

/// The alarms and timers this app has set that have not rung yet, so they can be listed and cancelled.
public protocol AlarmManaging: Sendable {
    func pending() async -> [AlarmInfo]
    func cancel(id: String) async throws
}

/// Opens `sms:` and `tel:` links. Both always end with the user's own tap in
/// the system UI; iOS does not let apps send texts or place calls silently.
public protocol URLOpening: Sendable {
    func open(_ url: URL) async -> Bool
}

public struct DeviceServices: Sendable {
    public let weather: any WeatherProviding
    public let calendar: any CalendarProviding
    public let contacts: any ContactsProviding
    public let notifications: any NotificationScheduling
    public let alarms: (any AlarmManaging)?
    public let urlOpener: any URLOpening
    public let spending: SpendingStore

    public init(
        weather: any WeatherProviding,
        calendar: any CalendarProviding,
        contacts: any ContactsProviding,
        notifications: any NotificationScheduling,
        alarms: (any AlarmManaging)? = nil,
        urlOpener: any URLOpening,
        spending: SpendingStore
    ) {
        self.weather = weather
        self.calendar = calendar
        self.contacts = contacts
        self.notifications = notifications
        self.alarms = alarms
        self.urlOpener = urlOpener
        self.spending = spending
    }
}
