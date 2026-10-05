import Foundation

/// Clock and calendar used by the tools. Injected so tests are deterministic.
public struct ToolClock: Sendable {
    public let now: @Sendable () -> Date
    public let calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }
}

public enum DeviceToolbox {
    /// Every on-device tool, available to both assistants.
    public static func tools(services: DeviceServices, clock: ToolClock = ToolClock()) -> [any Tool] {
        [
            GetWeatherTool(weather: services.weather),
            SetAlarmTool(notifications: services.notifications, clock: clock),
            SetTimerTool(notifications: services.notifications, clock: clock),
        ] + (services.alarms.map { [ListAlarmsTool(alarms: $0, clock: clock), CancelAlarmTool(alarms: $0, clock: clock)] as [any Tool] } ?? []) + [
            AddReminderTool(notifications: services.notifications, clock: clock),
            ListCalendarEventsTool(calendar: services.calendar, clock: clock),
            AddCalendarEventTool(calendar: services.calendar, clock: clock),
            RescheduleCalendarEventTool(calendar: services.calendar, clock: clock),
            DeleteCalendarEventTool(calendar: services.calendar, clock: clock),
            FindContactTool(contacts: services.contacts),
            TextContactTool(contacts: services.contacts, opener: services.urlOpener),
            CallContactTool(contacts: services.contacts, opener: services.urlOpener),
        ] + MapsToolbox.tools(opener: services.urlOpener) + [
            LogExpenseTool(store: services.spending, clock: clock),
            SpendingSummaryTool(store: services.spending, clock: clock),
            SetSpendingTrackingTool(store: services.spending),
            DeleteSpendingDataTool(store: services.spending),
        ]
    }
}

// MARK: - Weather

public struct GetWeatherTool: Tool {
    public let name = "get_weather"
    public let description = LocalizedText(
        en: "Get the current weather and today's forecast. Omit place for the user's current location.",
        pl: "Podaj aktualną pogodę i dzisiejszą prognozę. Pomiń miejsce, aby użyć bieżącej lokalizacji."
    )
    public let parametersSchema = #"{"type":"object","properties":{"place":{"type":"string","description":"City or address, optional"}}}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let weather: any WeatherProviding

    struct Args: Decodable { let place: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let place = args.place?.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = try await weather.weather(for: (place?.isEmpty ?? true) ? nil : place)
        var parts = ["\(report.place): \(Int(report.temperatureC.rounded()))°C, \(report.condition)"]
        if let feels = report.feelsLikeC { parts.append("feels like \(Int(feels.rounded()))°C") }
        if let high = report.highC, let low = report.lowC {
            parts.append("today \(Int(low.rounded()))° to \(Int(high.rounded()))°C")
        }
        if let chance = report.precipitationChancePercent { parts.append("\(chance)% chance of precipitation") }
        if let note = report.note { parts.append(note) }
        return parts.joined(separator: "; ") + "."
    }
}

// MARK: - Alarms, timers, reminders

public struct SetAlarmTool: Tool {
    public let name = "set_alarm"
    public let description = LocalizedText(
        en: "Set an alarm. `time` is an ISO 8601 local date-time, or HH:mm for the next time the clock shows it.",
        pl: "Ustaw budzik. `time` to lokalna data i czas ISO 8601 albo HH:mm dla najbliższego takiego czasu."
    )
    public let parametersSchema = #"{"type":"object","properties":{"time":{"type":"string"},"label":{"type":"string"}},"required":["time"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let notifications: any NotificationScheduling
    let clock: ToolClock

    struct Args: Decodable { let time: String; let label: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let date = ToolDates.parse(args.time, now: clock.now(), calendar: clock.calendar) else {
            throw ToolError("Could not understand the time \"\(args.time)\". Use ISO 8601 or HH:mm.")
        }
        guard date > clock.now() else { throw ToolError("That time is in the past.") }
        let label = args.label?.isEmpty == false ? args.label! : "Alarm"
        try await notifications.schedule(ScheduledNotification(title: label, fireDate: date, isAlarm: true))
        return "Alarm \"\(label)\" set for \(ToolDates.describe(date, calendar: clock.calendar)). It will ring like the Clock app, but it is managed here, not listed in the Clock app: the user can ask to see or cancel their alarms."
    }
}

public struct SetTimerTool: Tool {
    public let name = "set_timer"
    public let description = LocalizedText(
        en: "Start a countdown timer.",
        pl: "Uruchom minutnik."
    )
    public let parametersSchema = #"{"type":"object","properties":{"seconds":{"type":"integer"},"label":{"type":"string"}},"required":["seconds"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let notifications: any NotificationScheduling
    let clock: ToolClock

    struct Args: Decodable { let seconds: Int; let label: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard (1...86_400).contains(args.seconds) else { throw ToolError("A timer must be between 1 second and 24 hours.") }
        let fire = clock.now().addingTimeInterval(TimeInterval(args.seconds))
        let label = args.label?.isEmpty == false ? args.label! : "Timer"
        try await notifications.schedule(ScheduledNotification(title: label, fireDate: fire, isAlarm: true, isTimer: true))
        return "Timer set for \(args.seconds / 60) min \(args.seconds % 60) s."
    }
}

public struct ListAlarmsTool: Tool {
    public let name = "list_alarms"
    public let description = LocalizedText(
        en: "List the alarms and timers set through this app that have not rung yet.",
        pl: "Wyświetl budziki i minutniki ustawione przez tę aplikację, które jeszcze nie zadzwoniły."
    )
    public let parametersSchema = #"{"type":"object","properties":{}}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let alarms: any AlarmManaging
    let clock: ToolClock

    public init(alarms: any AlarmManaging, clock: ToolClock) { self.alarms = alarms; self.clock = clock }

    public func run(argumentsJSON: String) async throws -> String {
        let list = await alarms.pending().sorted { $0.fireDate < $1.fireDate }
        guard !list.isEmpty else { return "There are no alarms or timers waiting." }
        return list.map { "- [\($0.id.prefix(8))] \($0.isTimer ? "timer" : "alarm") \"\($0.title)\": \(ToolDates.describe($0.fireDate, calendar: clock.calendar))" }.joined(separator: "\n")
    }
}

public struct CancelAlarmTool: Tool {
    public let name = "cancel_alarm"
    public let description = LocalizedText(
        en: "Cancel an alarm or timer set through this app. Give its label or time, or all=true to cancel every one.",
        pl: "Anuluj budzik lub minutnik ustawiony przez tę aplikację. Podaj jego nazwę lub godzinę, albo all=true, aby anulować wszystkie."
    )
    public let parametersSchema = #"{"type":"object","properties":{"label":{"type":"string"},"time":{"type":"string","description":"HH:mm or ISO date-time of the alarm"},"all":{"type":"boolean"}}}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let alarms: any AlarmManaging
    let clock: ToolClock

    public init(alarms: any AlarmManaging, clock: ToolClock) { self.alarms = alarms; self.clock = clock }

    struct Args: Decodable { let label: String?; let time: String?; let all: LooseBool? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = (try? ToolArguments.decode(Args.self, from: argumentsJSON)) ?? Args(label: nil, time: nil, all: nil)
        let list = await alarms.pending()
        guard !list.isEmpty else { return "There are no alarms or timers to cancel." }
        var matches = list
        if args.all?.value != true {
            if let label = args.label?.trimmingCharacters(in: .whitespaces), !label.isEmpty {
                matches = matches.filter { $0.title.folded.contains(label.folded) }
            }
            if let time = args.time, let date = ToolDates.parse(time, now: clock.now(), calendar: clock.calendar) {
                let hasDay = time.count > 5
                matches = matches.filter { hasDay ? abs($0.fireDate.timeIntervalSince(date)) < 90 : (clock.calendar.component(.hour, from: $0.fireDate) == clock.calendar.component(.hour, from: date) && clock.calendar.component(.minute, from: $0.fireDate) == clock.calendar.component(.minute, from: date)) }
            }
            if args.label == nil, args.time == nil, list.count > 1 {
                throw ToolError("There are \(list.count) alarms or timers. Ask which one, or cancel all: \(list.map { "\($0.title) \(ToolDates.describe($0.fireDate, calendar: clock.calendar))" }.joined(separator: "; "))")
            }
        }
        guard !matches.isEmpty else { throw ToolError("No alarm or timer matches that. Waiting: \(list.map { "\($0.title) \(ToolDates.describe($0.fireDate, calendar: clock.calendar))" }.joined(separator: "; "))") }
        if matches.count > 1, args.all?.value != true {
            throw ToolError("\(matches.count) match: \(matches.map { "\($0.title) \(ToolDates.describe($0.fireDate, calendar: clock.calendar))" }.joined(separator: "; ")). Ask which one.")
        }
        for item in matches { try await alarms.cancel(id: item.id) }
        return "Cancelled \(matches.count == 1 ? "\"\(matches[0].title)\" (\(ToolDates.describe(matches[0].fireDate, calendar: clock.calendar)))" : "\(matches.count) alarms and timers")."
    }
}

public struct AddReminderTool: Tool {
    public let name = "add_reminder"
    public let description = LocalizedText(
        en: "Remind the user at a time, once or repeating (daily, weekly, monthly, yearly).",
        pl: "Przypomnij użytkownikowi o określonej porze, jednorazowo lub cyklicznie (daily, weekly, monthly, yearly)."
    )
    public let parametersSchema = #"{"type":"object","properties":{"title":{"type":"string"},"when":{"type":"string","description":"ISO 8601 local date-time"},"repeat":{"type":"string","enum":["daily","weekly","monthly","yearly"]}},"required":["title","when"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let notifications: any NotificationScheduling
    let clock: ToolClock

    struct Args: Decodable {
        let title: String
        let when: String
        let repeats: ScheduledNotification.Repeat?

        enum CodingKeys: String, CodingKey {
            case title, when
            case repeats = "repeat"
        }
    }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let date = ToolDates.parse(args.when, now: clock.now(), calendar: clock.calendar) else {
            throw ToolError("Could not understand the time \"\(args.when)\".")
        }
        guard date > clock.now() else { throw ToolError("That time is in the past.") }
        try await notifications.schedule(ScheduledNotification(title: args.title, fireDate: date, repeats: args.repeats))
        let repeating = args.repeats.map { ", repeating \($0.rawValue)" } ?? ""
        return "Reminder \"\(args.title)\" set for \(ToolDates.describe(date, calendar: clock.calendar))\(repeating)."
    }
}

// MARK: - Calendar

public struct ListCalendarEventsTool: Tool {
    public let name = "list_calendar_events"
    public let description = LocalizedText(
        en: "List calendar events between two dates (default: the next 7 days).",
        pl: "Wyświetl wydarzenia z kalendarza między dwiema datami (domyślnie najbliższe 7 dni)."
    )
    public let parametersSchema = #"{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"}}}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let calendar: any CalendarProviding
    let clock: ToolClock

    struct Args: Decodable { let from: String?; let to: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let now = clock.now()
        let from = args.from.flatMap { ToolDates.parse($0, now: now, calendar: clock.calendar) } ?? clock.calendar.startOfDay(for: now)
        var to = args.to.flatMap { ToolDates.parse($0, now: now, calendar: clock.calendar) } ?? from.addingTimeInterval(7 * 86_400)
        // "Events on 2027-01-20" arrives as from = to = that date (or only a date for `to`): that means the whole day.
        let endIsDateOnly = args.to.map { $0.trimmingCharacters(in: .whitespaces).count <= 10 && !$0.contains(":") } ?? false
        if endIsDateOnly || to <= from {
            let dayStart = clock.calendar.startOfDay(for: endIsDateOnly ? to : from)
            to = clock.calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        }
        let events = try await calendar.events(from: from, to: to).sorted { $0.start < $1.start }
        guard !events.isEmpty else { return "No events between \(ToolDates.describe(from, calendar: clock.calendar)) and \(ToolDates.describe(to, calendar: clock.calendar))." }
        return events.map { event in
            let when = event.isAllDay
                ? "\(ToolDates.describe(event.start, calendar: clock.calendar).prefix(21)) (all day)"
                : "\(ToolDates.describe(event.start, calendar: clock.calendar)) to \(ToolDates.describe(event.end, calendar: clock.calendar).suffix(5))"
            return "- \(when): \(event.title)" + (event.location.map { " @ \($0)" } ?? "")
        }.joined(separator: "\n")
    }
}

public struct AddCalendarEventTool: Tool {
    public let name = "add_calendar_event"
    public let description = LocalizedText(
        en: "Add an event to the user's calendar.",
        pl: "Dodaj wydarzenie do kalendarza użytkownika."
    )
    public let parametersSchema = #"{"type":"object","properties":{"title":{"type":"string"},"start":{"type":"string","description":"ISO 8601 local date-time"},"end":{"type":"string","description":"Optional, default 1 hour after start"},"location":{"type":"string"}},"required":["title","start"]}"#
    public let tier = ToolTier.both
    // Calendars sync to other devices and people, so adding asks first.
    public let risk = ToolRisk.writeExternal
    let calendar: any CalendarProviding
    let clock: ToolClock

    struct Args: Decodable { let title: String; let start: String; let end: String?; let location: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let now = clock.now()
        guard let start = ToolDates.parse(args.start, now: now, calendar: clock.calendar) else {
            throw ToolError("Could not understand the start time \"\(args.start)\".")
        }
        let end = args.end.flatMap { ToolDates.parse($0, now: now, calendar: clock.calendar) } ?? start.addingTimeInterval(3_600)
        guard end > start else { throw ToolError("The end must be after the start.") }
        let event = try await calendar.addEvent(title: args.title, start: start, end: end, location: args.location)
        return "Added \"\(event.title)\" on \(ToolDates.describe(event.start, calendar: clock.calendar))."
    }
}

/// Finds the one event the user means: by words from its title, on a day if they named one, otherwise in the next year.
enum CalendarLookup {
    static func find(title: String, on day: String?, calendar: any CalendarProviding, clock: ToolClock) async throws -> CalendarEventInfo {
        let now = clock.now()
        let cal = clock.calendar
        var from = cal.startOfDay(for: now)
        var to = cal.date(byAdding: .day, value: 366, to: from) ?? from.addingTimeInterval(366 * 86_400)
        if let day, let date = ToolDates.parse(day, now: now, calendar: cal) {
            from = cal.startOfDay(for: date)
            to = cal.date(byAdding: .day, value: 1, to: from) ?? from.addingTimeInterval(86_400)
        }
        let words = title.folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        let all = try await calendar.events(from: from, to: to).sorted { $0.start < $1.start }
        let matches = all.filter { event in
            let name = event.title.folded
            return words.isEmpty ? false : words.allSatisfy { name.contains($0) }
        }
        func line(_ e: CalendarEventInfo) -> String { "\"\(e.title)\" on \(ToolDates.describe(e.start, calendar: cal))" }
        guard let first = matches.first else {
            let nearby = all.prefix(6).map(line).joined(separator: "; ")
            throw ToolError("No calendar event matches \"\(title)\". " + (nearby.isEmpty ? "The calendar is empty for that period." : "Events then: \(nearby)."))
        }
        if matches.count > 1 {
            throw ToolError("\(matches.count) events match \"\(title)\": \(matches.prefix(6).map(line).joined(separator: "; ")). Ask the user which one (or for its date).")
        }
        guard !first.id.isEmpty else { throw ToolError("That event cannot be changed from here.") }
        return first
    }
}

public struct RescheduleCalendarEventTool: Tool {
    public let name = "reschedule_calendar_event"
    public let description = LocalizedText(
        en: "Move an existing calendar event to a new time (it keeps its length unless new_end is given). Find it by words from its title and, if known, the day it is on now.",
        pl: "Przenieś istniejące wydarzenie w kalendarzu na nowy termin (zachowuje długość, chyba że podano new_end). Znajdź je po słowach z tytułu i, jeśli znany, dniu, w którym jest teraz."
    )
    public let parametersSchema = #"{"type":"object","properties":{"title":{"type":"string","description":"Words from the event's current title"},"on":{"type":"string","description":"The day it is on now, YYYY-MM-DD (optional)"},"new_start":{"type":"string","description":"ISO 8601 local date-time"},"new_end":{"type":"string"},"new_title":{"type":"string"}},"required":["title","new_start"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeExternal
    let calendar: any CalendarProviding
    let clock: ToolClock

    public init(calendar: any CalendarProviding, clock: ToolClock) { self.calendar = calendar; self.clock = clock }

    struct Args: Decodable { let title: String; let on: String?; let new_start: String; let new_end: String?; let new_title: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let now = clock.now()
        guard let start = ToolDates.parse(args.new_start, now: now, calendar: clock.calendar) else {
            throw ToolError("Could not understand the new start time \"\(args.new_start)\".")
        }
        let end = args.new_end.flatMap { ToolDates.parse($0, now: now, calendar: clock.calendar) }
        if let end, end <= start { throw ToolError("The end must be after the start.") }
        let found = try await CalendarLookup.find(title: args.title, on: args.on, calendar: calendar, clock: clock)
        let updated = try await calendar.updateEvent(id: found.id, title: args.new_title, start: start, end: end, location: nil)
        return "Moved \"\(updated.title)\" from \(ToolDates.describe(found.start, calendar: clock.calendar)) to \(ToolDates.describe(updated.start, calendar: clock.calendar)) (until \(ToolDates.describe(updated.end, calendar: clock.calendar).suffix(5)))."
    }
}

public struct DeleteCalendarEventTool: Tool {
    public let name = "delete_calendar_event"
    public let description = LocalizedText(
        en: "Delete a calendar event. Find it by words from its title and, if known, the day it is on.",
        pl: "Usuń wydarzenie z kalendarza. Znajdź je po słowach z tytułu i, jeśli znany, dniu."
    )
    public let parametersSchema = #"{"type":"object","properties":{"title":{"type":"string","description":"Words from the event's title"},"on":{"type":"string","description":"The day it is on, YYYY-MM-DD (optional)"}},"required":["title"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.destructive
    let calendar: any CalendarProviding
    let clock: ToolClock

    public init(calendar: any CalendarProviding, clock: ToolClock) { self.calendar = calendar; self.clock = clock }

    struct Args: Decodable { let title: String; let on: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let found = try await CalendarLookup.find(title: args.title, on: args.on, calendar: calendar, clock: clock)
        try await calendar.deleteEvent(id: found.id)
        return "Deleted \"\(found.title)\" (\(ToolDates.describe(found.start, calendar: clock.calendar)))."
    }
}

// MARK: - Contacts, text, call

enum PhoneTarget {
    /// Turns a name or a number into one dialable number, or explains why not.
    static func resolve(_ query: String, contacts: any ContactsProviding) async throws -> (name: String?, number: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        if digits.filter(\.isNumber).count >= 6, trimmed.allSatisfy({ $0.isNumber || " +-()".contains($0) }) {
            return (nil, digits)
        }
        let matches = try await contacts.find(name: trimmed).filter { !$0.phoneNumbers.isEmpty }
        switch matches.count {
        case 0:
            throw ToolError("No contact named \"\(trimmed)\" with a phone number was found.")
        case 1:
            let contact = matches[0]
            if contact.phoneNumbers.count > 1 {
                throw ToolError("\(contact.name) has several numbers: \(contact.phoneNumbers.joined(separator: ", ")). Ask the user which one.")
            }
            return (contact.name, contact.phoneNumbers[0].filter { $0.isNumber || $0 == "+" })
        default:
            throw ToolError("Several contacts match \"\(trimmed)\": \(matches.map(\.name).joined(separator: ", ")). Ask the user which one.")
        }
    }
}

public struct FindContactTool: Tool {
    public let name = "find_contact"
    public let description = LocalizedText(
        en: "Look up a contact's phone numbers by name.",
        pl: "Znajdź numery telefonu kontaktu po imieniu."
    )
    public let parametersSchema = #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let contacts: any ContactsProviding

    struct Args: Decodable { let name: String }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let matches = try await contacts.find(name: args.name)
        guard !matches.isEmpty else { return "No contact found for \"\(args.name)\"." }
        return matches.prefix(5).map { "\($0.name): \($0.phoneNumbers.joined(separator: ", "))" }.joined(separator: "\n")
    }
}

public struct TextContactTool: Tool {
    public let name = "text_contact"
    public let description = LocalizedText(
        en: "Prepare a text message to a contact or number. Opens Messages with the text filled in; the user taps Send.",
        pl: "Przygotuj SMS do kontaktu lub numeru. Otwiera Wiadomości z gotowym tekstem; użytkownik sam naciska Wyślij."
    )
    public let parametersSchema = #"{"type":"object","properties":{"to":{"type":"string","description":"Contact name or phone number"},"body":{"type":"string"}},"required":["to","body"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.send
    let contacts: any ContactsProviding
    let opener: any URLOpening

    struct Args: Decodable { let to: String; let body: String }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let target = try await PhoneTarget.resolve(args.to, contacts: contacts)
        var components = URLComponents()
        components.scheme = "sms"
        components.path = target.number
        components.queryItems = [URLQueryItem(name: "body", value: args.body)]
        guard let url = components.url, await opener.open(url) else {
            throw ToolError("Could not open Messages.")
        }
        return "Messages is open with the text to \(target.name ?? target.number). The user still has to tap Send."
    }
}

public struct CallContactTool: Tool {
    public let name = "call_contact"
    public let description = LocalizedText(
        en: "Start a phone call to a contact or number. iOS asks the user to confirm the call.",
        pl: "Zadzwoń do kontaktu lub na numer. iOS poprosi użytkownika o potwierdzenie połączenia."
    )
    public let parametersSchema = #"{"type":"object","properties":{"to":{"type":"string","description":"Contact name or phone number"}},"required":["to"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.send
    let contacts: any ContactsProviding
    let opener: any URLOpening

    struct Args: Decodable { let to: String }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let target = try await PhoneTarget.resolve(args.to, contacts: contacts)
        guard let url = URL(string: "tel:\(target.number)"), await opener.open(url) else {
            throw ToolError("Could not start the call.")
        }
        return "Calling \(target.name ?? target.number). The user confirms on the call screen."
    }
}

// MARK: - Spending

public struct LogExpenseTool: Tool {
    public let name = "log_expense"
    public let description = LocalizedText(
        en: "Record a payment the user tells you about. Amount like \"12,50 zł\" or \"9.99 EUR\".",
        pl: "Zapisz płatność, o której mówi użytkownik. Kwota np. „12,50 zł” lub „9.99 EUR”."
    )
    public let parametersSchema = #"{"type":"object","properties":{"amount":{"type":"string"},"merchant":{"type":"string"},"category":{"type":"string","enum":["groceries","eating_out","transport","shopping","health","subscriptions","travel","home","other"]},"date":{"type":"string"}},"required":["amount","merchant"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let store: SpendingStore
    let clock: ToolClock

    struct Args: Decodable {
        let amount: LooseString
        let merchant: String
        let category: String?
        let date: String?
    }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let amount = AmountParser.parse(args.amount.value) else {
            throw ToolError("Could not read the amount \"\(args.amount.value)\".")
        }
        let now = clock.now()
        let date = args.date.flatMap { ToolDates.parse($0, now: now, calendar: clock.calendar) } ?? now
        let category = args.category.flatMap { ExpenseCategorizer.categories.contains($0) ? $0 : nil }
            ?? ExpenseCategorizer.category(forMerchant: args.merchant)
        let expense = Expense(
            date: date, minorUnits: amount.minorUnits, currency: amount.currency,
            merchant: args.merchant, category: category, source: .manual
        )
        switch await store.add(expense) {
        case .added: return "Logged \(AmountParser.format(amount.minorUnits, currency: amount.currency)) at \(args.merchant) (\(category))."
        case .duplicate: return "That payment was already logged a moment ago."
        case .trackingOff: return "Not logged."
        }
    }
}

public struct SpendingSummaryTool: Tool {
    public let name = "spending_summary"
    public let description = LocalizedText(
        en: "Totals of the user's recorded spending for a period, optionally for one category.",
        pl: "Sumy zapisanych wydatków użytkownika za okres, opcjonalnie dla jednej kategorii."
    )
    public let parametersSchema = #"{"type":"object","properties":{"period":{"type":"string","enum":["today","yesterday","this_week","last_week","this_month","last_month","last_7_days","last_30_days","this_year"]},"category":{"type":"string"}},"required":["period"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.read
    let store: SpendingStore
    let clock: ToolClock

    struct Args: Decodable { let period: String; let category: String? }

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let period = SpendingPeriod(rawValue: args.period) else {
            throw ToolError("Unknown period \"\(args.period)\".")
        }
        let interval = period.interval(now: clock.now(), calendar: clock.calendar)
        let summaries = await store.summaries(in: interval, category: args.category)
        let enabled = await store.isTrackingEnabled
        guard !summaries.isEmpty else {
            return enabled
                ? "No spending recorded for \(period.rawValue)."
                : "No spending recorded for \(period.rawValue). Automatic tracking is off."
        }
        return summaries.map { summary in
            var lines = ["\(period.rawValue): \(AmountParser.format(summary.totalMinorUnits, currency: summary.currency)) in \(summary.count) payments"]
            lines += summary.byCategory.map { "  \($0.category): \(AmountParser.format($0.minorUnits, currency: summary.currency)) (\($0.count))" }
            if !summary.topMerchants.isEmpty { lines.append("  top: " + summary.topMerchants.joined(separator: ", ")) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

public struct SetSpendingTrackingTool: Tool {
    public let name = "set_spending_tracking"
    public let description = LocalizedText(
        en: "Turn passive spending tracking on or off. Turning it on returns the one-time Shortcuts setup steps to tell the user.",
        pl: "Włącz lub wyłącz pasywne śledzenie wydatków. Po włączeniu zwraca kroki jednorazowej konfiguracji w Skrótach, które trzeba przekazać użytkownikowi."
    )
    public let parametersSchema = #"{"type":"object","properties":{"enabled":{"type":"boolean"}},"required":["enabled"]}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.writeLocal
    let store: SpendingStore

    struct Args: Decodable { let enabled: Bool }

    public static let setupSteps = """
    Tracking is on. One-time setup, about a minute, because Apple does not let apps create automations:
    1. Open the Shortcuts app, tap Automation, then New Automation.
    2. Choose Transaction, pick the cards to track, and tap Next.
    3. Add the action "Log payment" from Bolek & Lolek. Fill Merchant, Amount and Card from the transaction.
    4. Set it to Run Immediately and turn off Notify When Run.
    After that, every Apple Pay payment from those cards is recorded on this iPhone only.
    """

    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        await store.setTracking(enabled: args.enabled)
        return args.enabled ? Self.setupSteps : "Tracking is off. Existing records are kept; ask to delete them if wanted."
    }
}

public struct DeleteSpendingDataTool: Tool {
    public let name = "delete_spending_data"
    public let description = LocalizedText(
        en: "Permanently delete every recorded payment on this device.",
        pl: "Trwale usuń wszystkie zapisane płatności z tego urządzenia."
    )
    public let parametersSchema = #"{"type":"object","properties":{}}"#
    public let tier = ToolTier.both
    public let risk = ToolRisk.destructive
    let store: SpendingStore

    public func run(argumentsJSON: String) async throws -> String {
        await store.deleteAll()
        return "All recorded spending was deleted."
    }
}
