import Foundation
import UserNotifications
import SwiftUI

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func scheduleFoodLowNotification(for pet: PetEntity) {
        let identifier = "food-low-\(pet.id.uuidString)"

        // Remove existing notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.foodNotificationEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Food Running Low!"
        content.body = "\(pet.name)'s food bowl is running low. Time to refill!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        // Schedule immediately if food is low
        if pet.isFoodLow {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling food notification: \(error)")
                }
            }
        } else {
            // Schedule notification when food will be low (at 20%)
            let timeUntilLow = pet.foodTimeRemaining * 0.8 // 80% of remaining time
            if timeUntilLow > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilLow, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling food notification: \(error)")
                    }
                }
            }
        }
    }

    func scheduleWaterLowNotification(for pet: PetEntity) {
        let identifier = "water-low-\(pet.id.uuidString)"

        // Remove existing notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.waterNotificationEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Water Running Low!"
        content.body = "\(pet.name)'s water bowl is running low. Time to refill!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        // Schedule immediately if water is low
        if pet.isWaterLow {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling water notification: \(error)")
                }
            }
        } else {
            // Schedule notification when water will be low (at 20%)
            let timeUntilLow = pet.waterTimeRemaining * 0.8 // 80% of remaining time
            if timeUntilLow > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilLow, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling water notification: \(error)")
                    }
                }
            }
        }
    }

    func scheduleEmptyNotification(for pet: PetEntity, type: String, timeRemaining: TimeInterval) {
        guard timeRemaining > 0 else { return }

        let identifier = "\(type)-empty-\(pet.id.uuidString)"

        // Remove existing notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "\(type.capitalized) Empty!"
        content.body = "\(pet.name)'s \(type) bowl is now empty!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeRemaining, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling empty notification: \(error)")
            }
        }
    }

    func cancelNotifications(for pet: PetEntity) {
        let identifiers = [
            "food-low-\(pet.id.uuidString)",
            "water-low-\(pet.id.uuidString)",
            "food-empty-\(pet.id.uuidString)",
            "water-empty-\(pet.id.uuidString)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func rescheduleAllNotifications() {
        let context = PersistenceController.shared.container.viewContext
        let request = PetEntity.fetchRequest()

        do {
            let pets = try context.fetch(request)
            for pet in pets {
                scheduleFoodLowNotification(for: pet)
                scheduleWaterLowNotification(for: pet)
                scheduleEmptyNotification(for: pet, type: "food", timeRemaining: pet.foodTimeRemaining)
                scheduleEmptyNotification(for: pet, type: "water", timeRemaining: pet.waterTimeRemaining)
            }
        } catch {
            print("Error fetching pets for notifications: \(error)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
