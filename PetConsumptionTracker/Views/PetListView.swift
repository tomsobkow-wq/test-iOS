import SwiftUI
import CoreData

struct PetListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var tracker = ConsumptionTracker.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PetEntity.createdAt, ascending: true)],
        animation: .default)
    private var pets: FetchedResults<PetEntity>

    @State private var showingAddPet = false
    @State private var selectedPet: PetEntity?

    var body: some View {
        NavigationStack {
            Group {
                if pets.isEmpty {
                    emptyStateView
                } else {
                    petsList
                }
            }
            .navigationTitle("My Pets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddPet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddPet) {
                AddPetView()
            }
            .navigationDestination(item: $selectedPet) { pet in
                PetDetailView(pet: pet)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "pawprint.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Pets Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add your first pet to start tracking\ntheir food and water consumption")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddPet = true }) {
                Label("Add Pet", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
        .padding()
    }

    private var petsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(pets) { pet in
                    PetRowView(pet: pet)
                        .onTapGesture {
                            selectedPet = pet
                        }
                }
            }
            .padding()
        }
        .refreshable {
            tracker.lastUpdate = Date()
        }
    }
}

#Preview {
    PetListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
