import AgentCore
import SwiftUI

private let accent = AgentMode.lolek.accent

/// Writes an appointment from an email into the iPhone calendar, unless it is already there.
enum CalendarAdder {
    enum Outcome: Equatable { case added(String), alreadyThere(String)
        var id: String { switch self { case .added(let id), .alreadyThere(let id): id } }
    }

    static func add(title: String, start: Date, end: Date, location: String?) async throws -> Outcome {
        let calendar = AppServices.device.calendar
        // An event that is already in the calendar must not be added twice.
        let existing = (try? await calendar.events(from: start.addingTimeInterval(-3_600), to: end.addingTimeInterval(3_600))) ?? []
        if let same = existing.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame && abs($0.start.timeIntervalSince(start)) < 60 }) { return .alreadyThere(same.id) }
        let event = try await calendar.addEvent(title: title, start: start, end: end, location: location)
        return .added(event.id)
    }

    static func update(id: String, title: String, start: Date, end: Date, location: String?) async throws {
        _ = try await AppServices.device.calendar.updateEvent(id: id, title: title, start: start, end: end, location: location ?? "")
    }

    static func remove(id: String) async throws { try await AppServices.device.calendar.deleteEvent(id: id) }
}

enum AppointmentFormat {
    static func when(_ candidate: AppointmentCandidate) -> String { when(start: candidate.start, end: candidate.effectiveEnd) }

    static func dateLine(_ start: Date) -> String {
        let day = DateFormatter(); day.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
        return day.string(from: start).capitalized
    }

    static func timeLine(start: Date, end: Date) -> String {
        let time = DateFormatter(); time.timeStyle = .short; time.dateStyle = .none
        return "\(time.string(from: start))–\(time.string(from: end))"
    }

    static func when(start: Date, end: Date) -> String {
        let day = DateFormatter(); day.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        let time = DateFormatter(); time.timeStyle = .short; time.dateStyle = .none
        return "\(day.string(from: start)) · \(time.string(from: start))–\(time.string(from: end))"
    }
}

/// "This email mentions an appointment": found by code, added with one tap and a look at the details.
struct AppointmentCard: View {
    let candidate: AppointmentCandidate
    let state: State
    var onAdd: () -> Void
    var onChange: () -> Void
    var onRemove: () -> Void
    var onOpenCalendar: () -> Void

    enum State: Equatable { case idle, saved(id: String, alreadyThere: Bool) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppointmentFormat.dateLine(candidate.start)).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: AppointmentFormat.timeLine(start: candidate.start, end: candidate.effectiveEnd)).font(.system(size: 14)).foregroundStyle(.primary.opacity(0.8))
                if let location = candidate.location {
                    Text(verbatim: location).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        if candidate.isCancelled {
            Text("Cancelled").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
        } else {
            switch state {
            case .idle:
                Button(action: onAdd) {
                    Text("Add").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 16).frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                }
                .accessibilityIdentifier("appointment-add")
            case .saved(_, let alreadyThere):
                Menu {
                    Button(action: onChange) { Label("Change time or details", systemImage: "calendar.badge.clock") }
                    Button(action: onOpenCalendar) { Label("Open in Calendar", systemImage: "calendar") }
                    Button(role: .destructive, action: onRemove) { Label("Remove from calendar", systemImage: "trash") }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(alreadyThere ? "In your calendar" : "Added")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                }
                .accessibilityIdentifier("appointment-added")
            }
        }
    }
}

/// Details to check before the event goes into the calendar.
struct AppointmentSheet: View {
    let candidate: AppointmentCandidate
    /// Set when the event is already in the calendar and this sheet changes it instead of adding it.
    var existingID: String?
    var onSaved: (CalendarAdder.Outcome, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var error: String?
    @State private var saving = false

    init(candidate: AppointmentCandidate, existingID: String? = nil, onSaved: @escaping (CalendarAdder.Outcome, Date) -> Void) {
        self.candidate = candidate
        self.existingID = existingID
        self.onSaved = onSaved
        _title = State(initialValue: candidate.title)
        _start = State(initialValue: candidate.start)
        _end = State(initialValue: candidate.effectiveEnd)
        _location = State(initialValue: candidate.location ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existingID == nil ? "Add to Calendar" : "Change appointment").font(.system(size: 22, weight: .bold)).padding(.top, 8)
            VStack(spacing: 0) {
                field("Title") { TextField("Title", text: $title).font(.system(size: 16)).accessibilityIdentifier("appointment-title") }
                Divider()
                field("Starts") { DatePicker("Starts", selection: $start).labelsHidden().onChange(of: start) { _, new in if end <= new { end = new.addingTimeInterval(3_600) } } }
                Divider()
                field("Ends") { DatePicker("Ends", selection: $end, in: start...).labelsHidden() }
                Divider()
                field("Location") { TextField("Optional", text: $location).font(.system(size: 16)) }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            if let error { Text(verbatim: error).font(.footnote).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Cancel").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 22).frame(minHeight: 48).overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                }
                Button { Task { await save() } } label: {
                    Text(existingID == nil ? "Add to Calendar" : "Save changes").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48).background(accent, in: Capsule())
                }
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("appointment-save")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .tint(accent)
    }

    private func field<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let place = location.trimmingCharacters(in: .whitespaces)
            let name = title.trimmingCharacters(in: .whitespaces)
            let outcome: CalendarAdder.Outcome
            if let existingID {
                try await CalendarAdder.update(id: existingID, title: name, start: start, end: end, location: place.isEmpty ? nil : place)
                outcome = .alreadyThere(existingID)
            } else {
                outcome = try await CalendarAdder.add(title: name, start: start, end: end, location: place.isEmpty ? nil : place)
            }
            onSaved(outcome, start)
            dismiss()
        } catch {
            self.error = (error as? ToolError)?.message ?? error.localizedDescription
        }
    }
}
