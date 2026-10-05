import AgentCore
import SwiftUI

private let mailAccent = AgentMode.lolek.accent

/// The Mail screen: every message, newest first, with four quiet filters and a search field. Reading happens on this
/// iPhone; the only network traffic is to Gmail itself.
struct MailScreen: View {
    @Bindable var model: MailModel
    var onClose: () -> Void
    var onSummarise: (EmailSummary) -> Void
    var onAsk: (EmailSummary) -> Void

    @State private var selected: EmailSummary?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            filterTabs
            Divider()
            content
        }
        .background(Color(.systemBackground))
        .tint(mailAccent)
        .task { model.reload() }
        .sheet(item: $selected) { item in
            MailDetailView(item: item, provider: model.connection.provider, onSummarise: { onSummarise(item) }, onAsk: { onAsk(item) })
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mail").font(.system(size: 30, weight: .bold))
                    subtitle
                }
                Spacer()
                Button(action: onClose) {
                    Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(mailAccent)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("mail-done")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                TextField("Search mail", text: $model.searchText)
                    .font(.system(size: 16))
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { model.reload() }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("mail-search")
                if !model.searchText.isEmpty {
                    Button { model.searchText = ""; model.reload() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// "10 unread" and, with several mailboxes, a small menu to look at one of them.
    @ViewBuilder private var subtitle: some View {
        let unread = model.connection.unread.map { String(localized: "\($0) unread") }
        if model.connection.accounts.count > 1 {
            Menu {
                Button { model.account = nil } label: { Label(String(localized: "All accounts"), systemImage: model.account == nil ? "checkmark" : "tray.2") }
                ForEach(model.connection.accounts, id: \.self) { address in
                    Button { model.account = address } label: { Label(address, systemImage: model.account == address ? "checkmark" : "envelope") }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: [unread, model.account ?? String(localized: "All accounts")].compactMap { $0 }.joined(separator: " · "))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .tint(.secondary)
            .accessibilityIdentifier("mail-accounts")
        } else {
            Text(verbatim: unread ?? model.connection.accounts.first ?? "").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    // MARK: Filters

    private var filterTabs: some View {
        HStack(spacing: 0) {
            ForEach(MailFilter.allCases) { filter in
                let isSelected = model.filter == filter
                Button { withAnimation(.easeInOut(duration: 0.2)) { model.filter = filter } } label: {
                    VStack(spacing: 8) {
                        Text(filter.title)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? mailAccent : Color.secondary)
                        Rectangle().fill(isSelected ? mailAccent : Color.clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottom)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        if !model.connection.isConnected {
            emptyState(symbol: "envelope", title: String(localized: "Connect Gmail"), detail: String(localized: "Lolek reads your mail on this iPhone only. Nothing goes to Bolek or any server.")) {
                PillButton(title: "Connect Gmail", accent: mailAccent) { Task { _ = await model.connection.connect(); model.reload() } }
            }
        } else if model.isLoading {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Reading your mail…").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = model.errorText {
            emptyState(symbol: "exclamationmark.triangle", title: String(localized: "Could not read mail"), detail: error) {
                PillButton(title: "Try again", accent: mailAccent) { model.reload() }
            }
        } else if model.items.isEmpty {
            emptyState(symbol: "tray", title: String(localized: "Nothing here"), detail: emptyDetail) { EmptyView() }
        } else {
            list
        }
    }

    private var emptyDetail: String {
        if !model.searchText.isEmpty { return String(localized: "No mail matches your search.") }
        switch model.filter {
        case .today: return String(localized: "No mail has arrived today.")
        case .unread: return String(localized: "You are all caught up.")
        case .people: return String(localized: "No mail from people.")
        case .all: return String(localized: "The inbox is empty.")
        }
    }

    private func emptyState<Action: View>(symbol: String, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
            Text(verbatim: title).font(.system(size: 18, weight: .semibold))
            Text(verbatim: detail).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            action().padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private var sections: [(title: String, items: [EmailSummary])] {
        var result: [(title: String, items: [EmailSummary])] = []
        for item in model.items {
            let title = MailDates.section(item.date)
            if result.last?.title == title { result[result.count - 1].items.append(item) } else { result.append((title, [item])) }
        }
        return result
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button { searchFocused = false; selected = item } label: { MailRow(item: item) }
                                .buttonStyle(RowPressStyle())
                                .onAppear { model.loadMoreIfNeeded(current: item) }
                        }
                    } header: {
                        Text(verbatim: section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                    }
                }
                footer
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.refreshAll() }
        .accessibilityIdentifier("mail-list")
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 6) {
            if model.isLoadingMore { ProgressView() }
            else if !model.hasMore {
                Text("That's everything.").font(.footnote).foregroundStyle(.tertiary)
            }
            Label("On this iPhone only", systemImage: "lock.fill").font(.footnote).foregroundStyle(.tertiary)
            ForEach(model.failedAccounts, id: \.self) { address in
                Text("Could not reach \(address).").font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color(.secondarySystemBackground) : Color.clear)
    }
}

struct MailRow: View {
    let item: EmailSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                MailAvatar(item: item, size: 42)
                if item.isUnread {
                    Circle().fill(mailAccent).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                        .offset(x: -3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: EmailAddress.parse(item.from).name)
                        .font(.system(size: 16, weight: item.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: MailDates.time(item.date)).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text(verbatim: item.subject)
                    .font(.system(size: 15, weight: item.isUnread ? .medium : .regular))
                    .lineLimit(1)
                Text(verbatim: EmailSanitizer.display(item.snippet))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 74) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MailAvatar: View {
    let item: EmailSummary
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(item.kind == .person ? mailAccent.opacity(0.14) : Color(.secondarySystemBackground))
            if item.kind == .person {
                Text(verbatim: initial).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(mailAccent)
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var initial: String {
        EmailAddress.parse(item.from).name.first(where: { $0.isLetter }).map { String($0).uppercased() } ?? "?"
    }

    private var symbol: String {
        switch item.kind {
        case .promotions: "tag"
        case .social: "person.2"
        default: "bell"
        }
    }
}
