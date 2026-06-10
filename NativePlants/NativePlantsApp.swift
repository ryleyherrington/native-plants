import AppIntents
import SwiftUI

@main
struct NativePlantsApp: App {
    @MainActor
    init() {
        let wateringStore = WateringScheduleStore.shared
        AppDependencyManager.shared.add(dependency: wateringStore)
        wateringStore.bootstrapSpotlightIndex()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
