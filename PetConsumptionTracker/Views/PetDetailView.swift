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
    @State private var showingGuidanceSheet = false
    
    @State private var medicineToEdit: MedicineEntity?

    @State private var vetVisitToEdit: VetVisitEntity?
    
    @AppStorage("isKidModeEnabled") private var isKidModeEnabled = false

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
                if !isKidModeEnabled {
                    medicineSection
                }
                
                // Vet Visits Section
                if !isKidModeEnabled {
                    vetVisitsSection
                }

                // Quick Actions
                quickActionsView

                // Settings Info
                if !isKidModeEnabled {
                    settingsInfoView
                }
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
                    
                    if !isKidModeEnabled {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Pet", systemImage: "trash")
                        }
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
            AddMedicineView(pet: pet, medicineToEdit: medicineToEdit)
        }
        .sheet(isPresented: $showingVetVisitsSheet) {
            VetVisitsView(pet: pet)
        }
        .sheet(isPresented: $showingAddVetVisitSheet) {
            AddVetVisitView(pet: pet, visitToEdit: vetVisitToEdit)
        }
        .confirmationDialog("Delete Pet?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deletePet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(pet.name) and all their data.")
        }
        .sheet(isPresented: $showingGuidanceSheet) {
            if let species = PetSpecies(rawValue: pet.species) {
                PetGuidanceView(species: species)
                    .presentationDetents([.medium, .large])
            } else {
                PetGuidanceView(species: .other)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header View

    private var petHeaderView: some View {
        VStack(spacing: 12) {
            PetImageView(pet: pet, size: 120)
                .onTapGesture {
                    showingGuidanceSheet = true
                }

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
                    onRefill: { refillFood() },
                    onEdit: { showingEditSheet = true }
                )

                consumptionCard(
                    title: "Water",
                    icon: "drop.fill",
                    percentage: pet.waterRemainingPercentage,
                    timeRemaining: pet.waterTimeRemaining,
                    color: pet.isWaterLow ? .red : .blue,
                    duration: pet.waterDurationHours,
                    onRefill: { refillWater() },
                    onEdit: { showingEditSheet = true }
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Exercise Section

    private var exerciseSection: some View {
        let careLabel = pet.speciesEnum.careLabel
        let careIcon = pet.speciesEnum.careIcon
        let careColor: Color = pet.speciesEnum.careType == .habitatMaintenance ? .teal : .green
        
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: careLabel, icon: careIcon, color: careColor)

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
                                    (pet.isExerciseNeeded ? Color.yellow : careColor),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: pet.exerciseRemainingPercentage)

                        VStack(spacing: 4) {
                            Image(systemName: careIcon)
                                .font(.title2)
                                .foregroundColor(pet.isExerciseOverdue ? .red : careColor)
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
                                Text(pet.speciesEnum.careType == .habitatMaintenance ? "Last Cleaned:" : "Last Exercise:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            Text(lastExercise.timeAgoDisplay)
                                .font(.headline)
                                .foregroundColor(pet.isExerciseOverdue ? .red : .primary)
                        } else {
                            Text("No \(careLabel.lowercased()) logged yet")
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
                        Text(pet.speciesEnum.careActionLabel)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [careColor, careColor.opacity(0.8)],
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
                Button(action: { 
                    medicineToEdit = nil
                    showingAddMedicineSheet = true 
                }) {
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
                        MedicineRowView(
                            medicine: medicine,
                            onAdminister: administerMedicine,
                            onEdit: editMedicine,
                            onDelete: deleteMedicine
                        )
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

    // MARK: - Vet Visits Section

    private var vetVisitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Vet Visits", icon: "cross.case.fill", color: .teal)
                Spacer()
                Button(action: { 
                    vetVisitToEdit = nil
                    showingAddVetVisitSheet = true 
                }) {
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
            
            // Move actions here to prevent overlap and ensure right alignment
            vetVisitRowActions(visit)
        }
        .padding(.vertical, 4)
    }

    private func vetVisitRowActions(_ visit: VetVisitEntity) -> some View {
        Menu {
            Button(action: { editVetVisit(visit) }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: { deleteVetVisit(visit) }) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundColor(.teal.opacity(0.6))
        }
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
        onRefill: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray.opacity(0.6))
                }
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

                if !isKidModeEnabled {
                    quickActionButton(
                        title: "Add Medicine",
                        icon: "pills",
                        color: .purple
                    ) {
                        showingAddMedicineSheet = true
                        medicineToEdit = nil
                    }

                    quickActionButton(
                        title: "Schedule Visit",
                        icon: "calendar.badge.plus",
                        color: .teal
                    ) {
                        showingAddVetVisitSheet = true
                        vetVisitToEdit = nil
                    }
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
                settingRow(
                    icon: pet.speciesEnum.careIcon,
                    title: "\(pet.speciesEnum.careLabel) alerts",
                    value: pet.exerciseNotificationEnabled ? "On" : "Off",
                    color: pet.speciesEnum.careType == .habitatMaintenance ? .teal : .green
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
    
    private func editMedicine(_ medicine: MedicineEntity) {
        medicineToEdit = medicine
        showingAddMedicineSheet = true
    }
    
    private func editVetVisit(_ visit: VetVisitEntity) {
        vetVisitToEdit = visit
        showingAddVetVisitSheet = true
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

    private func deleteMedicine(_ medicine: MedicineEntity) {
        withAnimation {
            NotificationManager.shared.cancelMedicineNotification(for: medicine)
            viewContext.delete(medicine)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting medicine: \(error)")
            }
        }
    }
    
    private func deleteVetVisit(_ visit: VetVisitEntity) {
        withAnimation {
            NotificationManager.shared.cancelVetVisitNotifications(for: visit)
            viewContext.delete(visit)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting visit: \(error)")
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
