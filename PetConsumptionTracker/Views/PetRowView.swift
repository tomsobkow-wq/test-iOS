import SwiftUI

struct PetRowView: View {
    @ObservedObject var pet: PetEntity
    @StateObject private var tracker = ConsumptionTracker.shared

    var body: some View {
        VStack(spacing: 0) {
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

                VStack(alignment: .trailing, spacing: 8) {
                    statusIndicator(
                        icon: "fork.knife",
                        percentage: pet.foodRemainingPercentage,
                        isLow: pet.isFoodLow
                    )
                    statusIndicator(
                        icon: "drop.fill",
                        percentage: pet.waterRemainingPercentage,
                        isLow: pet.isWaterLow
                    )
                }
            }
            .padding()

            HStack(spacing: 0) {
                ConsumptionBar(
                    percentage: pet.foodRemainingPercentage,
                    color: pet.isFoodLow ? .red : .orange,
                    label: "Food",
                    timeRemaining: pet.foodTimeRemaining
                )

                Divider()
                    .frame(height: 40)

                ConsumptionBar(
                    percentage: pet.waterRemainingPercentage,
                    color: pet.isWaterLow ? .red : .blue,
                    label: "Water",
                    timeRemaining: pet.waterTimeRemaining
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private func statusIndicator(icon: String, percentage: Double, isLow: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isLow ? .red : .gray)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
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

    return PetRowView(pet: pet)
        .padding()
        .background(Color(.systemGroupedBackground))
}
