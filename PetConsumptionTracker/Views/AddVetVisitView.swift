import SwiftUI

struct AddVetVisitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let pet: PetEntity

    @State private var visitDate = Date()
    @State private var reason = ""
    @State private var vetName = ""
    @State private var clinicName = ""
    @State private var notes = ""
    @State private var reminderEnabled = true

    // Common visit reasons
    private let commonReasons = [
        "Annual Checkup",
        "Vaccination",
        "Dental Cleaning",
        "Illness/Symptoms",
        "Follow-up",
        "Surgery",
        "Grooming",
        "Emergency",
        "Other"
    ]

    @State private var selectedReason: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.2))
                                .frame(width: 60, height: 60)
                            Image(systemName: "cross.case.fill")
                                .font(.title)
                                .foregroundColor(.teal)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Schedule Vet Visit")
                                .font(.headline)
                            Text("for \(pet.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }

                Section("Date & Time") {
                    DatePicker(
                        "Visit Date",
                        selection: $visitDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(.teal)
                }

                Section("Visit Reason") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonReasons, id: \.self) { reasonOption in
                                Button(action: {
                                    selectedReason = reasonOption
                                    if reasonOption != "Other" {
                                        reason = reasonOption
                                    }
                                }) {
                                    Text(reasonOption)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedReason == reasonOption ?
                                            Color.teal : Color(.systemGray5)
                                        )
                                        .foregroundColor(
                                            selectedReason == reasonOption ?
                                            .white : .primary
                                        )
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if selectedReason == "Other" || selectedReason == nil {
                        TextField("Describe the reason", text: $reason)
                    }
                }

                Section("Veterinarian (Optional)") {
                    TextField("Vet Name (e.g., Dr. Smith)", text: $vetName)
                    TextField("Clinic Name", text: $clinicName)
                }

                Section("Reminders") {
                    Toggle("Enable Reminders", isOn: $reminderEnabled)

                    if reminderEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.teal)
                                    .font(.caption)
                                Text("You'll receive reminders:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                reminderItem("1 day before the visit")
                                reminderItem("1 hour before the visit")
                                reminderItem("At the appointment time")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    visitSummaryView
                }
            }
            .navigationTitle("Schedule Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        saveVisit()
                    }
                    .disabled(reason.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func reminderItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var visitSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.teal)
                Text("Visit Summary")
                    .font(.headline)
            }

            if !reason.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Date:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(visitDate.formatted(date: .abbreviated, time: .shortened))
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Reason:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(reason)
                            .fontWeight(.medium)
                    }

                    if daysUntilVisit > 0 {
                        HStack {
                            Text("In:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(daysUntilVisit) day\(daysUntilVisit == 1 ? "" : "s")")
                                .fontWeight(.medium)
                                .foregroundColor(.teal)
                        }
                    }
                }
                .font(.subheadline)
            } else {
                Text("Select a reason for the visit")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var daysUntilVisit: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: visitDate)
        return max(0, components.day ?? 0)
    }

    private func saveVisit() {
        withAnimation {
            let visit = VetVisitEntity(context: viewContext)
            visit.id = UUID()
            visit.visitDate = visitDate
            visit.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            visit.vetName = vetName.isEmpty ? nil : vetName.trimmingCharacters(in: .whitespacesAndNewlines)
            visit.clinicName = clinicName.isEmpty ? nil : clinicName.trimmingCharacters(in: .whitespacesAndNewlines)
            visit.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
            visit.isCompleted = false
            visit.reminderEnabled = reminderEnabled
            visit.createdAt = Date()
            visit.pet = pet

            do {
                try viewContext.save()

                if reminderEnabled {
                    NotificationManager.shared.scheduleVetVisitNotifications(for: visit)
                }

                dismiss()
            } catch {
                print("Error saving vet visit: \(error)")
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let pet = PetEntity(context: context)
    pet.id = UUID()
    pet.name = "Buddy"
    pet.species = "Dog"

    return AddVetVisitView(pet: pet)
        .environment(\.managedObjectContext, context)
}
