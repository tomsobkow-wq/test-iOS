import SwiftUI

struct PetDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var pet: PetEntity
    @StateObject private var tracker = ConsumptionTracker.shared

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Pet Image and Info
                petHeaderView

                // Consumption Cards
                HStack(spacing: 16) {
                    consumptionCard(
                        title: "Food",
                        icon: "fork.knife",
                        percentage: pet.foodRemainingPercentage,
                        timeRemaining: pet.foodTimeRemaining,
                        color: pet.isFoodLow ? .red : .orange,
                        duration: pet.foodDurationHours,
                        onRefill: {
                            refillFood()
                        }
                    )

                    consumptionCard(
                        title: "Water",
                        icon: "drop.fill",
                        percentage: pet.waterRemainingPercentage,
                        timeRemaining: pet.waterTimeRemaining,
                        color: pet.isWaterLow ? .red : .blue,
                        duration: pet.waterDurationHours,
                        onRefill: {
                            refillWater()
                        }
                    )
                }
                .padding(.horizontal)

                // Quick Actions
                quickActionsView

                // Settings Info
                settingsInfoView
            }
            .padding(.vertical)
        }
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Pet", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete Pet", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPetView(pet: pet)
        }
        .confirmationDialog("Delete Pet?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deletePet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(pet.name) and all their data.")
        }
    }

    private var petHeaderView: some View {
        VStack(spacing: 12) {
            PetImageView(pet: pet, size: 120)

            VStack(spacing: 4) {
                Text(pet.name)
                    .font(.title)
                    .fontWeight(.bold)
                Text(pet.species)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func consumptionCard(
        title: String,
        icon: String,
        percentage: Double,
        timeRemaining: TimeInterval,
        color: Color,
        duration: Int32,
        onRefill: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            // Circular Progress
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: CGFloat(percentage / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: percentage)

                VStack(spacing: 2) {
                    Text("\(Int(percentage))%")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(timeRemaining.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            Text("Lasts \(duration)h")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onRefill) {
                Text("Refill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(color)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Refill Both",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                ) {
                    refillFood()
                    refillWater()
                }

                quickActionButton(
                    title: "View History",
                    icon: "clock.arrow.circlepath",
                    color: .purple
                ) {
                    // Future feature
                }
            }
            .padding(.horizontal)
        }
    }

    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var settingsInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notification Settings")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                settingRow(
                    icon: "fork.knife",
                    title: "Food alerts",
                    value: pet.foodNotificationEnabled ? "On" : "Off",
                    color: .orange
                )
                Divider()
                    .padding(.leading, 50)
                settingRow(
                    icon: "drop.fill",
                    title: "Water alerts",
                    value: pet.waterNotificationEnabled ? "On" : "Off",
                    color: .blue
                )
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    private func settingRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func refillFood() {
        withAnimation {
            pet.refillFood()
            saveAndReschedule()
        }
    }

    private func refillWater() {
        withAnimation {
            pet.refillWater()
            saveAndReschedule()
        }
    }

    private func saveAndReschedule() {
        do {
            try viewContext.save()

            // Reschedule notifications
            NotificationManager.shared.cancelNotifications(for: pet)
            NotificationManager.shared.scheduleFoodLowNotification(for: pet)
            NotificationManager.shared.scheduleWaterLowNotification(for: pet)
            NotificationManager.shared.scheduleEmptyNotification(for: pet, type: "food", timeRemaining: pet.foodTimeRemaining)
            NotificationManager.shared.scheduleEmptyNotification(for: pet, type: "water", timeRemaining: pet.waterTimeRemaining)
        } catch {
            print("Error saving: \(error)")
        }
    }

    private func deletePet() {
        NotificationManager.shared.cancelNotifications(for: pet)
        viewContext.delete(pet)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error deleting pet: \(error)")
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
    pet.lastFoodRefill = Date().addingTimeInterval(-3600 * 18)
    pet.lastWaterRefill = Date().addingTimeInterval(-3600 * 8)
    pet.createdAt = Date()
    pet.useDefaultImage = true
    pet.foodNotificationEnabled = true
    pet.waterNotificationEnabled = true

    return NavigationStack {
        PetDetailView(pet: pet)
    }
    .environment(\.managedObjectContext, context)
}
