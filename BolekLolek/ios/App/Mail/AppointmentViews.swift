import AgentCore
import SwiftUI

private let accent = AgentMode.lolek.accent

/// Writes an appointment from an email into the iPhone calendar, unless it is already there.
enum CalendarAdder {
    enum Outcome { case added, alreadyThere }

    static func add(title: String, start: Date, end: Date, location: String?) async throws -> Outcome {
        let calendar = AppServices.device.calendar
        // A reminder that is already in the calendar must not be added twice.
        let existing = (try? await calendar.events(from: start.addingTimeInterval(-3_600), to: end.addingTimeInterval(3_600))) ?? []
        if existing.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame && abs($0.start.timeIntervalSince(start)) < 60 }) { return .alreadyThere }
        _ = try await calendar.addEvent(title: title, start: start, end: end, location: location)
        return .added
    }
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
    var onOpenCalendar: () -> Void

    enum State { case idle, added, alreadyThere }

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
            case .added, .alreadyThere:
                Button(action: onOpenCalendar) {
                    Label(state == .added ? "Added" : "Already in your calendar", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent).labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("appointment-added")
            }
        }
    }
}

/// Details to check before the event goes into the calendar.
struct AppointmentSheet: View {
    let candidate: AppointmentCandidate
    var onSaved: (CalendarAdder.Outcome, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var error: String?
    @State private var saving = false

    init(candidate: AppointmentCandidate, onSaved: @escaping (CalendarAdder.Outcome, Date) -> Void) {
        self.candidate = candidate
        self.onSaved = onSaved
        _title = State(initialValue: candidate.title)
        _start = State(initialValue: candidate.start)
        _end = State(initialValue: candidate.effectiveEnd)
        _location = State(initialValue: candidate.location ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add to Calendar").font(.system(size: 22, weight: .bold)).padding(.top, 8)
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
                    Text("Add to Calendar").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
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
            let outcome = try await CalendarAdder.add(title: title.trimmingCharacters(in: .whitespaces), start: start, end: end, location: place.isEmpty ? nil : place)
            onSaved(outcome, start)
            dismiss()
        } catch {
            self.error = (error as? ToolError)?.message ?? error.localizedDescription
        }
    }
}
