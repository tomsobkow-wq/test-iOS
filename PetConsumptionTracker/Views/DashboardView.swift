import SwiftUI
import CoreData
import UIKit // Needed for UIImage

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PetEntity.createdAt, ascending: true)],
        animation: .default)
    private var pets: FetchedResults<PetEntity>
    
    @State private var showingAddPet = false
    @State private var showingOnboarding = false
    @State private var selectedPet: PetEntity?
    @AppStorage("isKidModeEnabled") private var isKidModeEnabled = false

    
    // Grid layout for pets
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerView
                    
                    // Priority Tasks Section (if any)
                    if hasUrgentTasks {
                        urgentTasksSection
                    }
                    
                    // My Pets Section
                    myPetsSection
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Pet Tracker")
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingAddPet) {
                AddPetView()
            }
            .navigationDestination(item: $selectedPet) { pet in
                PetDetailView(pet: pet)
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(showOnboarding: $showingOnboarding, isReview: true)
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text(isKidModeEnabled ? "My Pets" : "Pet Care")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            Spacer()
            
            // Kid Mode Toggle
            Toggle("Kid Mode", isOn: $isKidModeEnabled)
                .labelsHidden()
                .tint(.accentColor)
                .overlay(
                    HStack(spacing: 4) {
                        if isKidModeEnabled {
                            Text("Kid Mode")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .offset(y: 20)
                )

            // Simple app icon or profile placeholder
            Image(systemName: isKidModeEnabled ? "face.smiling.fill" : "pawprint.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
        }

        .padding(.top, 8)
        .overlay(alignment: .topTrailing) {
            Button(action: { showingOnboarding = true }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .offset(x: 4, y: 0) // Adjust alignment to align with icons if needed
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 18 { return "Good Afternoon" }
        return "Good Evening"
    }
    
    // MARK: - Urgent Tasks
    
    private var hasUrgentTasks: Bool {
        // Simple logic: if any pet has red status
        pets.contains { $0.isFoodLow || $0.isWaterLow || $0.isExerciseOverdue || !$0.medicinesDue.isEmpty }
    }
    
    private var urgentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needs Attention")
                .font(.headline)
                .padding(.leading, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pets) { pet in
                        if pet.isFoodLow {
                            TaskCard(icon: "fork.knife", title: "Fill Food", subtitle: pet.name, color: .orange)
                        }
                        if pet.isWaterLow {
                            TaskCard(icon: "drop.fill", title: "Fill Water", subtitle: pet.name, color: .blue)
                        }
                        if pet.isExerciseOverdue {
                            TaskCard(icon: "figure.run", title: "Walk Needed", subtitle: pet.name, color: .green)
                        }
                        ForEach(pet.medicinesDue) { medicine in
                             TaskCard(icon: "pills.fill", title: medicine.name, subtitle: pet.name, color: .purple)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - My Pets
    
    private var myPetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Pets")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddPet = true }) {
                    Label("Add Pet", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 4)
            
            if pets.isEmpty {
                 emptyPetsState
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(pets) { pet in
                        PetGridItem(pet: pet)
                            .onTapGesture {
                                selectedPet = pet
                            }
                    }
                }
            }
        }
    }
    
    private var emptyPetsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No pets added yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Add Your First Pet") {
                showingAddPet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Supporting Views

struct TaskCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 80, alignment: .leading)
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct PetGridItem: View {
    @ObservedObject var pet: PetEntity
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Image/Color
            ZStack {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(height: 100)
                
                if let data = pet.imageData, let uiImage = UIImage(data: data) {
                     Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor.opacity(0.5))
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(pet.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(pet.species)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Status Indicators
                HStack(spacing: 8) {
                    StatusDot(color: pet.isFoodLow ? .red : .green, tooltip: "Food")
                    StatusDot(color: pet.isWaterLow ? .red : .blue, tooltip: "Water")
                    StatusDot(color: pet.isExerciseOverdue ? .red : .yellow, tooltip: "Exercise")
                    if !pet.medicinesDue.isEmpty {
                        StatusDot(color: .purple, tooltip: "Meds")
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct StatusDot: View {
    let color: Color
    let tooltip: String // For future accessibility/tooltip use
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
