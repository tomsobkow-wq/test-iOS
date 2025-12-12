import SwiftUI

struct MedicineRowView: View {
    @ObservedObject var medicine: MedicineEntity
    var onAdminister: (MedicineEntity) -> Void

    var body: some View {
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
                Button(action: { 
                    print("Button tapped for \(medicine.name)")
                    onAdminister(medicine) 
                }) {
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
}
