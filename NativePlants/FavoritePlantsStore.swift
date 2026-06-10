import Foundation

@MainActor
final class FavoritePlantsStore: ObservableObject {
    static let shared = FavoritePlantsStore()

    @Published var favoriteIDs: [String] {
        didSet {
            save()
        }
    }

    private let storageKey = "dev.ryleyherrington.native-plants.favorite-plant-ids"

    private init() {
        favoriteIDs = Self.loadFavorites(storageKey: storageKey)
    }

    func isFavorite(_ plant: Plant) -> Bool {
        favoriteIDs.contains(plant.id)
    }

    func toggle(_ plant: Plant) {
        if isFavorite(plant) {
            unfavorite(plant)
        } else {
            favorite(plant)
        }
    }

    func favorite(_ plant: Plant) {
        guard !favoriteIDs.contains(plant.id) else {
            return
        }

        favoriteIDs.append(plant.id)
    }

    func unfavorite(_ plant: Plant) {
        favoriteIDs.removeAll { $0 == plant.id }
    }

    func favoritePlants(from plants: [Plant]) -> [Plant] {
        let plantsByID = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
        return favoriteIDs.compactMap { plantsByID[$0] }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favoriteIDs) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadFavorites(storageKey: String) -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let favoriteIDs = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return favoriteIDs
    }
}
