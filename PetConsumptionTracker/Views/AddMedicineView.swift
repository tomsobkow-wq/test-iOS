import SwiftUI

struct AddMedicineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let pet: PetEntity

    @State private var name = ""
    @State private var dosage = ""
    @State private var frequencyHours: Double = 24
    @State private var notes = ""
    @State private var notificationEnabled = true
    @State private var selectedFrequencyType = FrequencyType.daily

    enum FrequencyType: String, CaseIterable {
        case hourly = "Hourly"
        case daily = "Daily"
        case everyXDays = "Every X Days"
        case weekly = "Weekly"

        var defaultHours: Double {
            switch self {
            case .hourly: return 6
            case .daily: return 24
            case .everyXDays: return 48
            case .weekly: return 168
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.2))
                                .frame(width: 60, height: 60)
                            Image(systemName: "pills.fill")
                                .font(.title)
                                .foregroundColor(.purple)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add Medicine")
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

                Section("Medicine Details") {
                    TextField("Medicine Name", text: $name)
                        .textContentType(.name)

                    TextField("Dosage (e.g., 1 tablet, 5ml)", text: $dosage)
                }

                Section("Frequency") {
                    Picker("Schedule", selection: $selectedFrequencyType) {
                        ForEach(FrequencyType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: selectedFrequencyType) { _, newValue in
                        frequencyHours = newValue.defaultHours
                    }

                    frequencyPicker
                }

                Section("Reminders") {
                    Toggle("Notification Reminders", isOn: $notificationEnabled)

                    if notificationEnabled {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.purple)
                            Text("You'll be reminded when it's time for the next dose")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    summaryView
                }
            }
            .navigationTitle("Add Medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMedicine()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var frequencyPicker: some View {
        switch selectedFrequencyType {
        case .hourly:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Every:")
                    Spacer()
                    Text("\(Int(frequencyHours)) hours")
                        .foregroundColor(.secondary)
                }
                Slider(value: $frequencyHours, in: 1...23, step: 1)
                    .tint(.purple)
            }

        case .daily:
            HStack {
                Text("Frequency")
                Spacer()
                Text("Once daily (every 24 hours)")
                    .foregroundColor(.secondary)
            }

        case .everyXDays:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Every:")
                    Spacer()
                    Text("\(Int(frequencyHours / 24)) days")
                        .foregroundColor(.secondary)
                }
                Slider(value: $frequencyHours, in: 48...168, step: 24)
                    .tint(.purple)
            }

        case .weekly:
            HStack {
                Text("Frequency")
                Spacer()
                Text("Once weekly (every 7 days)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.purple)
                Text("Summary")
                    .font(.headline)
            }

            if !name.isEmpty {
                Text("Give \(pet.name) \(name)\(!dosage.isEmpty ? " (\(dosage))" : "") \(frequencyDescription).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Enter medicine details above")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var frequencyDescription: String {
        let hours = Int(frequencyHours)
        if hours == 1 {
            return "every hour"
        } else if hours < 24 {
            return "every \(hours) hours"
        } else if hours == 24 {
            return "once daily"
        } else if hours == 168 {
            return "once weekly"
        } else {
            let days = hours / 24
            return "every \(days) days"
        }
    }

    private func saveMedicine() {
        withAnimation {
            let medicine = MedicineEntity(context: viewContext)
            medicine.id = UUID()
            medicine.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            medicine.dosage = dosage.isEmpty ? nil : dosage.trimmingCharacters(in: .whitespacesAndNewlines)
            medicine.frequencyHours = Int32(frequencyHours)
            medicine.lastAdministered = Date()
            medicine.notificationEnabled = notificationEnabled
            medicine.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
            medicine.createdAt = Date()
            medicine.isActive = true
            medicine.pet = pet

            do {
                try viewContext.save()

                if notificationEnabled {
                    NotificationManager.shared.scheduleMedicineNotification(for: medicine)
                }

                dismiss()
            } catch {
                print("Error saving medicine: \(error)")
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

    return AddMedicineView(pet: pet)
        .environment(\.managedObjectContext, context)
}
