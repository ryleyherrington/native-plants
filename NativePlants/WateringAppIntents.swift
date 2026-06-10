import AppIntents
import CoreSpotlight
import Foundation

enum WateringIntentError: LocalizedError {
    case entityNotFound

    var errorDescription: String? {
        switch self {
        case .entityNotFound:
            return "That plant or watering schedule could not be found."
        }
    }
}

struct PlantEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Plant")
    static let defaultQuery = PlantEntityQuery()

    let id: String
    let name: String
    let scientificName: String
    let section: String
    let difficulty: String
    let notes: String
    let traits: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(scientificName)",
            image: .init(systemName: "leaf.fill")
        )
    }

    init(plant: Plant) {
        id = plant.id
        name = plant.name
        scientificName = plant.scientificName
        section = plant.section
        difficulty = plant.difficulty
        notes = plant.notes
        traits = plant.traits
    }
}

struct PlantEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [PlantEntity] {
        PlantCatalog.load().map(PlantEntity.init)
    }

    func entities(for identifiers: [PlantEntity.ID]) async throws -> [PlantEntity] {
        let ids = Set(identifiers)
        return PlantCatalog.load()
            .filter { ids.contains($0.id) }
            .map(PlantEntity.init)
    }

    func entities(matching string: String) async throws -> [PlantEntity] {
        let query = string.foldedForSearch
        return PlantCatalog.load()
            .filter { plant in
                plant.searchableText.contains(query)
            }
            .map(PlantEntity.init)
    }

    func suggestedEntities() async throws -> [PlantEntity] {
        PlantCatalog.load()
            .prefix(12)
            .map(PlantEntity.init)
    }
}

@available(iOS 18.0, *)
extension PlantEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = name
        attributes.contentDescription = "\(scientificName). \(section). \(difficulty). \(notes)"
        attributes.keywords = traits + [scientificName, section, difficulty, "native plant", "watering"]
        return attributes
    }
}

struct WateringScheduleEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Watering Schedule")
    static let defaultQuery = WateringScheduleEntityQuery()

    let id: UUID
    let plantID: String
    let plantName: String
    let nextWateringDate: Date
    let intervalDays: Int
    let notes: String

    var displayRepresentation: DisplayRepresentation {
        let dateText = WateringDateFormatter.shared.string(from: nextWateringDate)
        return DisplayRepresentation(
            title: "\(plantName)",
            subtitle: "\(dateText) - every \(intervalDays) days",
            image: .init(systemName: "drop.fill")
        )
    }

    init(schedule: WateringSchedule) {
        id = schedule.id
        plantID = schedule.plantID
        plantName = schedule.plantName
        nextWateringDate = schedule.nextWateringDate()
        intervalDays = schedule.intervalDays
        notes = schedule.notes
    }
}

struct WateringScheduleEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [WateringScheduleEntity] {
        await MainActor.run {
            WateringScheduleStore.shared
                .schedulesSortedByNextDate()
                .map(WateringScheduleEntity.init)
        }
    }

    func entities(for identifiers: [WateringScheduleEntity.ID]) async throws -> [WateringScheduleEntity] {
        let ids = Set(identifiers)
        return await MainActor.run {
            WateringScheduleStore.shared
                .schedulesSortedByNextDate()
                .filter { ids.contains($0.id) }
                .map(WateringScheduleEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [WateringScheduleEntity] {
        let query = string.foldedForSearch
        return await MainActor.run {
            WateringScheduleStore.shared
                .schedulesSortedByNextDate()
                .filter { schedule in
                    schedule.plantName.foldedForSearch.contains(query)
                        || schedule.notes.foldedForSearch.contains(query)
                }
                .map(WateringScheduleEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WateringScheduleEntity] {
        await MainActor.run {
            WateringScheduleStore.shared
                .upcomingSchedules(limit: 8)
                .map(WateringScheduleEntity.init)
        }
    }
}

@available(iOS 18.0, *)
extension WateringScheduleEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let dateText = WateringDateFormatter.shared.string(from: nextWateringDate)
        attributes.title = "Water \(plantName)"
        attributes.contentDescription = "Watering schedule for \(plantName), next due \(dateText), every \(intervalDays) days. \(notes)"
        attributes.dueDate = nextWateringDate
        attributes.keywords = [plantName, "water", "watering", "native plant", "garden"]
        return attributes
    }
}

struct ScheduleWateringIntent: AppIntent {
    static let title: LocalizedStringResource = "Schedule Plant Watering"
    static let description = IntentDescription("Add or update a recurring watering schedule for a native plant.")

    @Parameter(title: "Plant")
    var plant: PlantEntity

    @Parameter(title: "First Watering", kind: .date)
    var startDate: Date

    @Parameter(title: "Repeat Every Days")
    var intervalDays: Int

    @Parameter(title: "Notes")
    var notes: String?

    init() {
        startDate = Date()
        intervalDays = 7
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<WateringScheduleEntity> & ProvidesDialog {
        guard let catalogPlant = PlantCatalog.load().first(where: { $0.id == plant.id }) else {
            throw WateringIntentError.entityNotFound
        }

        let schedule = WateringScheduleStore.shared.upsertSchedule(
            for: catalogPlant,
            startDate: startDate,
            intervalDays: intervalDays,
            notes: notes ?? ""
        )
        WateringScheduleStore.shared.requestPlant(catalogPlant.id)

        let nextDate = WateringDateFormatter.shared.string(from: schedule.nextWateringDate())
        return .result(
            value: WateringScheduleEntity(schedule: schedule),
            dialog: "I scheduled \(catalogPlant.name) for \(nextDate), repeating every \(schedule.intervalDays) days."
        )
    }
}

struct OpenWateringCalendarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Watering Calendar"
    static let description = IntentDescription("Open the Native Plants watering calendar.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        WateringScheduleStore.shared.requestCalendar()
        return .result(dialog: "Opening the watering calendar.")
    }
}

struct OpenPlantWateringIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Plant Watering"
    static let description = IntentDescription("Open watering details for a native plant.")
    static let openAppWhenRun = true

    @Parameter(title: "Plant")
    var plant: PlantEntity

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        WateringScheduleStore.shared.requestPlant(plant.id)
        return .result(dialog: "Opening watering for \(plant.name).")
    }
}

struct MarkPlantWateredIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Plant Watered"
    static let description = IntentDescription("Mark a watering schedule as completed today.")

    @Parameter(title: "Watering Schedule")
    var schedule: WateringScheduleEntity

    @MainActor
    func perform() async throws -> some ReturnsValue<WateringScheduleEntity> & ProvidesDialog {
        WateringScheduleStore.shared.markWatered(scheduleID: schedule.id)

        guard let updatedSchedule = WateringScheduleStore.shared.schedule(with: schedule.id) else {
            throw WateringIntentError.entityNotFound
        }

        let nextDate = WateringDateFormatter.shared.string(from: updatedSchedule.nextWateringDate())
        return .result(
            value: WateringScheduleEntity(schedule: updatedSchedule),
            dialog: "\(updatedSchedule.plantName) is marked watered. The next watering is \(nextDate)."
        )
    }
}

struct NativePlantsAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lime

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleWateringIntent(),
            phrases: [
                "Schedule plant watering in \(.applicationName)",
                "Add watering to \(.applicationName)"
            ],
            shortTitle: "Schedule Watering",
            systemImageName: "drop.fill"
        )

        AppShortcut(
            intent: OpenWateringCalendarIntent(),
            phrases: [
                "Open watering calendar in \(.applicationName)",
                "Show watering in \(.applicationName)"
            ],
            shortTitle: "Watering Calendar",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: MarkPlantWateredIntent(),
            phrases: [
                "Mark plant watered in \(.applicationName)",
                "I watered a plant in \(.applicationName)"
            ],
            shortTitle: "Mark Watered",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
