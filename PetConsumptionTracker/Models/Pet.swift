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
    @NSManaged public var lastFoodRefill: Date?
    @NSManaged public var lastWaterRefill: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var foodNotificationEnabled: Bool
    @NSManaged public var waterNotificationEnabled: Bool
}

extension PetEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PetEntity> {
        return NSFetchRequest<PetEntity>(entityName: "PetEntity")
    }

    var foodRemainingPercentage: Double {
        guard let lastRefill = lastFoodRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(foodDurationHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    var waterRemainingPercentage: Double {
        guard let lastRefill = lastWaterRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(waterDurationHours) * 3600
        let remaining = max(0, 1 - (elapsed / total))
        return remaining * 100
    }

    var foodTimeRemaining: TimeInterval {
        guard let lastRefill = lastFoodRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(foodDurationHours) * 3600
        return max(0, total - elapsed)
    }

    var waterTimeRemaining: TimeInterval {
        guard let lastRefill = lastWaterRefill else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRefill)
        let total = Double(waterDurationHours) * 3600
        return max(0, total - elapsed)
    }

    var isFoodLow: Bool {
        return foodRemainingPercentage < 20
    }

    var isWaterLow: Bool {
        return waterRemainingPercentage < 20
    }

    func refillFood() {
        lastFoodRefill = Date()
    }

    func refillWater() {
        lastWaterRefill = Date()
    }
}

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
}
