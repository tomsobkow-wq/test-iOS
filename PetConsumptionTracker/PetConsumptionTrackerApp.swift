import SwiftUI

@main
struct PetConsumptionTrackerApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notificationManager = NotificationManager.shared

    init() {
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(notificationManager)
        }
    }
}
