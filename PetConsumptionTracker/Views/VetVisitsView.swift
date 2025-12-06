import SwiftUI

struct VetVisitsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var pet: PetEntity

    @State private var showingAddVisit = false
    @State private var selectedVisit: VetVisitEntity?
    @State private var showingDeleteConfirmation = false
    @State private var visitToDelete: VetVisitEntity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Calendar Header
                    calendarHeaderView

                    // Upcoming Visits Section
                    if !pet.upcomingVetVisits.isEmpty {
                        visitsSection(
                            title: "Upcoming",
                            icon: "calendar.badge.clock",
                            color: .teal,
                            visits: pet.upcomingVetVisits
                        )
                    }

                    // Past Visits Section
                    if !pet.pastVetVisits.isEmpty {
                        visitsSection(
                            title: "Past Visits",
                            icon: "clock.arrow.circlepath",
                            color: .gray,
                            visits: pet.pastVetVisits.reversed()
                        )
                    }

                    // Empty State
                    if pet.vetVisitsArray.isEmpty {
                        emptyStateView
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vet Visits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddVisit = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.teal)
                    }
                }
            }
            .sheet(isPresented: $showingAddVisit) {
                AddVetVisitView(pet: pet)
            }
            .sheet(item: $selectedVisit) { visit in
                VetVisitDetailView(visit: visit)
            }
            .confirmationDialog(
                "Delete Visit?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let visit = visitToDelete {
                        deleteVisit(visit)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this vet visit.")
            }
        }
    }

    private var calendarHeaderView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal.opacity(0.3), .teal.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "cross.case.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.teal)
            }

            VStack(spacing: 4) {
                Text("\(pet.name)'s Vet Calendar")
                    .font(.title2)
                    .fontWeight(.bold)

                if let nextVisit = pet.nextVetVisit {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text("Next visit: \(nextVisit.formattedDateOnly)")
                            .font(.subheadline)
                    }
                    .foregroundColor(.teal)
                } else {
                    Text("No upcoming visits scheduled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical)
    }

    private func visitsSection(title: String, icon: String, color: Color, visits: [VetVisitEntity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Spacer()
                Text("\(visits.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }

            ForEach(visits) { visit in
                visitCard(visit, isPast: visit.isCompleted || visit.isPast)
            }
        }
    }

    private func visitCard(_ visit: VetVisitEntity, isPast: Bool) -> some View {
        HStack(spacing: 16) {
            // Date badge
            VStack(spacing: 2) {
                Text(visit.visitDate.dayOfMonth)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isPast ? .gray : (visit.isToday ? .white : .teal))
                Text(visit.visitDate.shortMonth)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isPast ? .gray : (visit.isToday ? .white.opacity(0.9) : .teal))
            }
            .frame(width: 56, height: 56)
            .background(
                isPast ? Color.gray.opacity(0.15) :
                    (visit.isToday ? Color.teal : Color.teal.opacity(0.15))
            )
            .cornerRadius(12)

            // Visit details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(visit.reason)
                        .font(.headline)
                        .foregroundColor(isPast ? .secondary : .primary)

                    if visit.isToday {
                        Text("Today")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal)
                            .cornerRadius(4)
                    }
                }

                if let vetName = visit.vetName, !vetName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(vetName)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if let clinicName = visit.clinicName, !clinicName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill")
                            .font(.caption2)
                        Text(clinicName)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(visit.formattedTimeOnly)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            Menu {
                Button(action: { selectedVisit = visit }) {
                    Label("View Details", systemImage: "eye")
                }

                if !visit.isCompleted {
                    Button(action: { markVisitCompleted(visit) }) {
                        Label("Mark Completed", systemImage: "checkmark.circle")
                    }
                }

                Button(role: .destructive, action: {
                    visitToDelete = visit
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .opacity(isPast ? 0.7 : 1)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.teal.opacity(0.5))

            Text("No Vet Visits")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Schedule a vet visit to keep track of \(pet.name)'s health checkups and appointments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddVisit = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Schedule Visit")
                }
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.teal)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func markVisitCompleted(_ visit: VetVisitEntity) {
        withAnimation {
            visit.markCompleted()
            NotificationManager.shared.cancelVetVisitNotifications(for: visit)
            do {
                try viewContext.save()
            } catch {
                print("Error marking visit completed: \(error)")
            }
        }
    }

    private func deleteVisit(_ visit: VetVisitEntity) {
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
}

// MARK: - Visit Detail View

struct VetVisitDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var visit: VetVisitEntity

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Date Header
                    VStack(spacing: 8) {
                        Text(visit.visitDate.dayOfMonth)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.teal)

                        Text(visit.visitDate.formatted(date: .complete, time: .omitted))
                            .font(.headline)

                        Text(visit.formattedTimeOnly)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if visit.isCompleted {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top)

                    // Details Card
                    VStack(spacing: 0) {
                        detailRow(icon: "cross.case.fill", title: "Reason", value: visit.reason, color: .teal)
                        Divider().padding(.leading, 50)

                        if let vetName = visit.vetName, !vetName.isEmpty {
                            detailRow(icon: "person.fill", title: "Veterinarian", value: vetName, color: .blue)
                            Divider().padding(.leading, 50)
                        }

                        if let clinicName = visit.clinicName, !clinicName.isEmpty {
                            detailRow(icon: "building.2.fill", title: "Clinic", value: clinicName, color: .purple)
                            Divider().padding(.leading, 50)
                        }

                        detailRow(
                            icon: "bell.fill",
                            title: "Reminders",
                            value: visit.reminderEnabled ? "Enabled" : "Disabled",
                            color: .orange
                        )
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Notes
                    if let notes = visit.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundColor(.yellow)
                                Text("Notes")
                                    .font(.headline)
                            }
                            .padding(.horizontal)

                            Text(notes)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .padding(.horizontal)
                        }
                    }

                    // Actions
                    if !visit.isCompleted && !visit.isPast {
                        VStack(spacing: 12) {
                            Button(action: markCompleted) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Mark as Completed")
                                }
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Visit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
        .padding()
    }

    private func markCompleted() {
        withAnimation {
            visit.markCompleted()
            NotificationManager.shared.cancelVetVisitNotifications(for: visit)
            do {
                try viewContext.save()
                dismiss()
            } catch {
                print("Error: \(error)")
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let pet = PetEntity(context: context)
    pet.id = UUID()
    pet.name = "Buddy"
    pet.species = "Dog"

    let visit = VetVisitEntity(context: context)
    visit.id = UUID()
    visit.visitDate = Date().addingTimeInterval(7 * 24 * 3600)
    visit.reason = "Annual checkup"
    visit.vetName = "Dr. Smith"
    visit.clinicName = "Happy Pets Clinic"
    visit.pet = pet

    return VetVisitsView(pet: pet)
        .environment(\.managedObjectContext, context)
}
