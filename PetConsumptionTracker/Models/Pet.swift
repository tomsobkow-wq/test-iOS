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

    /// Maximum allowed exercise/cleaning interval is 720 hours (30 days)
    static let maxExerciseIntervalHours: Int32 = 720

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
    
    var speciesEnum: PetSpecies {
        PetSpecies(rawValue: species) ?? .other
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
    case reptile = "Reptile"
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
        case .reptile: return "lizard.fill" // System image as placeholder if no asset
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
        case .reptile: return "lizard.fill"
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
        case .fish, .turtle, .reptile: return 168 // Weekly (7 days) for cleaning
        case .other: return 48
        }
    }

    var waterGuidance: String {
        switch self {
        case .dog:
            return "Provide constant access to fresh, clean water. Clean bowls regularly to prevent bacteria buildup."
        case .cat:
            return "Cats have low thirst drive. Provide fresh water daily, consider a fountain or wide bowl. Wet food helps hydration."
        case .bird:
            return "Provide clean, fresh tap water daily in a drinker or bowl. Ensure it's not contaminated and clean dishes daily."
        case .fish:
            return "Maintain clean water with filtration and weekly partial changes (25%). Dechlorinate tap water and monitor pH/temp."
        case .rabbit:
            return "Always provide fresh, clean water in a heavy bowl (preferred) or hanging bottle. Check twice daily."
        case .hamster:
            return "Fresh water must be available at all times via a clean bottle. Clean the bottle daily."
        case .turtle:
            return "Provide a large pool of clean, dechlorinated water. Needs frequent changes (50% weekly) as they are messy eaters."
        case .other:
            return "Provide fresh, clean water daily. Research specific needs for your pet's species."
        }
    }

    var foodGuidance: String {
        switch self {
        case .dog:
            return "Feed a balanced diet appropriate for age/breed. Avoid adding water to kibble unless advised. Watch portion sizes."
        case .cat:
            return "Meat-based diet is essential. Wet food supports urinary health. Small, frequent meals are best. Limit treats <10%."
        case .bird:
            return "75% formulated pellets, 25% fresh veggies/fruits. Seeds/nuts should only be treats. Avoid avocado and chocolate."
        case .fish:
            return "Feed small amounts (what they eat in 2-3 mins) 1-2 times daily. Flakes or pellets specific to species. Do not overfeed."
        case .rabbit:
            return "80-90% unlimited Timothy hay is vital. 2 cups fresh greens daily. Limit pellets to ~1/4 cup. Avoid sugary treats."
        case .hamster:
            return "Staple diet of high-quality hamster pellets/blocks. Supplement with small amounts of veggies/fruit a few times a week."
        case .turtle:
            return "Commercial floating pellets daily. Supplement with leafy greens (3-4x week) and occasional insects/fish (1x week)."
        case .other:
            return "Research a balanced diet specific to your pet. Generally, fresh and species-appropriate food is best."
        }
    }

    var exerciseGuidance: String {
        switch self {
        case .dog:
            return "Needs 30-120 mins daily activity depending on breed. Walks, sniffing, and play are crucial for engagement."
        case .cat:
            return "Indoor cats need play to maintain weight. Use wand toys, lasers, or motorized toys to mimic hunting."
        case .bird:
            return "Needs physical/mental stimulation. Place food/water apart to encourage moving. Toys and chewables prevent boredom."
        case .fish:
            return "Swimming space is their exercise. Ensure tank is large enough with decorations for exploring."
        case .rabbit:
            return "Needs huge space to run/binky daily (min 24 sq ft). Tunnels and chew toys prevent boredom."
        case .hamster:
            return "Needs daily exercise via a solid-surface wheel (essential) and tunnels/burrowing opportunities."
        case .turtle:
            return "Needs ample swimming space and a dry basking area. Live food can stimulate hunting behavior."
        case .reptile:
            return "Research specific heating, lighting (UVB), and humidity requirements for your reptile."
        case .other:
            return "Ensure enclosure size allows for natural movement and behaviors. Provide enrichment items."
        }
    }
    
    // MARK: - Care Customization
    
    enum CareType {
        case exercise
        case habitatMaintenance // Tank/Cage cleaning
    }
    
    var careType: CareType {
        switch self {
        case .fish, .turtle, .reptile:
            return .habitatMaintenance
        default:
            return .exercise
        }
    }
    
    var careLabel: String {
        switch careType {
        case .exercise: return "Exercise"
        case .habitatMaintenance:
            switch self {
                case .fish, .turtle: return "Tank Cleaning"
                case .hamster, .rabbit, .bird, .reptile: return "Cage Cleaning"
                default: return "Habitat Cleaning"
            }
        }
    }
    
    var careIcon: String {
        switch careType {
        case .exercise: return "figure.run"
        case .habitatMaintenance: return "sparkles"
        }
    }
    
    var careActionLabel: String {
        switch careType {
        case .exercise: return "Log Exercise"
        case .habitatMaintenance: return "Cleaned"
        }
    }
    
    }
}
