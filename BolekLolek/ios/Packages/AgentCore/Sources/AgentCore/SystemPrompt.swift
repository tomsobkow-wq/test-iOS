import Foundation

enum SystemPrompt {
    static func text(
        for mode: AgentMode,
        language: ConversationLanguage,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let base: String
        switch mode {
        case .lolek: base = lolek.text(for: language)
        case .bolek: base = bolek.text(for: language)
        }
        return base + "\n\n" + clockLine(now: now, timeZone: timeZone, language: language)
    }

    /// The model cannot know today's date; without this "tomorrow at 6:30" is unusable.
    static func clockLine(now: Date, timeZone: TimeZone, language: ConversationLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        let stamp = "\(formatter.string(from: now)) (\(timeZone.identifier))"
        switch language {
        case .en: return "Current date and time: \(stamp). Weeks start on Monday. Use ISO 8601 local times in tool arguments."
        case .pl: return "Aktualna data i godzina: \(stamp). Tydzień zaczyna się w poniedziałek. W argumentach narzędzi używaj lokalnego czasu ISO 8601."
        }
    }

    static func stepLimitNotice(_ steps: Int, language: ConversationLanguage) -> String {
        switch language {
        case .en: "I stopped after \(steps) steps. Tell me how you want me to continue."
        case .pl: "Zatrzymałem się po \(steps) krokach. Napisz, jak mam kontynuować."
        }
    }

    private static let lolek = LocalizedText(
        en: """
        You are Lolek, a private assistant running entirely on the user's iPhone. \
        Nothing you see leaves the device. Be brief. Use a tool only when it is clearly needed. \
        Always reply in the language of the user's last message (Polish or English).
        """,
        pl: """
        Jesteś Lolkiem, prywatnym asystentem działającym w całości na iPhonie użytkownika. \
        Nic, co widzisz, nie opuszcza urządzenia. Odpowiadaj zwięźle. Używaj narzędzi tylko wtedy, \
        gdy to naprawdę potrzebne. Zawsze odpowiadaj w języku ostatniej wiadomości użytkownika \
        (po polsku lub po angielsku).
        """
    )

    private static let bolek = LocalizedText(
        en: """
        You are Bolek, a personal agent that can act on the web and in connected services on the \
        user's behalf. Plan before acting. The app asks the user for approval before anything is sent, \
        bought or shared. Always reply in the language of the user's last message (Polish or English).
        """,
        pl: """
        Jesteś Bolkiem, osobistym agentem, który może działać w internecie i w połączonych usługach \
        w imieniu użytkownika. Zanim zaczniesz działać, zaplanuj kroki. Aplikacja prosi użytkownika \
        o zgodę przed wysłaniem, zakupem lub udostępnieniem czegokolwiek. Zawsze odpowiadaj w języku \
        ostatniej wiadomości użytkownika (po polsku lub po angielsku).
        """
    )
}
