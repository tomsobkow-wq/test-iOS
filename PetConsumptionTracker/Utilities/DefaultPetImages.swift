import SwiftUI

struct DefaultPetImage: View {
    let species: PetSpecies
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)

            Image(systemName: species.systemImageName)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundColor(iconColor)
        }
    }

    private var backgroundColor: Color {
        switch species {
        case .dog:
            return Color.brown.opacity(0.3)
        case .cat:
            return Color.orange.opacity(0.3)
        case .bird:
            return Color.blue.opacity(0.3)
        case .fish:
            return Color.cyan.opacity(0.3)
        case .rabbit:
            return Color.gray.opacity(0.3)
        case .guineaPig:
            return Color.orange.opacity(0.3)
        case .hamster:
            return Color.yellow.opacity(0.3)
        case .mouse:
            return Color.gray.opacity(0.3)
        case .turtle:
            return Color.green.opacity(0.3)
        case .lizard:
            return Color.green.opacity(0.3)
        case .reptile:
            return Color.green.opacity(0.3)
        case .other:
            return Color.purple.opacity(0.3)
        }
    }

    private var iconColor: Color {
        switch species {
        case .dog:
            return Color.brown
        case .cat:
            return Color.orange
        case .bird:
            return Color.blue
        case .fish:
            return Color.cyan
        case .rabbit:
            return Color.gray
        case .guineaPig:
            return Color.brown
        case .hamster:
            return Color.yellow.opacity(0.8)
        case .mouse:
            return Color.gray
        case .turtle:
            return Color.green
        case .lizard:
            return Color.green
        case .reptile:
            return Color.green
        case .other:
            return Color.purple
        }
    }
}

struct PetImageView: View {
    let pet: PetEntity
    let size: CGFloat

    var body: some View {
        Group {
            if let imageData = pet.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let speciesRaw = PetSpecies(rawValue: pet.species) {
                DefaultPetImage(species: speciesRaw, size: size)
            } else {
                DefaultPetImage(species: .other, size: size)
            }
        }
    }
}

struct DefaultImagePicker: View {
    @Binding var selectedSpecies: PetSpecies

    let columns = [
        GridItem(.adaptive(minimum: 80))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or choose a default image:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(PetSpecies.allCases, id: \.rawValue) { species in
                    Button(action: {
                        selectedSpecies = species
                    }) {
                        VStack(spacing: 4) {
                            DefaultPetImage(species: species, size: 60)
                                .overlay(
                                    Circle()
                                        .stroke(selectedSpecies == species ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                            Text(species.rawValue)
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            ForEach(PetSpecies.allCases.prefix(4), id: \.rawValue) { species in
                DefaultPetImage(species: species, size: 60)
            }
        }
        HStack {
            ForEach(PetSpecies.allCases.suffix(4), id: \.rawValue) { species in
                DefaultPetImage(species: species, size: 60)
            }
        }
    }
    .padding()
}
