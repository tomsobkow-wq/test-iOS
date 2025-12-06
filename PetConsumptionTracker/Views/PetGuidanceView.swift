
import SwiftUI

struct PetGuidanceView: View {
    @Environment(\.dismiss) private var dismiss
    let species: PetSpecies

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        DefaultPetImage(species: species, size: 80)
                        Text("Care Guidance for \(species.rawValue)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Guidance Sections
                    VStack(spacing: 16) {
                        GuidanceCard(
                            title: "Food",
                            icon: "fork.knife",
                            color: .pink, // Matching Daily Care color in PetDetailView
                            content: species.foodGuidance
                        )

                        GuidanceCard(
                            title: "Water",
                            icon: "drop.fill",
                            color: .blue, // Matching Daily Care color in PetDetailView
                            content: species.waterGuidance
                        )

                        GuidanceCard(
                            title: "Exercise",
                            icon: "figure.run",
                            color: .green, // Matching Exercise color in PetDetailView
                            content: species.exerciseGuidance
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GuidanceCard: View {
    let title: String
    let icon: String
    let color: Color
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true) // Ensure text wraps properly
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    PetGuidanceView(species: .dog)
}
