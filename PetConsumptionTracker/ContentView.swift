import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        DashboardView()
            .sheet(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { _ in } // Initial value only controlled by logic inside OnboardingView
            )) {
                OnboardingView(showOnboarding: $hasCompletedOnboarding)
                    .interactiveDismissDisabled()
            }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
