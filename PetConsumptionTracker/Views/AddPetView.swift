import SwiftUI

struct AddPetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedSpecies: PetSpecies = .dog
    @State private var selectedImage: UIImage?
    @State private var useCustomImage = false
    @State private var foodDurationHours: Double = 24
    @State private var waterDurationHours: Double = 12
    @State private var exerciseDurationHours: Double = 24
    @State private var foodNotificationsEnabled = true
    @State private var waterNotificationsEnabled = true
    @State private var exerciseNotificationsEnabled = true

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
                    .onChange(of: selectedSpecies) { _, newSpecies in
                        exerciseDurationHours = Double(newSpecies.defaultExerciseHours)
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
                            Image(systemName: "figure.run")
                                .foregroundColor(.green)
                            Text("Exercise every:")
                            Spacer()
                            Text(formatExerciseDuration(Int(exerciseDurationHours)))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $exerciseDurationHours,
                            in: Double(PetEntity.minExerciseIntervalHours)...Double(PetEntity.maxExerciseIntervalHours),
                            step: selectedSpecies.needsExercise ? 1 : 24
                        )
                        .tint(.green)

                        if exerciseDurationHours >= 120 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Maximum interval: 5 days")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $exerciseNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.green)
                            Text("Exercise reminders")
                        }
                    }

                    if !selectedSpecies.needsExercise {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("\(selectedSpecies.rawValue)s typically don't require regular exercise sessions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Exercise Settings", systemImage: "figure.run")
                } footer: {
                    Text("Pets must exercise at least once every 5 days for optimal health.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("How notifications work")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("You'll receive notifications when food, water, or exercise levels drop below 20%, giving you time to take action.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePet()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
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
        } else if hours >= 120 {
            return "5 days (max)"
        } else {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours == 0 {
                return "\(days) days"
            }
            return "\(days)d \(remainingHours)h"
        }
    }

    private func savePet() {
        withAnimation {
            let newPet = PetEntity(context: viewContext)
            newPet.id = UUID()
            newPet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            newPet.species = selectedSpecies.rawValue
            newPet.foodDurationHours = Int32(foodDurationHours)
            newPet.waterDurationHours = Int32(waterDurationHours)
            newPet.exerciseDurationHours = Int32(min(exerciseDurationHours, Double(PetEntity.maxExerciseIntervalHours)))
            newPet.lastFoodRefill = Date()
            newPet.lastWaterRefill = Date()
            newPet.lastExercise = Date()
            newPet.createdAt = Date()
            newPet.foodNotificationEnabled = foodNotificationsEnabled
            newPet.waterNotificationEnabled = waterNotificationsEnabled
            newPet.exerciseNotificationEnabled = exerciseNotificationsEnabled

            if useCustomImage, let image = selectedImage {
                newPet.imageData = image.jpegData(compressionQuality: 0.8)
                newPet.useDefaultImage = false
            } else {
                newPet.useDefaultImage = true
                newPet.defaultImageName = selectedSpecies.defaultImageName
            }

            do {
                try viewContext.save()

                // Schedule notifications
                NotificationManager.shared.scheduleFoodLowNotification(for: newPet)
                NotificationManager.shared.scheduleWaterLowNotification(for: newPet)
                NotificationManager.shared.scheduleExerciseNotification(for: newPet)
                NotificationManager.shared.scheduleExerciseOverdueNotification(for: newPet)
                NotificationManager.shared.scheduleEmptyNotification(for: newPet, type: "food", timeRemaining: newPet.foodTimeRemaining)
                NotificationManager.shared.scheduleEmptyNotification(for: newPet, type: "water", timeRemaining: newPet.waterTimeRemaining)

                dismiss()
            } catch {
                let nsError = error as NSError
                print("Error saving pet: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

#Preview {
    AddPetView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
