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
    @State private var foodNotificationsEnabled = true
    @State private var waterNotificationsEnabled = true

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

                Section("Food Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Food lasts:")
                            Spacer()
                            Text(formatDuration(foodDurationHours))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $foodDurationHours, in: 1...72, step: 1)
                    }

                    Toggle("Low food alerts", isOn: $foodNotificationsEnabled)
                }

                Section("Water Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Water lasts:")
                            Spacer()
                            Text(formatDuration(waterDurationHours))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $waterDurationHours, in: 1...48, step: 1)
                    }

                    Toggle("Low water alerts", isOn: $waterNotificationsEnabled)
                }

                Section {
                    Text("You'll receive notifications when food or water levels drop below 20%.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    private func savePet() {
        withAnimation {
            let newPet = PetEntity(context: viewContext)
            newPet.id = UUID()
            newPet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            newPet.species = selectedSpecies.rawValue
            newPet.foodDurationHours = Int32(foodDurationHours)
            newPet.waterDurationHours = Int32(waterDurationHours)
            newPet.lastFoodRefill = Date()
            newPet.lastWaterRefill = Date()
            newPet.createdAt = Date()
            newPet.foodNotificationEnabled = foodNotificationsEnabled
            newPet.waterNotificationEnabled = waterNotificationsEnabled

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
