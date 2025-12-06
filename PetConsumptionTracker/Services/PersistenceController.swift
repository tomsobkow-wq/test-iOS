import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample pets for preview
        let samplePets = [
            ("Buddy", "Dog", 24, 12),
            ("Whiskers", "Cat", 18, 8),
            ("Tweety", "Bird", 12, 6)
        ]

        for (name, species, foodHours, waterHours) in samplePets {
            let pet = PetEntity(context: viewContext)
            pet.id = UUID()
            pet.name = name
            pet.species = species
            pet.foodDurationHours = Int32(foodHours)
            pet.waterDurationHours = Int32(waterHours)
            pet.lastFoodRefill = Date().addingTimeInterval(-Double.random(in: 0...Double(foodHours) * 3600))
            pet.lastWaterRefill = Date().addingTimeInterval(-Double.random(in: 0...Double(waterHours) * 3600))
            pet.createdAt = Date()
            pet.useDefaultImage = true
            pet.defaultImageName = PetSpecies(rawValue: species)?.defaultImageName
            pet.foodNotificationEnabled = true
            pet.waterNotificationEnabled = true
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Preview context save error: \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PetModel")

        if inMemory {
            if let storeDescription = container.persistentStoreDescriptions.first {
                storeDescription.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        // Create the managed object model programmatically
        let model = createManagedObjectModel()
        container.managedObjectModel.entities = model.entities

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Persistent store loading error: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create PetEntity
        let petEntity = NSEntityDescription()
        petEntity.name = "PetEntity"
        petEntity.managedObjectClassName = "PetEntity"

        // Define attributes
        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .UUIDAttributeType
        idAttribute.isOptional = false

        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = false
        nameAttribute.defaultValue = ""

        let speciesAttribute = NSAttributeDescription()
        speciesAttribute.name = "species"
        speciesAttribute.attributeType = .stringAttributeType
        speciesAttribute.isOptional = false
        speciesAttribute.defaultValue = ""

        let imageDataAttribute = NSAttributeDescription()
        imageDataAttribute.name = "imageData"
        imageDataAttribute.attributeType = .binaryDataAttributeType
        imageDataAttribute.isOptional = true

        let useDefaultImageAttribute = NSAttributeDescription()
        useDefaultImageAttribute.name = "useDefaultImage"
        useDefaultImageAttribute.attributeType = .booleanAttributeType
        useDefaultImageAttribute.isOptional = false
        useDefaultImageAttribute.defaultValue = true

        let defaultImageNameAttribute = NSAttributeDescription()
        defaultImageNameAttribute.name = "defaultImageName"
        defaultImageNameAttribute.attributeType = .stringAttributeType
        defaultImageNameAttribute.isOptional = true

        let foodDurationHoursAttribute = NSAttributeDescription()
        foodDurationHoursAttribute.name = "foodDurationHours"
        foodDurationHoursAttribute.attributeType = .integer32AttributeType
        foodDurationHoursAttribute.isOptional = false
        foodDurationHoursAttribute.defaultValue = 24

        let waterDurationHoursAttribute = NSAttributeDescription()
        waterDurationHoursAttribute.name = "waterDurationHours"
        waterDurationHoursAttribute.attributeType = .integer32AttributeType
        waterDurationHoursAttribute.isOptional = false
        waterDurationHoursAttribute.defaultValue = 12

        let lastFoodRefillAttribute = NSAttributeDescription()
        lastFoodRefillAttribute.name = "lastFoodRefill"
        lastFoodRefillAttribute.attributeType = .dateAttributeType
        lastFoodRefillAttribute.isOptional = true

        let lastWaterRefillAttribute = NSAttributeDescription()
        lastWaterRefillAttribute.name = "lastWaterRefill"
        lastWaterRefillAttribute.attributeType = .dateAttributeType
        lastWaterRefillAttribute.isOptional = true

        let createdAtAttribute = NSAttributeDescription()
        createdAtAttribute.name = "createdAt"
        createdAtAttribute.attributeType = .dateAttributeType
        createdAtAttribute.isOptional = false
        createdAtAttribute.defaultValue = Date()

        let foodNotificationEnabledAttribute = NSAttributeDescription()
        foodNotificationEnabledAttribute.name = "foodNotificationEnabled"
        foodNotificationEnabledAttribute.attributeType = .booleanAttributeType
        foodNotificationEnabledAttribute.isOptional = false
        foodNotificationEnabledAttribute.defaultValue = true

        let waterNotificationEnabledAttribute = NSAttributeDescription()
        waterNotificationEnabledAttribute.name = "waterNotificationEnabled"
        waterNotificationEnabledAttribute.attributeType = .booleanAttributeType
        waterNotificationEnabledAttribute.isOptional = false
        waterNotificationEnabledAttribute.defaultValue = true

        petEntity.properties = [
            idAttribute,
            nameAttribute,
            speciesAttribute,
            imageDataAttribute,
            useDefaultImageAttribute,
            defaultImageNameAttribute,
            foodDurationHoursAttribute,
            waterDurationHoursAttribute,
            lastFoodRefillAttribute,
            lastWaterRefillAttribute,
            createdAtAttribute,
            foodNotificationEnabledAttribute,
            waterNotificationEnabledAttribute
        ]

        model.entities = [petEntity]
        return model
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
