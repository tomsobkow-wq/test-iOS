import Foundation

/// The model cannot know today's date; without it "tomorrow at 6:30" is unusable.
/// Kept out of the system prompt so that prompt stays byte-identical between turns.
public enum PromptClock {
    /// "Current date and time: Monday 2026-10-05 09:41 (Europe/Warsaw). ..." in the user's language.
    public static func line(now: Date, timeZone: TimeZone, language: ConversationLanguage) -> String {
        let stamp = "\(stamp(now, timeZone: timeZone)) (\(timeZone.identifier))"
        switch language {
        case .en: return "Current date and time: \(stamp). Weeks start on Monday. Use ISO 8601 local times in tool arguments."
        case .pl: return "Aktualna data i godzina: \(stamp). Tydzień zaczyna się w poniedziałek. W argumentach narzędzi używaj lokalnego czasu ISO 8601."
        }
    }

    /// "Monday 2026-10-05 09:41"
    public static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
