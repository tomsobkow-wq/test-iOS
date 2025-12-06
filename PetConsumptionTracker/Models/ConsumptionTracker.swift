import Foundation
import SwiftUI
import Combine

class ConsumptionTracker: ObservableObject {
    static let shared = ConsumptionTracker()

    private var timer: Timer?
    @Published var lastUpdate = Date()

    private init() {
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.lastUpdate = Date()
            self?.checkAndScheduleNotifications()
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func checkAndScheduleNotifications() {
        let context = PersistenceController.shared.container.viewContext
        let request = PetEntity.fetchRequest()

        do {
            let pets = try context.fetch(request)
            for pet in pets {
                if pet.foodNotificationEnabled && pet.isFoodLow {
                    NotificationManager.shared.scheduleFoodLowNotification(for: pet)
                }
                if pet.waterNotificationEnabled && pet.isWaterLow {
                    NotificationManager.shared.scheduleWaterLowNotification(for: pet)
                }
            }
        } catch {
            print("Error fetching pets: \(error)")
        }
    }

    func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return "Empty"
        }

        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

extension TimeInterval {
    var formattedDuration: String {
        ConsumptionTracker.shared.formatTimeRemaining(self)
    }
}
