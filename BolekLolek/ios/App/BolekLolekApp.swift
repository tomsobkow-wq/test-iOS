import SwiftUI
import UserNotifications

@main
struct BolekLolekApp: App {
    @State private var model = AppModel()
    private static let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
