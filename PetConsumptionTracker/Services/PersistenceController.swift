import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample pets for preview
        let samplePets = [
            ("Buddy", "Dog", 24, 12, 24),
            ("Whiskers", "Cat", 18, 8, 48),
            ("Tweety", "Bird", 12, 6, 72)
        ]

        for (name, species, foodHours, waterHours, exerciseHours) in samplePets {
            let pet = PetEntity(context: viewContext)
            pet.id = UUID()
            pet.name = name
            pet.species = species
            pet.foodDurationHours = Int32(foodHours)
            pet.waterDurationHours = Int32(waterHours)
            pet.exerciseDurationHours = Int32(exerciseHours)
            pet.lastFoodRefill = Date().addingTimeInterval(-Double.random(in: 0...Double(foodHours) * 3600))
            pet.lastWaterRefill = Date().addingTimeInterval(-Double.random(in: 0...Double(waterHours) * 3600))
            pet.lastExercise = Date().addingTimeInterval(-Double.random(in: 0...Double(exerciseHours) * 3600))
            pet.createdAt = Date()
            pet.useDefaultImage = true
            pet.defaultImageName = PetSpecies(rawValue: species)?.defaultImageName
            pet.foodNotificationEnabled = true
            pet.waterNotificationEnabled = true
            pet.exerciseNotificationEnabled = true

            // Add sample medicine
            let medicine = MedicineEntity(context: viewContext)
            medicine.id = UUID()
            medicine.name = "Vitamins"
            medicine.dosage = "1 tablet"
            medicine.frequencyHours = 24
            medicine.lastAdministered = Date().addingTimeInterval(-Double.random(in: 0...24 * 3600))
            medicine.notificationEnabled = true
            medicine.notes = "Give with food"
            medicine.createdAt = Date()
            medicine.pet = pet

            // Add sample vet visit
            let vetVisit = VetVisitEntity(context: viewContext)
            vetVisit.id = UUID()
            vetVisit.visitDate = Date().addingTimeInterval(Double.random(in: 7...30) * 24 * 3600)
            vetVisit.vetName = "Dr. Smith"
            vetVisit.clinicName = "Happy Pets Clinic"
            vetVisit.reason = "Annual checkup"
            vetVisit.notes = ""
            vetVisit.isCompleted = false
            vetVisit.reminderEnabled = true
            vetVisit.createdAt = Date()
            vetVisit.pet = pet
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
        // Create the managed object model programmatically before initializing the container
        let model = PersistenceController.createManagedObjectModel()
        container = NSPersistentContainer(name: "PetModel", managedObjectModel: model)

        if inMemory {
            if let storeDescription = container.persistentStoreDescriptions.first {
                storeDescription.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                print("Persistent store loading error: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create PetEntity
        let petEntity = NSEntityDescription()
        petEntity.name = "PetEntity"
        petEntity.managedObjectClassName = "PetEntity"

        // Create MedicineEntity
        let medicineEntity = NSEntityDescription()
        medicineEntity.name = "MedicineEntity"
        medicineEntity.managedObjectClassName = "MedicineEntity"

        // Create VetVisitEntity
        let vetVisitEntity = NSEntityDescription()
        vetVisitEntity.name = "VetVisitEntity"
        vetVisitEntity.managedObjectClassName = "VetVisitEntity"

        // ===== PetEntity Attributes =====
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

        let exerciseDurationHoursAttribute = NSAttributeDescription()
        exerciseDurationHoursAttribute.name = "exerciseDurationHours"
        exerciseDurationHoursAttribute.attributeType = .integer32AttributeType
        exerciseDurationHoursAttribute.isOptional = false
        exerciseDurationHoursAttribute.defaultValue = 24

        let lastFoodRefillAttribute = NSAttributeDescription()
        lastFoodRefillAttribute.name = "lastFoodRefill"
        lastFoodRefillAttribute.attributeType = .dateAttributeType
        lastFoodRefillAttribute.isOptional = true

        let lastWaterRefillAttribute = NSAttributeDescription()
        lastWaterRefillAttribute.name = "lastWaterRefill"
        lastWaterRefillAttribute.attributeType = .dateAttributeType
        lastWaterRefillAttribute.isOptional = true

        let lastExerciseAttribute = NSAttributeDescription()
        lastExerciseAttribute.name = "lastExercise"
        lastExerciseAttribute.attributeType = .dateAttributeType
        lastExerciseAttribute.isOptional = true

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

        let exerciseNotificationEnabledAttribute = NSAttributeDescription()
        exerciseNotificationEnabledAttribute.name = "exerciseNotificationEnabled"
        exerciseNotificationEnabledAttribute.attributeType = .booleanAttributeType
        exerciseNotificationEnabledAttribute.isOptional = false
        exerciseNotificationEnabledAttribute.defaultValue = true

        // ===== MedicineEntity Attributes =====
        let medicineIdAttribute = NSAttributeDescription()
        medicineIdAttribute.name = "id"
        medicineIdAttribute.attributeType = .UUIDAttributeType
        medicineIdAttribute.isOptional = false

        let medicineNameAttribute = NSAttributeDescription()
        medicineNameAttribute.name = "name"
        medicineNameAttribute.attributeType = .stringAttributeType
        medicineNameAttribute.isOptional = false
        medicineNameAttribute.defaultValue = ""

        let medicineDosageAttribute = NSAttributeDescription()
        medicineDosageAttribute.name = "dosage"
        medicineDosageAttribute.attributeType = .stringAttributeType
        medicineDosageAttribute.isOptional = true

        let medicineFrequencyHoursAttribute = NSAttributeDescription()
        medicineFrequencyHoursAttribute.name = "frequencyHours"
        medicineFrequencyHoursAttribute.attributeType = .integer32AttributeType
        medicineFrequencyHoursAttribute.isOptional = false
        medicineFrequencyHoursAttribute.defaultValue = 24

        let medicineLastAdministeredAttribute = NSAttributeDescription()
        medicineLastAdministeredAttribute.name = "lastAdministered"
        medicineLastAdministeredAttribute.attributeType = .dateAttributeType
        medicineLastAdministeredAttribute.isOptional = true

        let medicineNotificationEnabledAttribute = NSAttributeDescription()
        medicineNotificationEnabledAttribute.name = "notificationEnabled"
        medicineNotificationEnabledAttribute.attributeType = .booleanAttributeType
        medicineNotificationEnabledAttribute.isOptional = false
        medicineNotificationEnabledAttribute.defaultValue = true

        let medicineNotesAttribute = NSAttributeDescription()
        medicineNotesAttribute.name = "notes"
        medicineNotesAttribute.attributeType = .stringAttributeType
        medicineNotesAttribute.isOptional = true

        let medicineCreatedAtAttribute = NSAttributeDescription()
        medicineCreatedAtAttribute.name = "createdAt"
        medicineCreatedAtAttribute.attributeType = .dateAttributeType
        medicineCreatedAtAttribute.isOptional = false
        medicineCreatedAtAttribute.defaultValue = Date()

        let medicineIsActiveAttribute = NSAttributeDescription()
        medicineIsActiveAttribute.name = "isActive"
        medicineIsActiveAttribute.attributeType = .booleanAttributeType
        medicineIsActiveAttribute.isOptional = false
        medicineIsActiveAttribute.defaultValue = true

        // ===== VetVisitEntity Attributes =====
        let vetVisitIdAttribute = NSAttributeDescription()
        vetVisitIdAttribute.name = "id"
        vetVisitIdAttribute.attributeType = .UUIDAttributeType
        vetVisitIdAttribute.isOptional = false

        let vetVisitDateAttribute = NSAttributeDescription()
        vetVisitDateAttribute.name = "visitDate"
        vetVisitDateAttribute.attributeType = .dateAttributeType
        vetVisitDateAttribute.isOptional = false
        vetVisitDateAttribute.defaultValue = Date()

        let vetVisitVetNameAttribute = NSAttributeDescription()
        vetVisitVetNameAttribute.name = "vetName"
        vetVisitVetNameAttribute.attributeType = .stringAttributeType
        vetVisitVetNameAttribute.isOptional = true

        let vetVisitClinicNameAttribute = NSAttributeDescription()
        vetVisitClinicNameAttribute.name = "clinicName"
        vetVisitClinicNameAttribute.attributeType = .stringAttributeType
        vetVisitClinicNameAttribute.isOptional = true

        let vetVisitReasonAttribute = NSAttributeDescription()
        vetVisitReasonAttribute.name = "reason"
        vetVisitReasonAttribute.attributeType = .stringAttributeType
        vetVisitReasonAttribute.isOptional = false
        vetVisitReasonAttribute.defaultValue = ""

        let vetVisitNotesAttribute = NSAttributeDescription()
        vetVisitNotesAttribute.name = "notes"
        vetVisitNotesAttribute.attributeType = .stringAttributeType
        vetVisitNotesAttribute.isOptional = true

        let vetVisitIsCompletedAttribute = NSAttributeDescription()
        vetVisitIsCompletedAttribute.name = "isCompleted"
        vetVisitIsCompletedAttribute.attributeType = .booleanAttributeType
        vetVisitIsCompletedAttribute.isOptional = false
        vetVisitIsCompletedAttribute.defaultValue = false

        let vetVisitReminderEnabledAttribute = NSAttributeDescription()
        vetVisitReminderEnabledAttribute.name = "reminderEnabled"
        vetVisitReminderEnabledAttribute.attributeType = .booleanAttributeType
        vetVisitReminderEnabledAttribute.isOptional = false
        vetVisitReminderEnabledAttribute.defaultValue = true

        let vetVisitCreatedAtAttribute = NSAttributeDescription()
        vetVisitCreatedAtAttribute.name = "createdAt"
        vetVisitCreatedAtAttribute.attributeType = .dateAttributeType
        vetVisitCreatedAtAttribute.isOptional = false
        vetVisitCreatedAtAttribute.defaultValue = Date()

        // ===== Relationships =====

        // Pet -> Medicines (one-to-many)
        let petToMedicinesRelationship = NSRelationshipDescription()
        petToMedicinesRelationship.name = "medicines"
        petToMedicinesRelationship.destinationEntity = medicineEntity
        petToMedicinesRelationship.isOptional = true
        petToMedicinesRelationship.deleteRule = .cascadeDeleteRule

        // Medicine -> Pet (many-to-one)
        let medicineToPetRelationship = NSRelationshipDescription()
        medicineToPetRelationship.name = "pet"
        medicineToPetRelationship.destinationEntity = petEntity
        medicineToPetRelationship.maxCount = 1
        medicineToPetRelationship.isOptional = false
        medicineToPetRelationship.deleteRule = .nullifyDeleteRule

        petToMedicinesRelationship.inverseRelationship = medicineToPetRelationship
        medicineToPetRelationship.inverseRelationship = petToMedicinesRelationship

        // Pet -> VetVisits (one-to-many)
        let petToVetVisitsRelationship = NSRelationshipDescription()
        petToVetVisitsRelationship.name = "vetVisits"
        petToVetVisitsRelationship.destinationEntity = vetVisitEntity
        petToVetVisitsRelationship.isOptional = true
        petToVetVisitsRelationship.deleteRule = .cascadeDeleteRule

        // VetVisit -> Pet (many-to-one)
        let vetVisitToPetRelationship = NSRelationshipDescription()
        vetVisitToPetRelationship.name = "pet"
        vetVisitToPetRelationship.destinationEntity = petEntity
        vetVisitToPetRelationship.maxCount = 1
        vetVisitToPetRelationship.isOptional = false
        vetVisitToPetRelationship.deleteRule = .nullifyDeleteRule

        petToVetVisitsRelationship.inverseRelationship = vetVisitToPetRelationship
        vetVisitToPetRelationship.inverseRelationship = petToVetVisitsRelationship

        // Set properties for each entity
        petEntity.properties = [
            idAttribute,
            nameAttribute,
            speciesAttribute,
            imageDataAttribute,
            useDefaultImageAttribute,
            defaultImageNameAttribute,
            foodDurationHoursAttribute,
            waterDurationHoursAttribute,
            exerciseDurationHoursAttribute,
            lastFoodRefillAttribute,
            lastWaterRefillAttribute,
            lastExerciseAttribute,
            createdAtAttribute,
            foodNotificationEnabledAttribute,
            waterNotificationEnabledAttribute,
            exerciseNotificationEnabledAttribute,
            petToMedicinesRelationship,
            petToVetVisitsRelationship
        ]

        medicineEntity.properties = [
            medicineIdAttribute,
            medicineNameAttribute,
            medicineDosageAttribute,
            medicineFrequencyHoursAttribute,
            medicineLastAdministeredAttribute,
            medicineNotificationEnabledAttribute,
            medicineNotesAttribute,
            medicineCreatedAtAttribute,
            medicineIsActiveAttribute,
            medicineToPetRelationship
        ]

        vetVisitEntity.properties = [
            vetVisitIdAttribute,
            vetVisitDateAttribute,
            vetVisitVetNameAttribute,
            vetVisitClinicNameAttribute,
            vetVisitReasonAttribute,
            vetVisitNotesAttribute,
            vetVisitIsCompletedAttribute,
            vetVisitReminderEnabledAttribute,
            vetVisitCreatedAtAttribute,
            vetVisitToPetRelationship
        ]

        model.entities = [petEntity, medicineEntity, vetVisitEntity]
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
