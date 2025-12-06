import SwiftUI

struct PetRowView: View {
    @ObservedObject var pet: PetEntity
    @StateObject private var tracker = ConsumptionTracker.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with pet info
            HStack(spacing: 16) {
                PetImageView(pet: pet, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.name)
                        .font(.headline)
                    Text(pet.species)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicators
                VStack(alignment: .trailing, spacing: 6) {
                    statusIndicator(
                        icon: "fork.knife",
                        percentage: pet.foodRemainingPercentage,
                        isLow: pet.isFoodLow,
                        color: .orange
                    )
                    statusIndicator(
                        icon: "drop.fill",
                        percentage: pet.waterRemainingPercentage,
                        isLow: pet.isWaterLow,
                        color: .blue
                    )
                    statusIndicator(
                        icon: "figure.run",
                        percentage: pet.exerciseRemainingPercentage,
                        isLow: pet.isExerciseNeeded,
                        color: .green
                    )
                }
            }
            .padding()

            // Progress bars
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ConsumptionBar(
                        percentage: pet.foodRemainingPercentage,
                        color: pet.isFoodLow ? .red : .orange,
                        label: "Food",
                        timeRemaining: pet.foodTimeRemaining,
                        icon: "fork.knife"
                    )

                    ConsumptionBar(
                        percentage: pet.waterRemainingPercentage,
                        color: pet.isWaterLow ? .red : .blue,
                        label: "Water",
                        timeRemaining: pet.waterTimeRemaining,
                        icon: "drop.fill"
                    )
                }

                ConsumptionBar(
                    percentage: pet.exerciseRemainingPercentage,
                    color: pet.isExerciseOverdue ? .red : (pet.isExerciseNeeded ? .yellow : .green),
                    label: "Exercise",
                    timeRemaining: pet.exerciseTimeRemaining,
                    icon: "figure.run"
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            // Alert badges
            if hasAlerts {
                alertBadgesView
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private var hasAlerts: Bool {
        pet.isFoodLow || pet.isWaterLow || pet.isExerciseOverdue || !pet.medicinesDue.isEmpty
    }

    private var alertBadgesView: some View {
        HStack(spacing: 8) {
            if pet.isFoodLow {
                alertBadge(icon: "fork.knife", text: "Food low", color: .red)
            }
            if pet.isWaterLow {
                alertBadge(icon: "drop.fill", text: "Water low", color: .red)
            }
            if pet.isExerciseOverdue {
                alertBadge(icon: "figure.run", text: "Exercise overdue", color: .red)
            }
            if !pet.medicinesDue.isEmpty {
                alertBadge(icon: "pills.fill", text: "\(pet.medicinesDue.count) medicine due", color: .purple)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func alertBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .cornerRadius(6)
    }

    private func statusIndicator(icon: String, percentage: Double, isLow: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isLow ? .red : color.opacity(0.7))
            Text("\(Int(percentage))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isLow ? .red : .primary)
        }
    }
}

struct ConsumptionBar: View {
    let percentage: Double
    let color: Color
    let label: String
    let timeRemaining: TimeInterval
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.caption2)
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeRemaining.formattedDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage / 100), height: 8)
                        .animation(.easeInOut, value: percentage)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
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

    return PetRowView(pet: pet)
        .padding()
        .background(Color(.systemGroupedBackground))
}
