import Foundation
import CoreSpotlight

@MainActor
final class WateringScheduleStore: ObservableObject, @unchecked Sendable {
    enum PresentationRequest: Equatable {
        case calendar
        case plant(String)
    }

    static let shared = WateringScheduleStore()

    @Published private(set) var schedules: [WateringSchedule]
    @Published var presentationRequest: PresentationRequest?

    private let storageKey = "dev.ryleyherrington.native-plants.watering-schedules"
    private let calendar = Calendar.current

    private init() {
        schedules = Self.loadSchedules(storageKey: storageKey)
    }

    func bootstrapSpotlightIndex(plants: [Plant] = PlantCatalog.load()) {
        WateringSpotlightIndexer.reindex(plants: plants, schedules: schedules)
    }

    func schedulesSortedByNextDate() -> [WateringSchedule] {
        schedules.sorted { lhs, rhs in
            let lhsDate = lhs.nextWateringDate(calendar: calendar)
            let rhsDate = rhs.nextWateringDate(calendar: calendar)
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.plantName < rhs.plantName
        }
    }

    func upcomingSchedules(limit: Int? = nil) -> [WateringSchedule] {
        let sorted = schedulesSortedByNextDate()
        guard let limit else {
            return sorted
        }
        return Array(sorted.prefix(limit))
    }

    func schedule(for plantID: String) -> WateringSchedule? {
        schedules.first { $0.plantID == plantID }
    }

    func schedule(with id: UUID) -> WateringSchedule? {
        schedules.first { $0.id == id }
    }

    @discardableResult
    func upsertSchedule(
        for plant: Plant,
        startDate: Date,
        intervalDays: Int,
        notes: String
    ) -> WateringSchedule {
        let clampedInterval = max(1, min(intervalDays, 60))
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        if let existingIndex = schedules.firstIndex(where: { $0.plantID == plant.id }) {
            schedules[existingIndex].plantName = plant.name
            schedules[existingIndex].startDate = startDate
            schedules[existingIndex].intervalDays = clampedInterval
            schedules[existingIndex].notes = trimmedNotes
            schedules[existingIndex].updatedAt = now
            saveAndIndex()
            return schedules[existingIndex]
        }

        let schedule = WateringSchedule(
            id: UUID(),
            plantID: plant.id,
            plantName: plant.name,
            startDate: startDate,
            intervalDays: clampedInterval,
            notes: trimmedNotes,
            lastWateredDate: nil,
            createdAt: now,
            updatedAt: now
        )
        schedules.append(schedule)
        saveAndIndex()
        return schedule
    }

    func markWatered(scheduleID: UUID, on date: Date = Date()) {
        guard let index = schedules.firstIndex(where: { $0.id == scheduleID }) else {
            return
        }
        schedules[index].lastWateredDate = date
        schedules[index].updatedAt = date
        saveAndIndex()
    }

    func delete(scheduleID: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == scheduleID }) else {
            return
        }
        schedules.remove(at: index)
        save()
        WateringSpotlightIndexer.deleteSchedule(id: scheduleID)
    }

    func requestCalendar() {
        presentationRequest = .calendar
    }

    func requestPlant(_ plantID: String) {
        presentationRequest = .plant(plantID)
    }

    func clearPresentationRequest() {
        presentationRequest = nil
    }

    private func saveAndIndex() {
        save()
        WateringSpotlightIndexer.reindex(plants: PlantCatalog.load(), schedules: schedules)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(schedules) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadSchedules(storageKey: String) -> [WateringSchedule] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let schedules = try? JSONDecoder().decode([WateringSchedule].self, from: data) else {
            return []
        }
        return schedules
    }
}

struct WateringSchedule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let plantID: String
    var plantName: String
    var startDate: Date
    var intervalDays: Int
    var notes: String
    var lastWateredDate: Date?
    let createdAt: Date
    var updatedAt: Date

    func nextWateringDate(
        after referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let interval = max(1, intervalDays)
        let firstCandidate: Date

        if let lastWateredDate,
           let date = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: lastWateredDate)) {
            firstCandidate = date
        } else {
            firstCandidate = calendar.startOfDay(for: startDate)
        }

        guard firstCandidate < referenceDay else {
            return firstCandidate
        }

        let elapsedDays = calendar.dateComponents([.day], from: firstCandidate, to: referenceDay).day ?? 0
        let intervalsElapsed = Int(ceil(Double(elapsedDays) / Double(interval)))
        return calendar.date(byAdding: .day, value: intervalsElapsed * interval, to: firstCandidate) ?? referenceDay
    }

    func daysUntilNextWatering(
        after referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let nextDate = nextWateringDate(after: referenceDate, calendar: calendar)
        return calendar.dateComponents([.day], from: referenceDay, to: nextDate).day ?? 0
    }

    func isDue(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        daysUntilNextWatering(after: referenceDate, calendar: calendar) <= 0
    }
}

enum WateringRecommendation {
    static func intervalDays(for plant: Plant) -> Int {
        let text = ([plant.section, plant.habit, plant.notes] + plant.traits)
            .joined(separator: " ")
            .foldedForSearch

        if text.contains("wet") || text.contains("moist") || text.contains("riparian") || text.contains("fern") {
            return 4
        }

        if text.contains("dry") || text.contains("drought") || text.contains("xeric") {
            return 14
        }

        if text.contains("well-drained") || text.contains("well drained") {
            return 10
        }

        if plant.section.localizedCaseInsensitiveContains("trees")
            || plant.section.localizedCaseInsensitiveContains("shrubs") {
            return 7
        }

        return 6
    }
}

extension Plant {
    var suggestedWateringIntervalDays: Int {
        WateringRecommendation.intervalDays(for: self)
    }
}

enum WateringDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func relativeText(for schedule: WateringSchedule, calendar: Calendar = .current) -> String {
        let days = schedule.daysUntilNextWatering(calendar: calendar)
        if days < 0 {
            return "Overdue"
        }
        if days == 0 {
            return "Today"
        }
        if days == 1 {
            return "Tomorrow"
        }
        return "In \(days) days"
    }
}

enum WateringSpotlightIndexer {
    private static let searchableIndex = CSSearchableIndex(name: "dev.ryleyherrington.NativePlants.watering")

    @MainActor
    static func reindex(plants: [Plant], schedules: [WateringSchedule]) {
        guard #available(iOS 18.0, *) else {
            return
        }

        let plantEntities = plants.map(PlantEntity.init)
        let scheduleEntities = schedules.map(WateringScheduleEntity.init)
        Task {
            try? await searchableIndex.indexAppEntities(plantEntities)
            try? await searchableIndex.indexAppEntities(scheduleEntities)
        }
    }

    @MainActor
    static func deleteSchedule(id: UUID) {
        guard #available(iOS 18.0, *) else {
            return
        }

        Task {
            try? await searchableIndex.deleteAppEntities(
                identifiedBy: [id],
                ofType: WateringScheduleEntity.self
            )
        }
    }
}
