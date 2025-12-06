import Foundation
import CoreData

@objc(PetEntity)
public class PetEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var species: String
    @NSManaged public var imageData: Data?
    @NSManaged public var useDefaultImage: Bool
    @NSManaged public var defaultImageName: String?
    @NSManaged public var foodDurationHours: Int32
    @NSManaged public var waterDurationHours: Int32
    @NSManaged public var exerciseDurationHours: Int32
    @NSManaged public var lastFoodRefill: Date?
    @NSManaged public var lastWaterRefill: Date?
    @NSManaged public var lastExercise: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var foodNotificationEnabled: Bool
    @NSManaged public var waterNotificationEnabled: Bool
    @NSManaged public var exerciseNotificationEnabled: Bool
    @NSManaged public var medicines: NSSet?
    @NSManaged public var vetVisits: NSSet?
}

extension PetEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PetEntity> {
        return NSFetchRequest<PetEntity>(entityName: "PetEntity")
    }

    // MARK: - Food Properties
    var foodRemainingPercentage: Double {
        guard let lastRefill = lastFoodRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(foodDurationHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    var foodTimeRemaining: TimeInterval {
        guard let lastRefill = lastFoodRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(foodDurationHours) * 3600
        return max(0, total - elapsed)
    }

    var isFoodLow: Bool {
        return foodRemainingPercentage < 20
    }

    func refillFood() {
        lastFoodRefill = Date()
    }

    // MARK: - Water Properties
    var waterRemainingPercentage: Double {
        guard let lastRefill = lastWaterRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(waterDurationHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    var waterTimeRemaining: TimeInterval {
        guard let lastRefill = lastWaterRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(waterDurationHours) * 3600
        return max(0, total - elapsed)
    }

    var isWaterLow: Bool {
        return waterRemainingPercentage < 20
    }

    func refillWater() {
        lastWaterRefill = Date()
    }

    // MARK: - Exercise Properties

    /// Maximum allowed exercise interval is 120 hours (5 days)
    static let maxExerciseIntervalHours: Int32 = 120

    /// Minimum allowed exercise interval is 1 hour
    static let minExerciseIntervalHours: Int32 = 1

    var exerciseRemainingPercentage: Double {
        guard let lastExerciseDate = lastExercise else { return 0 }
        let elapsed = Date().timeIntervalSince(lastExerciseDate)
        let total = Double(exerciseDurationHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    var exerciseTimeRemaining: TimeInterval {
        guard let lastExerciseDate = lastExercise else { return 0 }
        let elapsed = Date().timeIntervalSince(lastExerciseDate)
        let total = Double(exerciseDurationHours) * 3600
        return max(0, total - elapsed)
    }

    var timeSinceLastExercise: TimeInterval {
        guard let lastExerciseDate = lastExercise else { return Double.infinity }
        return Date().timeIntervalSince(lastExerciseDate)
    }

    var isExerciseNeeded: Bool {
        return exerciseRemainingPercentage < 20
    }

    var isExerciseOverdue: Bool {
        return exerciseRemainingPercentage == 0
    }

    var daysSinceLastExercise: Int {
        guard let lastExerciseDate = lastExercise else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: lastExerciseDate, to: Date())
        return components.day ?? 0
    }

    func logExercise() {
        lastExercise = Date()
    }

    // MARK: - Medicine Helpers
    var medicinesArray: [MedicineEntity] {
        let set = medicines as? Set<MedicineEntity> ?? []
        return set.sorted { $0.createdAt < $1.createdAt }
    }

    var activeMedicines: [MedicineEntity] {
        return medicinesArray.filter { $0.isActive }
    }

    var medicinesDue: [MedicineEntity] {
        return activeMedicines.filter { $0.isDue }
    }

    // MARK: - Vet Visit Helpers
    var vetVisitsArray: [VetVisitEntity] {
        let set = vetVisits as? Set<VetVisitEntity> ?? []
        return set.sorted { $0.visitDate < $1.visitDate }
    }

    var upcomingVetVisits: [VetVisitEntity] {
        return vetVisitsArray.filter { !$0.isCompleted && $0.visitDate > Date() }
    }

    var nextVetVisit: VetVisitEntity? {
        return upcomingVetVisits.first
    }

    var pastVetVisits: [VetVisitEntity] {
        return vetVisitsArray.filter { $0.isCompleted || $0.visitDate <= Date() }
    }
}

// MARK: - Medicine Entity

@objc(MedicineEntity)
public class MedicineEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var dosage: String?
    @NSManaged public var frequencyHours: Int32
    @NSManaged public var lastAdministered: Date?
    @NSManaged public var notificationEnabled: Bool
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var isActive: Bool
    @NSManaged public var pet: PetEntity
}

extension MedicineEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MedicineEntity> {
        return NSFetchRequest<MedicineEntity>(entityName: "MedicineEntity")
    }

    var timeUntilNextDose: TimeInterval {
        guard let lastDose = lastAdministered else { return 0 }
        let elapsed = Date().timeIntervalSince(lastDose)
        let total = Double(frequencyHours) * 3600
        return max(0, total - elapsed)
    }

    var timeSinceLastDose: TimeInterval {
        guard let lastDose = lastAdministered else { return Double.infinity }
        return Date().timeIntervalSince(lastDose)
    }

    var isDue: Bool {
        return timeUntilNextDose == 0 && isActive
    }

    var isOverdue: Bool {
        guard let lastDose = lastAdministered else { return true }
        let elapsed = Date().timeIntervalSince(lastDose)
        let total = Double(frequencyHours) * 3600
        return elapsed > total && isActive
    }

    var progressPercentage: Double {
        guard let lastDose = lastAdministered else { return 0 }
        let elapsed = Date().timeIntervalSince(lastDose)
        let total = Double(frequencyHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    func administer() {
        lastAdministered = Date()
    }

    var frequencyDescription: String {
        let hours = Int(frequencyHours)
        if hours == 1 {
            return "Every hour"
        } else if hours < 24 {
            return "Every \(hours) hours"
        } else if hours == 24 {
            return "Once daily"
        } else if hours == 48 {
            return "Every 2 days"
        } else if hours == 72 {
            return "Every 3 days"
        } else if hours == 168 {
            return "Weekly"
        } else {
            let days = hours / 24
            return "Every \(days) days"
        }
    }
}

// MARK: - Vet Visit Entity

@objc(VetVisitEntity)
public class VetVisitEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var visitDate: Date
    @NSManaged public var vetName: String?
    @NSManaged public var clinicName: String?
    @NSManaged public var reason: String
    @NSManaged public var notes: String?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var reminderEnabled: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var pet: PetEntity
}

extension VetVisitEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<VetVisitEntity> {
        return NSFetchRequest<VetVisitEntity>(entityName: "VetVisitEntity")
    }

    var isUpcoming: Bool {
        return !isCompleted && visitDate > Date()
    }

    var isPast: Bool {
        return visitDate <= Date()
    }

    var isToday: Bool {
        return Calendar.current.isDateInToday(visitDate)
    }

    var isTomorrow: Bool {
        return Calendar.current.isDateInTomorrow(visitDate)
    }

    var isThisWeek: Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now)!
        return visitDate > now && visitDate <= weekFromNow
    }

    var daysUntilVisit: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: visitDate)
        return max(0, components.day ?? 0)
    }

    var timeUntilVisit: TimeInterval {
        return max(0, visitDate.timeIntervalSinceNow)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: visitDate)
    }

    var formattedDateOnly: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: visitDate)
    }

    var formattedTimeOnly: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: visitDate)
    }

    func markCompleted() {
        isCompleted = true
    }
}

// MARK: - Pet Species

enum PetSpecies: String, CaseIterable {
    case dog = "Dog"
    case cat = "Cat"
    case bird = "Bird"
    case fish = "Fish"
    case rabbit = "Rabbit"
    case hamster = "Hamster"
    case turtle = "Turtle"
    case other = "Other"

    var defaultImageName: String {
        switch self {
        case .dog: return "dog_default"
        case .cat: return "cat_default"
        case .bird: return "bird_default"
        case .fish: return "fish_default"
        case .rabbit: return "rabbit_default"
        case .hamster: return "hamster_default"
        case .turtle: return "turtle_default"
        case .other: return "pet_default"
        }
    }

    var systemImageName: String {
        switch self {
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        case .bird: return "bird.fill"
        case .fish: return "fish.fill"
        case .rabbit: return "hare.fill"
        case .hamster: return "pawprint.fill"
        case .turtle: return "tortoise.fill"
        case .other: return "pawprint.fill"
        }
    }

    var needsExercise: Bool {
        switch self {
        case .fish, .turtle:
            return false
        default:
            return true
        }
    }

    var defaultExerciseHours: Int {
        switch self {
        case .dog: return 24  // Daily
        case .cat: return 48  // Every 2 days
        case .bird: return 24 // Daily
        case .rabbit: return 24 // Daily
        case .hamster: return 24 // Daily
        case .fish, .turtle: return 120 // Not really needed
        case .other: return 48
        }
    }
}
