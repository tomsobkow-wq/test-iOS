import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        DashboardView()
            .sheet(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { value in
                   // If the sheet dismisses itself (setting to false), we don't want to change the persistent state
                   // unless the user actually completed it. But here, OnboardingView sets it to true when done.
                   // The sheet won't validly dismiss via drag if we don't allow it, but we disabled interactive dismiss.
                   // When "Get Started" is clicked, hasCompletedOnboarding becomes true.
                   // So !hasCompletedOnboarding becomes false.
                   // So this get returns false, shutting the sheet.
                   // The logic holds.
                }
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
