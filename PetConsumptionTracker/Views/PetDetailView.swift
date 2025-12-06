import SwiftUI

struct PetDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var pet: PetEntity
    @StateObject private var tracker = ConsumptionTracker.shared

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingMedicineSheet = false
    @State private var showingAddMedicineSheet = false
    @State private var showingVetVisitsSheet = false
    @State private var showingAddVetVisitSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Pet Image and Info
                petHeaderView

                // Daily Care Section
                dailyCareSection

                // Exercise Section
                exerciseSection

                // Medicine Section
                medicineSection

                // Vet Visits Section
                vetVisitsSection

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
        .sheet(isPresented: $showingAddMedicineSheet) {
            AddMedicineView(pet: pet)
        }
        .sheet(isPresented: $showingVetVisitsSheet) {
            VetVisitsView(pet: pet)
        }
        .sheet(isPresented: $showingAddVetVisitSheet) {
            AddVetVisitView(pet: pet)
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

    // MARK: - Header View

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

    // MARK: - Daily Care Section

    private var dailyCareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Daily Care", icon: "heart.fill", color: .pink)

            HStack(spacing: 12) {
                consumptionCard(
                    title: "Food",
                    icon: "fork.knife",
                    percentage: pet.foodRemainingPercentage,
                    timeRemaining: pet.foodTimeRemaining,
                    color: pet.isFoodLow ? .red : .orange,
                    duration: pet.foodDurationHours,
                    onRefill: { refillFood() }
                )

                consumptionCard(
                    title: "Water",
                    icon: "drop.fill",
                    percentage: pet.waterRemainingPercentage,
                    timeRemaining: pet.waterTimeRemaining,
                    color: pet.isWaterLow ? .red : .blue,
                    duration: pet.waterDurationHours,
                    onRefill: { refillWater() }
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Exercise Section

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Exercise", icon: "figure.run", color: .green)

            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    // Exercise progress circle
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 12)

                        Circle()
                            .trim(from: 0, to: CGFloat(pet.exerciseRemainingPercentage / 100))
                            .stroke(
                                pet.isExerciseOverdue ? Color.red :
                                    (pet.isExerciseNeeded ? Color.yellow : Color.green),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: pet.exerciseRemainingPercentage)

                        VStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .font(.title2)
                                .foregroundColor(pet.isExerciseOverdue ? .red : .green)
                            if pet.isExerciseOverdue {
                                Text("Overdue!")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            } else {
                                Text("\(Int(pet.exerciseRemainingPercentage))%")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .frame(width: 100, height: 100)

                    // Exercise info
                    VStack(alignment: .leading, spacing: 8) {
                        if let lastExercise = pet.lastExercise {
                            HStack {
                                Text("Last Exercise:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            Text(lastExercise.timeAgoDisplay)
                                .font(.headline)
                                .foregroundColor(pet.isExerciseOverdue ? .red : .primary)
                        } else {
                            Text("No exercise logged yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Goal:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Every \(formatExerciseDuration(Int(pet.exerciseDurationHours)))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if pet.exerciseTimeRemaining > 0 {
                            HStack {
                                Text("Next in:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(pet.exerciseTimeRemaining.formattedDuration)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: logExercise) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Exercise")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    // MARK: - Medicine Section

    private var medicineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Medicine", icon: "pills.fill", color: .purple)
                Spacer()
                Button(action: { showingAddMedicineSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
                .padding(.trailing)
            }

            VStack(spacing: 8) {
                if pet.activeMedicines.isEmpty {
                    emptyStateCard(
                        icon: "pills",
                        title: "No Medications",
                        subtitle: "Tap + to add medicine",
                        color: .purple
                    )
                } else {
                    ForEach(pet.activeMedicines.prefix(3)) { medicine in
                        medicineRow(medicine)
                    }

                    if pet.activeMedicines.count > 3 {
                        Button(action: { showingMedicineSheet = true }) {
                            Text("View all \(pet.activeMedicines.count) medications")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    private func medicineRow(_ medicine: MedicineEntity) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(medicine.isDue ? Color.red.opacity(0.2) : Color.purple.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: medicine.isDue ? "exclamationmark.circle.fill" : "pills.fill")
                    .foregroundColor(medicine.isDue ? .red : .purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(medicine.name)
                    .font(.headline)
                if let dosage = medicine.dosage, !dosage.isEmpty {
                    Text(dosage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(medicine.frequencyDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if medicine.isDue {
                Button(action: { administerMedicine(medicine) }) {
                    Text("Give")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .cornerRadius(8)
                }
            } else {
                VStack(alignment: .trailing) {
                    Text("Next in")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(medicine.timeUntilNextDose.formattedDuration)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Vet Visits Section

    private var vetVisitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Vet Visits", icon: "cross.case.fill", color: .teal)
                Spacer()
                Button(action: { showingAddVetVisitSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.teal)
                }
                .padding(.trailing)
            }

            VStack(spacing: 8) {
                if pet.upcomingVetVisits.isEmpty {
                    emptyStateCard(
                        icon: "calendar.badge.plus",
                        title: "No Upcoming Visits",
                        subtitle: "Tap + to schedule a vet visit",
                        color: .teal
                    )
                } else {
                    ForEach(pet.upcomingVetVisits.prefix(2)) { visit in
                        vetVisitRow(visit)
                    }

                    Button(action: { showingVetVisitsSheet = true }) {
                        HStack {
                            Image(systemName: "calendar")
                            Text("View All Visits")
                        }
                        .font(.subheadline)
                        .foregroundColor(.teal)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
    }

    private func vetVisitRow(_ visit: VetVisitEntity) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(visit.visitDate.dayOfMonth)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(visit.isToday ? .white : .teal)
                Text(visit.visitDate.shortMonth)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(visit.isToday ? .white.opacity(0.9) : .teal)
            }
            .frame(width: 50, height: 50)
            .background(visit.isToday ? Color.teal : Color.teal.opacity(0.15))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(visit.reason)
                    .font(.headline)
                if let vetName = visit.vetName, !vetName.isEmpty {
                    Text(vetName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(visit.formattedTimeOnly)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if visit.isToday {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.teal)
                    .cornerRadius(6)
            } else if visit.isTomorrow {
                Text("Tomorrow")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.teal)
            } else {
                Text("In \(visit.daysUntilVisit) days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
    }

    private func emptyStateCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color.opacity(0.5))
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
            sectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .yellow)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Refill All",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                ) {
                    refillFood()
                    refillWater()
                    logExercise()
                }

                quickActionButton(
                    title: "Add Medicine",
                    icon: "pills",
                    color: .purple
                ) {
                    showingAddMedicineSheet = true
                }

                quickActionButton(
                    title: "Schedule Visit",
                    icon: "calendar.badge.plus",
                    color: .teal
                ) {
                    showingAddVetVisitSheet = true
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
                    .multilineTextAlignment(.center)
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
            sectionHeader(title: "Notifications", icon: "bell.fill", color: .orange)

            VStack(spacing: 0) {
                settingRow(icon: "fork.knife", title: "Food alerts", value: pet.foodNotificationEnabled ? "On" : "Off", color: .orange)
                Divider().padding(.leading, 50)
                settingRow(icon: "drop.fill", title: "Water alerts", value: pet.waterNotificationEnabled ? "On" : "Off", color: .blue)
                Divider().padding(.leading, 50)
                settingRow(icon: "figure.run", title: "Exercise alerts", value: pet.exerciseNotificationEnabled ? "On" : "Off", color: .green)
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

    // MARK: - Actions

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

    private func logExercise() {
        withAnimation {
            pet.logExercise()
            saveAndReschedule()
        }
    }

    private func administerMedicine(_ medicine: MedicineEntity) {
        withAnimation {
            medicine.administer()
            do {
                try viewContext.save()
                NotificationManager.shared.scheduleMedicineNotification(for: medicine)
            } catch {
                print("Error saving: \(error)")
            }
        }
    }

    private func saveAndReschedule() {
        do {
            try viewContext.save()
            NotificationManager.shared.cancelNotifications(for: pet)
            NotificationManager.shared.scheduleFoodLowNotification(for: pet)
            NotificationManager.shared.scheduleWaterLowNotification(for: pet)
            NotificationManager.shared.scheduleExerciseNotification(for: pet)
            NotificationManager.shared.scheduleExerciseOverdueNotification(for: pet)
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

    private func formatExerciseDuration(_ hours: Int) -> String {
        if hours == 1 {
            return "hour"
        } else if hours < 24 {
            return "\(hours) hours"
        } else if hours == 24 {
            return "day"
        } else {
            let days = hours / 24
            return "\(days) days"
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var dayOfMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    var shortMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: self)
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
    pet.lastFoodRefill = Date().addingTimeInterval(-3600 * 18)
    pet.lastWaterRefill = Date().addingTimeInterval(-3600 * 8)
    pet.lastExercise = Date().addingTimeInterval(-3600 * 20)
    pet.createdAt = Date()
    pet.useDefaultImage = true
    pet.foodNotificationEnabled = true
    pet.waterNotificationEnabled = true
    pet.exerciseNotificationEnabled = true

    return NavigationStack {
        PetDetailView(pet: pet)
    }
    .environment(\.managedObjectContext, context)
}
