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

    // MARK: - Food Notifications

    func scheduleFoodLowNotification(for pet: PetEntity) {
        let identifier = "food-low-\(pet.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.foodNotificationEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Food Running Low!"
        content.body = "\(pet.name)'s food bowl is running low. Time to refill!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        if pet.isFoodLow {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling food notification: \(error)") }
            }
        } else {
            let timeUntilLow = pet.foodTimeRemaining * 0.8
            if timeUntilLow > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilLow, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error { print("Error scheduling food notification: \(error)") }
                }
            }
        }
    }

    // MARK: - Water Notifications

    func scheduleWaterLowNotification(for pet: PetEntity) {
        let identifier = "water-low-\(pet.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.waterNotificationEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Water Running Low!"
        content.body = "\(pet.name)'s water bowl is running low. Time to refill!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        if pet.isWaterLow {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling water notification: \(error)") }
            }
        } else {
            let timeUntilLow = pet.waterTimeRemaining * 0.8
            if timeUntilLow > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilLow, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error { print("Error scheduling water notification: \(error)") }
                }
            }
        }
    }

    // MARK: - Exercise Notifications

    func scheduleExerciseNotification(for pet: PetEntity) {
        let identifier = "exercise-needed-\(pet.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.exerciseNotificationEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Exercise Time!"
        content.body = "\(pet.name) needs some exercise. Time for a walk or play session!"
        content.sound = .default
        content.categoryIdentifier = "PET_EXERCISE"

        if pet.isExerciseNeeded {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling exercise notification: \(error)") }
            }
        } else {
            let timeUntilNeeded = pet.exerciseTimeRemaining * 0.8
            if timeUntilNeeded > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeUntilNeeded, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error { print("Error scheduling exercise notification: \(error)") }
                }
            }
        }
    }

    func scheduleExerciseOverdueNotification(for pet: PetEntity) {
        let identifier = "exercise-overdue-\(pet.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard pet.exerciseNotificationEnabled else { return }
        guard pet.exerciseTimeRemaining > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Exercise Overdue!"
        content.body = "\(pet.name) hasn't exercised in a while. Please take them out!"
        content.sound = .default
        content.categoryIdentifier = "PET_EXERCISE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error scheduling exercise overdue notification: \(error)") }
        }
    }

    // MARK: - Medicine Notifications

    func scheduleMedicineNotification(for medicine: MedicineEntity) {
        let identifier = "medicine-due-\(medicine.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard medicine.notificationEnabled && medicine.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "Medicine Time!"
        if let dosage = medicine.dosage, !dosage.isEmpty {
            content.body = "Time to give \(medicine.pet.name) their \(medicine.name) (\(dosage))"
        } else {
            content.body = "Time to give \(medicine.pet.name) their \(medicine.name)"
        }
        content.sound = .default
        content.categoryIdentifier = "PET_MEDICINE"

        if medicine.isDue {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling medicine notification: \(error)") }
            }
        } else if medicine.timeUntilNextDose > 0 {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: medicine.timeUntilNextDose, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling medicine notification: \(error)") }
            }
        }
    }

    func cancelMedicineNotification(for medicine: MedicineEntity) {
        let identifier = "medicine-due-\(medicine.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Vet Visit Notifications

    func scheduleVetVisitNotifications(for visit: VetVisitEntity) {
        cancelVetVisitNotifications(for: visit)

        guard visit.reminderEnabled && !visit.isCompleted else { return }
        guard visit.timeUntilVisit > 0 else { return }

        let petName = visit.pet.name

        // Schedule 1 day before reminder
        if visit.timeUntilVisit > 24 * 3600 {
            let oneDayBefore = visit.timeUntilVisit - (24 * 3600)
            let content = UNMutableNotificationContent()
            content.title = "Vet Visit Tomorrow"
            content.body = "\(petName) has a vet appointment tomorrow at \(visit.formattedTimeOnly)"
            if let clinicName = visit.clinicName, !clinicName.isEmpty {
                content.body += " at \(clinicName)"
            }
            content.sound = .default
            content.categoryIdentifier = "PET_VET"

            let identifier = "vet-1day-\(visit.id.uuidString)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: oneDayBefore, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling vet notification: \(error)") }
            }
        }

        // Schedule 1 hour before reminder
        if visit.timeUntilVisit > 3600 {
            let oneHourBefore = visit.timeUntilVisit - 3600
            let content = UNMutableNotificationContent()
            content.title = "Vet Visit in 1 Hour"
            content.body = "\(petName)'s vet appointment is in 1 hour"
            if let clinicName = visit.clinicName, !clinicName.isEmpty {
                content.body += " at \(clinicName)"
            }
            content.sound = .default
            content.categoryIdentifier = "PET_VET"

            let identifier = "vet-1hour-\(visit.id.uuidString)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: oneHourBefore, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Error scheduling vet notification: \(error)") }
            }
        }

        // Schedule at appointment time
        let content = UNMutableNotificationContent()
        content.title = "Vet Visit Now"
        content.body = "\(petName)'s vet appointment is now!"
        content.sound = .default
        content.categoryIdentifier = "PET_VET"

        let identifier = "vet-now-\(visit.id.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: visit.timeUntilVisit, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error scheduling vet notification: \(error)") }
        }
    }

    func cancelVetVisitNotifications(for visit: VetVisitEntity) {
        let identifiers = [
            "vet-1day-\(visit.id.uuidString)",
            "vet-1hour-\(visit.id.uuidString)",
            "vet-now-\(visit.id.uuidString)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Empty Notifications

    func scheduleEmptyNotification(for pet: PetEntity, type: String, timeRemaining: TimeInterval) {
        guard timeRemaining > 0 else { return }

        let identifier = "\(type)-empty-\(pet.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "\(type.capitalized) Empty!"
        content.body = "\(pet.name)'s \(type) bowl is now empty!"
        content.sound = .default
        content.categoryIdentifier = "PET_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error scheduling empty notification: \(error)") }
        }
    }

    // MARK: - Cancel All for Pet

    func cancelNotifications(for pet: PetEntity) {
        var identifiers = [
            "food-low-\(pet.id.uuidString)",
            "water-low-\(pet.id.uuidString)",
            "food-empty-\(pet.id.uuidString)",
            "water-empty-\(pet.id.uuidString)",
            "exercise-needed-\(pet.id.uuidString)",
            "exercise-overdue-\(pet.id.uuidString)"
        ]

        // Cancel medicine notifications
        for medicine in pet.medicinesArray {
            identifiers.append("medicine-due-\(medicine.id.uuidString)")
        }

        // Cancel vet visit notifications
        for visit in pet.vetVisitsArray {
            identifiers.append("vet-1day-\(visit.id.uuidString)")
            identifiers.append("vet-1hour-\(visit.id.uuidString)")
            identifiers.append("vet-now-\(visit.id.uuidString)")
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Reschedule All

    func rescheduleAllNotifications() {
        let context = PersistenceController.shared.container.viewContext
        let request = PetEntity.fetchRequest()

        do {
            let pets = try context.fetch(request)
            for pet in pets {
                scheduleFoodLowNotification(for: pet)
                scheduleWaterLowNotification(for: pet)
                scheduleExerciseNotification(for: pet)
                scheduleExerciseOverdueNotification(for: pet)
                scheduleEmptyNotification(for: pet, type: "food", timeRemaining: pet.foodTimeRemaining)
                scheduleEmptyNotification(for: pet, type: "water", timeRemaining: pet.waterTimeRemaining)

                // Medicine notifications
                for medicine in pet.activeMedicines {
                    scheduleMedicineNotification(for: medicine)
                }

                // Vet visit notifications
                for visit in pet.upcomingVetVisits {
                    scheduleVetVisitNotifications(for: visit)
                }
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
