import Foundation

/// A possible appointment found in an email: from a calendar invite, or from a date with a time written in the text.
public struct AppointmentCandidate: Sendable, Equatable, Identifiable {
    public var id: String { "\(Int(start.timeIntervalSince1970))-\(title)" }
    public var title: String
    public var start: Date
    public var end: Date?
    public var location: String?
    public var fromInvite: Bool
    public var isCancelled = false

    public init(title: String, start: Date, end: Date? = nil, location: String? = nil, fromInvite: Bool = false, isCancelled: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.fromInvite = fromInvite
        self.isCancelled = isCancelled
    }

    /// One hour when the email gives no end time (the same default the calendar tool uses).
    public var effectiveEnd: Date { end ?? start.addingTimeInterval(3_600) }
}

/// Finds appointments in an email without a model. Only dates that come with a time count: a payment deadline such as
/// "due 20.10.2026" is not an appointment. Polish and English; numeric, spelled-out and weekday forms; calendar invites.
public enum AppointmentExtractor {
    public static func candidates(
        subject: String, body: String, invite: String? = nil, received: Date? = nil,
        now: Date = Date(), calendar: Calendar = .current
    ) -> [AppointmentCandidate] {
        let title = cleanTitle(subject)
        if let invite {
            let events = parseInvite(invite, fallbackTitle: title, calendar: calendar).filter { $0.start >= now.addingTimeInterval(-3_600) }
            if !events.isEmpty { return Array(events.sorted { $0.start < $1.start }.prefix(3)) }
        }
        let text = subject + "\n" + body
        let location = labelledLocation(in: body)
        var found = parseText(text, reference: received ?? now, calendar: calendar).filter { $0.start >= now.addingTimeInterval(-3_600) }
        found = found.map { var c = $0; c.title = title; c.location = location; return c }
        var unique: [AppointmentCandidate] = []
        for item in found.sorted(by: { $0.start < $1.start }) where !unique.contains(where: { $0.start == item.start }) { unique.append(item) }
        return Array(unique.prefix(3))
    }

    /// Cheap check for the list view: does this short text mention a date together with a time?
    public static func mentionsDateAndTime(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !parseText(text, reference: now, calendar: calendar).isEmpty
    }

    static func cleanTitle(_ subject: String) -> String {
        var title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = title.range(of: "^(re|fwd?|odp|pd|fw)\\s*:\\s*", options: [.regularExpression, .caseInsensitive]) { title.removeSubrange(range) }
        return title.isEmpty ? "Appointment" : title
    }

    // MARK: Text

    private static let monthNames: [String: Int] = {
        var map: [String: Int] = [:]
        let english = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let short = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let polishGenitive = ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca", "sierpnia", "wrzesnia", "pazdziernika", "listopada", "grudnia"]
        let polishNominative = ["styczen", "luty", "marzec", "kwiecien", "maj", "czerwiec", "lipiec", "sierpien", "wrzesien", "pazdziernik", "listopad", "grudzien"]
        for i in 0..<12 {
            for name in [english[i], short[i], polishGenitive[i], polishNominative[i]] { map[name] = i + 1 }
        }
        map["sept"] = 9
        return map
    }()

    private static let weekdays: [(String, Int)] = [
        ("poniedzialek", 2), ("wtorek", 3), ("srod", 4), ("czwartek", 5), ("piatek", 6), ("sobot", 7), ("niedziel", 1),
        ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7), ("sunday", 1),
    ]

    private struct Hit { let range: NSRange; let year: Int?; let month: Int?; let day: Int?; let weekday: Int?; let relativeDays: Int? }

    private static func parseText(_ text: String, reference: Date, calendar: Calendar) -> [AppointmentCandidate] {
        let folded = text.folded
        let ns = folded as NSString
        let months = monthNames.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        var hits: [Hit] = []

        func scan(_ pattern: String, _ make: (NSTextCheckingResult) -> Hit?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: folded, range: NSRange(location: 0, length: ns.length)) { if let hit = make(match) { hits.append(hit) } }
        }
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        func word(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        scan("\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b") { m in Hit(range: m.range, year: int(m, 1), month: int(m, 2), day: int(m, 3), weekday: nil, relativeDays: nil) }
        scan("\\b(\\d{1,2})[./](\\d{1,2})[./](\\d{4}|\\d{2})\\b") { m in
            guard let y = int(m, 3) else { return nil }
            return Hit(range: m.range, year: y < 100 ? 2000 + y : y, month: int(m, 2), day: int(m, 1), weekday: nil, relativeDays: nil)
        }
        scan("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(months))\\b\\.?(?:\\s*,?\\s*(\\d{4}))?") { m in
            guard let name = word(m, 2), let month = monthNames[name] else { return nil }
            return Hit(range: m.range, year: int(m, 3), month: month, day: int(m, 1), weekday: nil, relativeDays: nil)
        }
        scan("\\b(\(months))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:\\s*,?\\s*(\\d{4}))?") { m in
            guard let name = word(m, 1), let month = monthNames[name] else { return nil }
            return Hit(range: m.range, year: int(m, 3), month: month, day: int(m, 2), weekday: nil, relativeDays: nil)
        }
        scan("\\b(poniedzialek|wtorek|srod\\w*|czwartek|piatek|sobot\\w*|niedziel\\w*|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b") { m in
            guard let name = word(m, 1), let day = weekdays.first(where: { name.hasPrefix($0.0) })?.1 else { return nil }
            return Hit(range: m.range, year: nil, month: nil, day: nil, weekday: day, relativeDays: nil)
        }
        scan("\\b(jutro|tomorrow|pojutrze|dzisiaj|dzis|today)\\b") { m in
            let offset = ["jutro": 1, "tomorrow": 1, "pojutrze": 2][word(m, 1) ?? ""] ?? 0
            return Hit(range: m.range, year: nil, month: nil, day: nil, weekday: nil, relativeDays: offset)
        }

        var results: [AppointmentCandidate] = []
        let startOfRef = calendar.startOfDay(for: reference)
        for hit in hits {
            // The time sits right after the date ("12 October at 14:30") or just before it ("14:30, 12 October").
            let after = NSRange(location: hit.range.location + hit.range.length, length: min(34, ns.length - hit.range.location - hit.range.length))
            let beforeStart = max(0, hit.range.location - 18)
            let before = NSRange(location: beforeStart, length: hit.range.location - beforeStart)
            guard let time = firstTime(in: ns, ranges: [after, before]) else { continue }

            var day: Date?
            if let month = hit.month, let dayNumber = hit.day {
                var comps = DateComponents(); comps.month = month; comps.day = dayNumber
                if let year = hit.year { comps.year = year; day = calendar.date(from: comps) } else {
                    comps.year = calendar.component(.year, from: reference)
                    day = calendar.date(from: comps)
                    if let d = day, d < startOfRef.addingTimeInterval(-86_400) { comps.year! += 1; day = calendar.date(from: comps) }
                }
            } else if let weekday = hit.weekday {
                day = calendar.nextDate(after: startOfRef.addingTimeInterval(-1), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
            } else if let offset = hit.relativeDays {
                day = calendar.date(byAdding: .day, value: offset, to: startOfRef)
            }
            guard let day, let start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else { continue }
            var end: Date?
            if let endTime = time.end, let e = calendar.date(bySettingHour: endTime.0, minute: endTime.1, second: 0, of: day), e > start { end = e }
            results.append(AppointmentCandidate(title: "", start: start, end: end))
        }
        return results
    }

    private struct FoundTime { let hour: Int; let minute: Int; let end: (Int, Int)? }

    private static func firstTime(in ns: NSString, ranges: [NSRange]) -> FoundTime? {
        let clock = try? NSRegularExpression(pattern: "(?<![\\d:.])(\\d{1,2}):(\\d{2})\\s*(am|pm)?(?:\\s*(?:-|to|do)\\s*(\\d{1,2}):(\\d{2})\\s*(am|pm)?)?")
        let twelve = try? NSRegularExpression(pattern: "(?<![\\d:.])(\\d{1,2})\\s*(am|pm)\\b")
        let godz = try? NSRegularExpression(pattern: "godz\\.?\\s*(\\d{1,2})(?:[.:](\\d{2}))?")
        for range in ranges where range.length > 0 {
            let part = ns.substring(with: range) as NSString
            let whole = NSRange(location: 0, length: part.length)
            func num(_ m: NSTextCheckingResult, _ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(part.substring(with: m.range(at: i))) }
            func str(_ m: NSTextCheckingResult, _ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : part.substring(with: m.range(at: i)) }
            func hour24(_ h: Int, _ suffix: String?) -> Int {
                guard let suffix else { return h }
                return suffix == "pm" ? (h % 12) + 12 : (h % 12)
            }
            if let m = clock?.firstMatch(in: String(part), range: whole), let h = num(m, 1), let min = num(m, 2), h < 24, min < 60 {
                var end: (Int, Int)?
                if let eh = num(m, 4), let em = num(m, 5), eh < 24, em < 60 { end = (hour24(eh, str(m, 6) ?? str(m, 3)), em) }
                return FoundTime(hour: hour24(h, str(m, 3)), minute: min, end: end)
            }
            if let m = twelve?.firstMatch(in: String(part), range: whole), let h = num(m, 1), (1...12).contains(h) {
                return FoundTime(hour: hour24(h, str(m, 2)), minute: 0, end: nil)
            }
            if let m = godz?.firstMatch(in: String(part), range: whole), let h = num(m, 1), h < 24 {
                return FoundTime(hour: h, minute: num(m, 2) ?? 0, end: nil)
            }
        }
        return nil
    }

    private static func labelledLocation(in body: String) -> String? {
        for line in body.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if let range = text.range(of: "^(location|where|venue|address|miejsce|adres|lokalizacja|gdzie)\\s*[:\\-–]\\s*", options: [.regularExpression, .caseInsensitive]) {
                let value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return String(value.prefix(160)) }
            }
        }
        return nil
    }

    // MARK: Calendar invites (.ics)

    static func parseInvite(_ ics: String, fallbackTitle: String, calendar: Calendar) -> [AppointmentCandidate] {
        // Unfold continuation lines, then read VEVENT blocks.
        let unfolded = ics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        let cancelled = unfolded.range(of: "METHOD:CANCEL", options: .caseInsensitive) != nil
        var out: [AppointmentCandidate] = []
        for block in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let body = block.components(separatedBy: "END:VEVENT").first ?? block
            var props: [String: (params: String, value: String)] = [:]
            for line in body.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = String(line[..<colon]), value = String(line[line.index(after: colon)...])
                let name = head.split(separator: ";").first.map { String($0).uppercased() } ?? head.uppercased()
                let params = head.contains(";") ? String(head[head.index(after: head.firstIndex(of: ";")!)...]) : ""
                if props[name] == nil { props[name] = (params, value) }
            }
            guard let startProp = props["DTSTART"], let start = icsDate(startProp.value, params: startProp.params, calendar: calendar) else { continue }
            let end = props["DTEND"].flatMap { icsDate($0.value, params: $0.params, calendar: calendar) }
            let summary = props["SUMMARY"].map { icsText($0.value) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
            let location = props["LOCATION"].map { icsText($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
            let isCancelled = cancelled || props["STATUS"]?.value.uppercased() == "CANCELLED"
            out.append(AppointmentCandidate(title: summary, start: start, end: end, location: location, fromInvite: true, isCancelled: isCancelled))
        }
        return out
    }

    private static func icsText(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func icsDate(_ value: String, params: String, calendar: Calendar) -> Date? {
        let text = value.trimmingCharacters(in: .whitespaces)
        var zone = calendar.timeZone
        if text.hasSuffix("Z") { zone = TimeZone(identifier: "UTC")! }
        else if let range = params.range(of: "TZID=") {
            let id = params[range.upperBound...].split(separator: ";").first.map(String.init) ?? ""
            zone = TimeZone(identifier: id.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? zone
        }
        var cal = calendar
        cal.timeZone = zone
        let digits = text.replacingOccurrences(of: "Z", with: "")
        let parts = digits.split(separator: "T")
        guard let datePart = parts.first, datePart.count == 8, let y = Int(datePart.prefix(4)), let mo = Int(datePart.dropFirst(4).prefix(2)), let d = Int(datePart.suffix(2)) else { return nil }
        var comps = DateComponents(year: y, month: mo, day: d)
        if parts.count > 1 {
            let time = parts[1]
            comps.hour = Int(time.prefix(2)); comps.minute = Int(time.dropFirst(2).prefix(2)); comps.second = Int(time.dropFirst(4).prefix(2)) ?? 0
        } else {
            comps.hour = 9; comps.minute = 0  // an all-day invite: show it at 09:00 for the user to adjust
        }
        return cal.date(from: comps)
    }
}
