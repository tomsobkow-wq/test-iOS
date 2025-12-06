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
    @State private var foodNotificationsEnabled: Bool
    @State private var waterNotificationsEnabled: Bool

    init(pet: PetEntity) {
        self.pet = pet
        _name = State(initialValue: pet.name)
        _selectedSpecies = State(initialValue: PetSpecies(rawValue: pet.species) ?? .other)
        _useCustomImage = State(initialValue: !pet.useDefaultImage)
        _foodDurationHours = State(initialValue: Double(pet.foodDurationHours))
        _waterDurationHours = State(initialValue: Double(pet.waterDurationHours))
        _foodNotificationsEnabled = State(initialValue: pet.foodNotificationEnabled)
        _waterNotificationsEnabled = State(initialValue: pet.waterNotificationEnabled)

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

    private func saveChanges() {
        pet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.species = selectedSpecies.rawValue
        pet.foodDurationHours = Int32(foodDurationHours)
        pet.waterDurationHours = Int32(waterDurationHours)
        pet.foodNotificationEnabled = foodNotificationsEnabled
        pet.waterNotificationEnabled = waterNotificationsEnabled

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
    pet.createdAt = Date()
    pet.useDefaultImage = true
    pet.foodNotificationEnabled = true
    pet.waterNotificationEnabled = true

    return EditPetView(pet: pet)
        .environment(\.managedObjectContext, context)
}
