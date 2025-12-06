import SwiftUI

struct ContentView: View {
    var body: some View {
        PetListView()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
