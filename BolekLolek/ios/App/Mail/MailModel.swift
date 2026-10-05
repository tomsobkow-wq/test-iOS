import AgentCore
import Observation
import SwiftUI

enum MailFilter: String, CaseIterable, Identifiable {
    case today, unread, people, events, all
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .unread: "Unread"
        case .people: "People"
        case .events: "Events"
        case .all: "All"
        }
    }
}

/// What the Mail screen shows. Browsing is done by code (Gmail paging), never by the model: the screen lists every
/// message, newest first, and loads more as you scroll. Nothing here leaves the phone except requests to Gmail.
@MainActor
@Observable
final class MailModel {
    let connection: MailConnection

    var filter: MailFilter = .today { didSet { if oldValue != filter { reload() } } }
    var account: String? { didSet { if oldValue != account { reload() } } }
    var searchText = ""

    private(set) var items: [EmailSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorText: String?
    private(set) var failedAccounts: [String] = []
    private(set) var hasLoaded = false
    /// Messages whose subject or preview mentions a date with a time (shown with a small calendar mark in the list).
    private(set) var calendarHints: Set<String> = []

    private var feed: MailFeed?
    private var generation = 0
    private var task: Task<Void, Never>?
    private let pageSize = 30

    init(connection: MailConnection) { self.connection = connection }

    private var spec: EmailQuerySpec {
        var spec = EmailQuerySpec(account: account)
        switch filter {
        case .today: spec.when = .today
        case .unread: spec.unread = true
        case .people: spec.raw = "category:primary"
        case .events: spec.raw = "in:inbox {subject:(appointment OR meeting OR invitation OR invite OR reservation OR booking OR wizyta OR spotkanie OR termin OR rezerwacja OR zaproszenie) filename:ics}"
        case .all: break
        }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { spec.text = text }
        return spec
    }

    func reload() {
        task?.cancel()
        generation += 1
        let mine = generation
        items = []
        hasMore = false
        errorText = nil
        failedAccounts = []
        guard connection.isConnected else { isLoading = false; hasLoaded = true; return }
        isLoading = true
        let query = EmailQueryBuilder().gmailQuery(spec)
        let account = account
        task = Task {
            let feed = await connection.provider.feed(query: query, account: account)
            do {
                guard let feed else { throw ToolError(String(localized: "No mailbox is connected.")) }
                let batch = try await feed.next(pageSize)
                guard mine == generation else { return }
                self.feed = feed
                items = batch
                noteCalendarHints(batch, replacing: true)
                hasMore = !(await feed.isExhausted)
                failedAccounts = await feed.failedAccounts
            } catch {
                guard mine == generation, !Task.isCancelled else { return }
                errorText = (error as? ToolError)?.message ?? error.localizedDescription
            }
            if mine == generation { isLoading = false; hasLoaded = true }
        }
    }

    func loadMoreIfNeeded(current item: EmailSummary) {
        guard hasMore, !isLoadingMore, !isLoading, item.id == items.last?.id, let feed else { return }
        isLoadingMore = true
        let mine = generation
        Task {
            let batch = (try? await feed.next(pageSize)) ?? []
            guard mine == generation else { return }
            items += batch
            noteCalendarHints(batch, replacing: false)
            hasMore = !(await feed.isExhausted) && !batch.isEmpty
            failedAccounts = await feed.failedAccounts
            isLoadingMore = false
        }
    }

    private func noteCalendarHints(_ batch: [EmailSummary], replacing: Bool) {
        if replacing { calendarHints = [] }
        for item in batch where AppointmentExtractor.mentionsDateAndTime(item.subject + "\n" + item.snippet) { calendarHints.insert(item.id) }
    }

    func refreshAll() async {
        await connection.refreshUnread()
        reload()
        await task?.value
    }
}

enum MailDates {
    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short; formatter.dateStyle = .none
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        }
        return formatter.string(from: date)
    }

    static func section(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEEE d MMMM" : "d MMMM yyyy")
        return formatter.string(from: date).capitalized
    }

    static func full(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
