import SwiftUI

struct EditPetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var pet: PetEntity

    @State private var name: String
    @State private var selectedSpecies: PetSpecies
    @State private var selectedImage: UIImage?
    @State private var useCustomImage: Bool
    @State private var foodDurationHours: Double
    @State private var waterDurationHours: Double
    @State private var exerciseDurationHours: Double
    @State private var foodNotificationsEnabled: Bool
    @State private var waterNotificationsEnabled: Bool
    @State private var exerciseNotificationsEnabled: Bool
    
    @State private var showingAddMedicineSheet = false
    @State private var showingAddVetVisitSheet = false

    init(pet: PetEntity) {
        self.pet = pet
        _name = State(initialValue: pet.name)
        _selectedSpecies = State(initialValue: PetSpecies(rawValue: pet.species) ?? .other)
        _useCustomImage = State(initialValue: !pet.useDefaultImage)
        _foodDurationHours = State(initialValue: Double(pet.foodDurationHours))
        _waterDurationHours = State(initialValue: Double(pet.waterDurationHours))
        _exerciseDurationHours = State(initialValue: Double(pet.exerciseDurationHours))
        _foodNotificationsEnabled = State(initialValue: pet.foodNotificationEnabled)
        _waterNotificationsEnabled = State(initialValue: pet.waterNotificationEnabled)
        _exerciseNotificationsEnabled = State(initialValue: pet.exerciseNotificationEnabled)

        if let imageData = pet.imageData {
            _selectedImage = State(initialValue: UIImage(data: imageData))
        } else {
            _selectedImage = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        if useCustomImage {
                            PhotosPicker(selectedImage: $selectedImage)
                        } else {
                            DefaultPetImage(species: selectedSpecies, size: 120)
                        }

                        Toggle("Use custom photo", isOn: $useCustomImage)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Pet Information") {
                    TextField("Pet Name", text: $name)

                    Picker("Species", selection: $selectedSpecies) {
                        ForEach(PetSpecies.allCases, id: \.rawValue) { species in
                            Text(species.rawValue).tag(species)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "fork.knife")
                                .foregroundColor(.orange)
                            Text("Food lasts:")
                            Spacer()
                            Text(formatDuration(foodDurationHours))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $foodDurationHours, in: 1...72, step: 1)
                            .tint(.orange)
                    }

                    Toggle(isOn: $foodNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                            Text("Low food alerts")
                        }
                    }
                } header: {
                    Label("Food Settings", systemImage: "fork.knife")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                            Text("Water lasts:")
                            Spacer()
                            Text(formatDuration(waterDurationHours))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $waterDurationHours, in: 1...48, step: 1)
                            .tint(.blue)
                    }

                    Toggle(isOn: $waterNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.blue)
                            Text("Low water alerts")
                        }
                    }
                } header: {
                    Label("Water Settings", systemImage: "drop.fill")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: selectedSpecies.careIcon)
                                .foregroundColor(.green)
                            Text("\(selectedSpecies.careLabel) every:")
                            Spacer()
                            Text(formatExerciseDuration(Int(exerciseDurationHours)))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $exerciseDurationHours,
                            in: Double(PetEntity.minExerciseIntervalHours)...Double(PetEntity.maxExerciseIntervalHours),
                            step: 24
                        )
                        .tint(.green)

                        if exerciseDurationHours >= 720 {
                             HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Interval: 30 days")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $exerciseNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.green)
                            Text("\(selectedSpecies.careLabel) reminders")
                        }
                    }
                } header: {
                    Label("\(selectedSpecies.careLabel) Settings", systemImage: selectedSpecies.careIcon)
                } footer: {
                    if selectedSpecies.careType == .habitatMaintenance {
                        Text("Regular cleaning is vital for the health of tank and cage pets.")
                    } else {
                        Text("Pets need regular activity for optimal health.")
                    }
                }
                
                Section("Health & Wellness") {
                    Button(action: { showingAddMedicineSheet = true }) {
                        Label("Add Medicine", systemImage: "pills.fill")
                            .foregroundColor(.purple)
                    }
                    
                    Button(action: { showingAddVetVisitSheet = true }) {
                        Label("Schedule Vet Visit", systemImage: "cross.case.fill")
                            .foregroundColor(.teal)
                    }
                }
            }
            .navigationTitle("Edit Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddMedicineSheet) {
                AddMedicineView(pet: pet)
            }
            .sheet(isPresented: $showingAddVetVisitSheet) {
                AddVetVisitView(pet: pet)
            }
        }
    }

    private func formatDuration(_ hours: Double) -> String {
        let h = Int(hours)
        if h >= 24 {
            let days = h / 24
            let remainingHours = h % 24
            if remainingHours == 0 {
                return "\(days) day\(days > 1 ? "s" : "")"
            }
            return "\(days)d \(remainingHours)h"
        }
        return "\(h) hour\(h > 1 ? "s" : "")"
    }

    private func formatExerciseDuration(_ hours: Int) -> String {
        if hours == 1 {
            return "1 hour"
        } else if hours < 24 {
            return "\(hours) hours"
        } else if hours == 24 {
            return "1 day"
        } else if hours == 48 {
            return "2 days"
        } else if hours == 72 {
            return "3 days"
        } else if hours == 96 {
            return "4 days"
        } else if hours >= 720 {
            return "30 days (max)"
        } else {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours == 0 {
                return "\(days) days"
            }
            return "\(days)d \(remainingHours)h"
        }
    }

    private func saveChanges() {
        pet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.species = selectedSpecies.rawValue
        pet.foodDurationHours = Int32(foodDurationHours)
        pet.waterDurationHours = Int32(waterDurationHours)
        pet.exerciseDurationHours = Int32(min(exerciseDurationHours, Double(PetEntity.maxExerciseIntervalHours)))
        pet.foodNotificationEnabled = foodNotificationsEnabled
        pet.waterNotificationEnabled = waterNotificationsEnabled
        pet.exerciseNotificationEnabled = exerciseNotificationsEnabled

        if useCustomImage, let image = selectedImage {
            pet.imageData = image.jpegData(compressionQuality: 0.8)
            pet.useDefaultImage = false
        } else {
            pet.imageData = nil
            pet.useDefaultImage = true
            pet.defaultImageName = selectedSpecies.defaultImageName
        }

        do {
            try viewContext.save()

            // Reschedule notifications
            NotificationManager.shared.cancelNotifications(for: pet)
            NotificationManager.shared.scheduleFoodLowNotification(for: pet)
            NotificationManager.shared.scheduleWaterLowNotification(for: pet)
            NotificationManager.shared.scheduleExerciseNotification(for: pet)
            NotificationManager.shared.scheduleExerciseOverdueNotification(for: pet)
            NotificationManager.shared.scheduleEmptyNotification(for: pet, type: "food", timeRemaining: pet.foodTimeRemaining)
            NotificationManager.shared.scheduleEmptyNotification(for: pet, type: "water", timeRemaining: pet.waterTimeRemaining)

            dismiss()
        } catch {
            let nsError = error as NSError
            print("Error saving pet: \(nsError), \(nsError.userInfo)")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let pet = PetEntity(context: context)
    pet.id = UUID()
    pet.name = "Buddy"
    pet.species = "Dog"
    pet.foodDurationHours = 24
    pet.waterDurationHours = 12
    pet.exerciseDurationHours = 24
    pet.createdAt = Date()
    pet.useDefaultImage = true
    pet.foodNotificationEnabled = true
    pet.waterNotificationEnabled = true
    pet.exerciseNotificationEnabled = true

    return EditPetView(pet: pet)
        .environment(\.managedObjectContext, context)
}
