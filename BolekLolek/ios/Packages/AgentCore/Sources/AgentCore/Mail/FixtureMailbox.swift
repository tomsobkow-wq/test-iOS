import Foundation

/// A made-up mailbox: invented people, companies and messages in Polish and English. Used by tests and by the debug
/// screenshots of the Mail screen, so nothing real is ever shown. It understands the few Gmail search words the app builds.
public final class FixtureMailbox: EmailProviding, MailboxPaging, @unchecked Sendable {
    struct Item {
        let id: String
        let minutesAgo: Int
        let from: String
        let subject: String
        let snippet: String
        let body: String
        let kind: EmailKind
        let unread: Bool
        var invite: String? = nil
    }

    private let now: Date
    private let items: [Item]
    public let label: String

    public init(label: String = "demo@example.com", now: Date = Date(), calendar: Calendar = .current) {
        self.label = label
        self.now = now
        let startOfToday = calendar.startOfDay(for: now)
        let sinceMidnight = Int(now.timeIntervalSince(startOfToday) / 60)
        // Today's messages are placed after midnight so "today" is never empty, whatever the time.
        func today(_ minutes: Int) -> Int { min(max(sinceMidnight - minutes, 1), max(sinceMidnight - 1, 1)) }
        func day(_ ago: Int, _ minutes: Int) -> Int { sinceMidnight + (ago - 1) * 1440 + minutes }
        var list: [Item] = []
        func add(_ id: String, _ minutes: Int, _ from: String, _ subject: String, _ snippet: String, _ kind: EmailKind, unread: Bool = false, body: String? = nil, invite: String? = nil) {
            list.append(Item(id: id, minutesAgo: minutes, from: from, subject: subject, snippet: snippet, body: body ?? snippet, kind: kind, unread: unread, invite: invite))
        }
        add("d0a1", today(25), "Przychodnia Zdrowie <rejestracja@przychodnia.example>", "Lolek test – wizyta kontrolna", "Przypominamy o wizycie kontrolnej 14.01.2027 o godz. 10:30.", .updates,
            body: "Dzień dobry,\n\nprzypominamy o wizycie kontrolnej 14.01.2027 o godz. 10:30.\nAdres: ul. Marszałkowska 10, Warszawa\n\nProsimy o potwierdzenie obecności. Termin płatności za poprzednią wizytę: 20.10.2026.")
        add("d0a2", today(70), "Sarah Mitchell <sarah.mitchell@example.com>", "Team sync", "Can we do Thursday at 3pm? Room 4B.", .person,
            body: "Hi,\n\ncan we do Thursday at 3pm? I booked the small room.\nLocation: Room 4B\n\nSarah")
        add("d0a3", today(100), "Google Calendar <calendar-notification@google.example>", "Invitation: Przegląd projektu", "Zaproszenie na 20 stycznia 2027, 15:00 - 16:00.", .updates,
            body: "Zaproszenie na spotkanie. Szczegóły w załączonym pliku.",
            invite: "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Europe/Warsaw:20270120T150000\r\nDTEND;TZID=Europe/Warsaw:20270120T160000\r\nSUMMARY:Lolek test – przegląd projektu\r\nLOCATION:Google Meet\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
        add("a001", today(12), "Anna Nowak <anna.nowak@example.com>", "Re: Weekend w Krakowie", "Super, to bierzemy ten apartament przy Plantach. Wyślę Ci link do rezerwacji jeszcze dziś wieczorem.", .person, unread: true,
            body: "Cześć!\n\nSuper, to bierzemy ten apartament przy Plantach. Wyślę Ci link do rezerwacji jeszcze dziś wieczorem. Koszt to 640 zł za dwie noce, płatne przy zameldowaniu.\n\nAnia")
        add("a002", today(55), "Delta Air Lines <no-reply@delta.example>", "Your flight DL 218 is delayed", "New departure time 18:40. We apologise for the inconvenience.", .updates, unread: true,
            body: "Flight DL 218 Warsaw to Amsterdam is delayed by 2 hours 10 minutes. New departure 18:40 from gate B12.\n\nTo manage your trip visit https://delta.example/trips/manage?token=abc123secret")
        add("a003", today(90), "Sarah Mitchell <sarah.mitchell@example.com>", "Lunch Thursday?", "Are you free around 1pm? There's a new place near the office that does great ramen.", .person, unread: true)
        add("a004", today(130), "mBank <powiadomienia@mbank.example>", "Nowy wyciąg jest dostępny", "Wyciąg za wrzesień 2026 został wygenerowany i czeka w serwisie transakcyjnym.", .updates)
        add("a005", today(170), "Google <no-reply@accounts.example>", "Your verification code", "Your verification code is 482913", .updates, unread: true,
            body: "Your verification code is 482913. Do not share it with anyone. If you did not request this, reset your password at https://accounts.example/reset?token=zzz999.")
        add("a006", today(210), "Zara Polska <newsletter@zara.example>", "Nowa kolekcja jesień - do -30%", "Odkryj nowości i skorzystaj z rabatu tylko do niedzieli.", .promotions)
        add("a007", today(240), "Allegro <oferty@allegro.example>", "Twoje obserwowane produkty staniały", "Sprawdź 6 obniżek cen w kategorii Elektronika.", .promotions)
        add("a008", today(300), "Booking.com <noreply@booking.example>", "Lizbona czeka: ostatnie wolne pokoje", "Hotele od 289 zł za noc na Twoje daty.", .promotions)
        add("a009", today(360), "GitHub <noreply@github.example>", "[bolek-lolek] Run failed: build", "The build failed on main for commit 9358bf3.", .updates)
        add("a00a", today(420), "Tomek Wiśniewski <tomek.w@example.com>", "Faktura za wrzesień", "Przesyłam fakturę nr 2026/09/114 na kwotę 1 230,00 zł. Termin płatności 14 dni.", .person, unread: true,
            body: "Dzień dobry,\n\nprzesyłam fakturę nr 2026/09/114 na kwotę 1 230,00 zł. Termin płatności: 14 dni od daty wystawienia.\n\nPozdrawiam,\nTomek")
        add("a00b", today(480), "LinkedIn <notifications@linkedin.example>", "Marta Lis i 3 inne osoby zobaczyły Twój profil", "Zobacz, kto przeglądał Twój profil w tym tygodniu.", .social)
        add("a00c", today(520), "Tauron <faktury@tauron.example>", "Faktura za energię elektryczną", "Do zapłaty 212,55 zł do 20.10.2026.", .updates)
        add("a00d", today(600), "Spotify <no-reply@spotify.example>", "Twój Wrapped czeka", "Zobacz, czego słuchałeś w tym roku.", .promotions)
        add("a00e", today(660), "Uber Eats <orders@ubereats.example>", "Zamów obiad z rabatem 15 zł", "Użyj kodu OBIAD15 w aplikacji.", .promotions)
        let people = [("Jan Kowalski <jan.kowalski@example.com>", "Umowa najmu - podpis"), ("Ewa Dąbrowska <ewa.d@example.com>", "Zdjęcia z wyjazdu"), ("Michael Brown <m.brown@example.com>", "Quarterly numbers"), ("Kasia <kasia.k@example.com>", "Urodziny Zosi w sobotę")]
        let updates = [("Netflix <info@netflix.example>", "Twoja płatność została przyjęta"), ("InPost <powiadomienia@inpost.example>", "Paczka czeka w paczkomacie WAW12M"), ("PKP Intercity <bilet@intercity.example>", "Twój e-bilet na 12 października"), ("Apple <no_reply@apple.example>", "Your receipt from Apple")]
        let promos = [("Empik <promocje@empik.example>", "Książki 2+1 gratis"), ("Decathlon <newsletter@decathlon.example>", "Wyprzedaż sprzętu na jesień"), ("Rossmann <klub@rossmann.example>", "-55% na kosmetyki"), ("Media Expert <oferty@mediaexpert.example>", "Czarny Piątek już w październiku")]
        var n = 0x100
        for ago in 1...6 {
            for (offset, entry) in people.enumerated() where (ago + offset) % 2 == 0 {
                add("b\(String(n, radix: 16))", day(ago, 60 + offset * 90), entry.0, entry.1, "Krótka wiadomość od \(EmailAddress.parse(entry.0).name.split(separator: " ")[0]).", .person); n += 1
            }
            for (offset, entry) in updates.enumerated() { add("c\(String(n, radix: 16))", day(ago, 30 + offset * 140), entry.0, entry.1, "Powiadomienie automatyczne.", .updates); n += 1 }
            for (offset, entry) in promos.enumerated() where (ago + offset) % 2 == 1 { add("d\(String(n, radix: 16))", day(ago, 200 + offset * 100), entry.0, entry.1, "Oferta ograniczona czasowo.", .promotions); n += 1 }
        }
        items = list.sorted { $0.minutesAgo < $1.minutesAgo }
    }

    public func isConnected() async -> Bool { true }
    public func accountLabels() async -> [String] { [label] }
    public func unreadCount() async -> Int? { items.filter(\.unread).count }

    public func search(query: String, limit: Int) async throws -> [EmailSummary] {
        Array(matching(query).prefix(limit)).map(summary)
    }

    public func page(query: String, pageToken: String?, size: Int) async throws -> EmailPage {
        let all = matching(query)
        let start = Int(pageToken ?? "") ?? 0
        let end = min(start + max(1, size), all.count)
        return EmailPage(items: all[start..<end].map(summary), nextToken: end < all.count ? String(end) : nil, estimatedTotal: all.count)
    }

    public func feed(query: String, account: String?) async -> MailFeed? {
        MailFeed(sources: [(position: 0, label: label, paging: self)], query: query, labelled: false)
    }

    public func message(id: String) async throws -> EmailMessage {
        guard let item = items.first(where: { $0.id == id }) else { throw ToolError("That email no longer exists.") }
        return EmailMessage(summary: summary(item), to: label, body: item.body, invite: item.invite)
    }

    private func summary(_ item: Item) -> EmailSummary {
        EmailSummary(id: item.id, from: item.from, subject: item.subject, date: now.addingTimeInterval(-Double(item.minutesAgo) * 60),
                     snippet: item.snippet, isUnread: item.unread, kind: item.kind)
    }

    /// Understands what `EmailQueryBuilder` writes: in:inbox, after:, before:, is:unread, from:(...), and plain words.
    private func matching(_ query: String) -> [Item] {
        var after: Double?
        var before: Double?
        var unread = false
        var primaryOnly = false
        var eventsOnly = false
        var from: String?
        var words: [String] = []
        var rest = query
        // The Events filter is a Gmail OR-group ({subject:(...) filename:ics}); the fixture only needs to know it was asked.
        if rest.contains("filename:ics") { eventsOnly = true }
        rest = rest.replacingOccurrences(of: "\\{[^}]*\\}", with: " ", options: .regularExpression)
        if let range = rest.range(of: "from:\\(([^)]*)\\)", options: .regularExpression) {
            from = String(rest[range]).dropFirst(6).dropLast().lowercased()
            rest.removeSubrange(range)
        }
        for token in rest.split(separator: " ").map(String.init) {
            if token == "in:inbox" { continue }
            else if token == "is:unread" { unread = true }
            else if token == "category:primary" { primaryOnly = true }
            else if token.hasPrefix("after:") { after = Double(token.dropFirst(6)) }
            else if token.hasPrefix("before:") { before = Double(token.dropFirst(7)) }
            else { words.append(token.lowercased()) }
        }
        return items.filter { item in
            let date = now.addingTimeInterval(-Double(item.minutesAgo) * 60).timeIntervalSince1970
            if let after, date < after { return false }
            if let before, date >= before { return false }
            if unread, !item.unread { return false }
            if primaryOnly, item.kind != .person { return false }
            if eventsOnly, item.invite == nil, !AppointmentExtractor.mentionsDateAndTime(item.subject + "\n" + item.body, now: now) { return false }
            if let from, !item.from.lowercased().contains(from) { return false }
            let haystack = (item.subject + " " + item.snippet + " " + item.from).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
