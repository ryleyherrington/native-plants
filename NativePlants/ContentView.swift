import AppIntents
import SwiftUI

private enum LayoutMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var wateringStore = WateringScheduleStore.shared
    @StateObject private var favoritesStore = FavoritePlantsStore.shared
    @State private var plants = PlantCatalog.load()
    @State private var searchText = ""
    @State private var layoutMode = LayoutMode.grid
    @State private var selectedSections = Set<String>()
    @State private var selectedDifficulties = Set<String>()
    @State private var selectedBloomTimes = Set<String>()
    @State private var selectedTraits = Set<String>()
    @State private var collapsedSections = Set<String>()
    @State private var showsLegend = false
    @State private var showsPlannerInDetail = true
    @State private var showsPlannerSheet = false
    @State private var showsWateringCalendar = false
    @State private var wateringFocusPlantID: String?
    @State private var showsFilters = false
    @State private var showsFavoritesReorder = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var preferredCompactColumn = NavigationSplitViewColumn.sidebar

    private var difficulties: [String] {
        Array(Set(plants.map(\.difficulty))).sorted()
    }

    private var traits: [String] {
        Array(Set(plants.flatMap(\.traits))).sorted()
    }

    private var bloomTimes: [String] {
        BloomSeason.allCases
            .map(\.title)
            .filter { bloomTime in
                plants.contains { plant in
                    plant.bloomSeasons.map(\.title).contains(bloomTime)
                }
            }
    }

    private var filteredPlants: [Plant] {
        plants.filter(matchesActiveFilters)
    }

    private var favoritePlants: [Plant] {
        favoritesStore.favoritePlants(from: plants).filter(matchesActiveFilters)
    }

    private var visibleFavoriteIDs: Set<String> {
        Set(favoritePlants.map(\.id))
    }

    private var groupedPlants: [(String, [Plant])] {
        PlantCatalog.sectionOrder.compactMap { section in
            let matches = filteredPlants.filter { plant in
                plant.section == section && !visibleFavoriteIDs.contains(plant.id)
            }
            return matches.isEmpty ? nil : (section, matches)
        }
    }

    private var activeFilterCount: Int {
        selectedSections.count + selectedDifficulties.count + selectedBloomTimes.count + selectedTraits.count
    }

    private var usesPlannerDetail: Bool {
        horizontalSizeClass != .compact
    }

    private func matchesActiveFilters(_ plant: Plant) -> Bool {
        let queryMatches = searchText.isEmpty || plant.searchableText.contains(searchText.foldedForSearch)
        let sectionMatches = selectedSections.isEmpty || selectedSections.contains(plant.section)
        let difficultyMatches = selectedDifficulties.isEmpty || selectedDifficulties.contains(plant.difficulty)
        let bloomMatches = selectedBloomTimes.isEmpty || !selectedBloomTimes.isDisjoint(with: plant.bloomSeasons.map(\.title))
        let traitMatches = selectedTraits.isEmpty || !selectedTraits.isDisjoint(with: plant.traits)
        return queryMatches && sectionMatches && difficultyMatches && bloomMatches && traitMatches
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            catalogColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 540, max: 760)
        } detail: {
            plannerDetail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showsLegend) {
            LegendView()
        }
        .sheet(isPresented: $showsPlannerSheet) {
            PlantPlannerView(plants: plants) {
                showsPlannerSheet = false
            }
        }
        .sheet(isPresented: $showsWateringCalendar) {
            WateringCalendarView(
                plants: plants,
                store: wateringStore,
                focusPlantID: wateringFocusPlantID
            )
        }
        .onChange(of: usesPlannerDetail) { _, usesDetail in
            if usesDetail {
                showsPlannerSheet = false
                columnVisibility = .all
            }
        }
        .onReceive(wateringStore.$presentationRequest.compactMap { $0 }) { request in
            switch request {
            case .calendar:
                wateringFocusPlantID = nil
            case .plant(let plantID):
                wateringFocusPlantID = plantID
            }
            showsWateringCalendar = true
            wateringStore.clearPresentationRequest()
        }
    }

    private var catalogColumn: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !favoritePlants.isEmpty {
                        FavoritePlantsSection(
                            plants: favoritePlants,
                            layoutMode: layoutMode,
                            isCollapsed: collapsedBinding(for: "Favorites"),
                            isFavorite: { favoritesStore.isFavorite($0) },
                            toggleFavorite: { favoritesStore.toggle($0) },
                            showReorder: {
                                showsFavoritesReorder = true
                            }
                        )
                    }

                    ForEach(groupedPlants, id: \.0) { section, plants in
                        PlantSection(
                            section: section,
                            plants: plants,
                            layoutMode: layoutMode,
                            isCollapsed: collapsedBinding(for: section),
                            isFavorite: { favoritesStore.isFavorite($0) },
                            toggleFavorite: { favoritesStore.toggle($0) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Native Plants")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search names, bloom, notes, traits")
            .navigationDestination(for: Plant.self) { plant in
                PlantDetailView(
                    plant: plant,
                    isFavorite: favoritesStore.isFavorite(plant),
                    toggleFavorite: {
                        favoritesStore.toggle(plant)
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsFilters = true
                    } label: {
                        Label("Filters", systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .tint(activeFilterCount > 0 ? .green : nil)
                    .accessibilityLabel(activeFilterCount > 0 ? "Filters, \(activeFilterCount) active" : "Filters")
                    .overlay(alignment: .topTrailing) {
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green, in: Capsule())
                                .offset(x: 8, y: -8)
                                .accessibilityHidden(true)
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Picker("Layout", selection: $layoutMode) {
                        ForEach(LayoutMode.allCases) { mode in
                            Image(systemName: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)

                    Button {
                        openPlanner()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Open plant planner")

                    Button {
                        wateringFocusPlantID = nil
                        showsWateringCalendar = true
                    } label: {
                        Image(systemName: "drop.fill")
                    }
                    .accessibilityLabel("Open watering calendar")

                    Button {
                        showsLegend = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Show plant icon key")
                }
            }
            .sheet(isPresented: $showsFilters) {
                FilterSheet(
                    sections: PlantCatalog.sectionOrder,
                    difficulties: difficulties,
                    bloomTimes: bloomTimes,
                    traits: traits,
                    selectedSections: $selectedSections,
                    selectedDifficulties: $selectedDifficulties,
                    selectedBloomTimes: $selectedBloomTimes,
                    selectedTraits: $selectedTraits
                )
            }
            .sheet(isPresented: $showsFavoritesReorder) {
                FavoritesReorderView(plants: plants, store: favoritesStore)
            }
        }
    }

    @ViewBuilder
    private var plannerDetail: some View {
        if usesPlannerDetail, showsPlannerInDetail {
            PlantPlannerView(plants: plants) {
                showsPlannerInDetail = false
                preferredCompactColumn = .sidebar
            }
        } else {
            PlannerPlaceholderView(openPlanner: openPlanner)
        }
    }

    private func openPlanner() {
        if usesPlannerDetail {
            showsPlannerInDetail = true
            showsPlannerSheet = false
            columnVisibility = .all
            preferredCompactColumn = .detail
        } else {
            showsPlannerSheet = true
            preferredCompactColumn = .sidebar
        }
    }

    private func collapsedBinding(for section: String) -> Binding<Bool> {
        Binding {
            collapsedSections.contains(section)
        } set: { isCollapsed in
            withAnimation(.snappy(duration: 0.2)) {
                if isCollapsed {
                    collapsedSections.insert(section)
                } else {
                    collapsedSections.remove(section)
                }
            }
        }
    }
}

private struct PlannerPlaceholderView: View {
    let openPlanner: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.green)

            Text("Plant Planner")
                .font(.title2.bold())

            Text("Open the planner to compare recommendations while keeping the catalog visible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                openPlanner()
            } label: {
                Label("Open Planner", systemImage: "sidebar.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

private struct FilterSheet: View {
    let sections: [String]
    let difficulties: [String]
    let bloomTimes: [String]
    let traits: [String]
    @Binding var selectedSections: Set<String>
    @Binding var selectedDifficulties: Set<String>
    @Binding var selectedBloomTimes: Set<String>
    @Binding var selectedTraits: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var hasActiveFilters: Bool {
        !(selectedSections.isEmpty && selectedDifficulties.isEmpty && selectedBloomTimes.isEmpty && selectedTraits.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ChipRow(title: "Section", values: sections, selection: $selectedSections)
                    ChipRow(title: "Ease", values: difficulties, selection: $selectedDifficulties)
                    ChipRow(title: "Bloom", values: bloomTimes, selection: $selectedBloomTimes)
                    ChipRow(title: "Traits", values: traits, selection: $selectedTraits)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        selectedSections.removeAll()
                        selectedDifficulties.removeAll()
                        selectedBloomTimes.removeAll()
                        selectedTraits.removeAll()
                    }
                    .disabled(!hasActiveFilters)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChipRow: View {
    let title: String
    let values: [String]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        if selection.contains(value) {
                            selection.remove(value)
                        } else {
                            selection.insert(value)
                        }
                    } label: {
                        ChipLabel(value: value, isSelected: selection.contains(value))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ChipLabel: View {
    let value: String
    let isSelected: Bool

    var body: some View {
        let icon = PlantIconography.icon(forTrait: value)

        HStack(spacing: 5) {
            Image(systemName: icon.symbolName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? Color.green : icon.color)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.green.opacity(0.18) : Color(.secondarySystemGroupedBackground))
        .foregroundStyle(isSelected ? Color.green : Color.primary)
        .clipShape(Capsule())
    }
}

private struct FavoritePlantsSection: View {
    let plants: [Plant]
    let layoutMode: LayoutMode
    @Binding var isCollapsed: Bool
    let isFavorite: (Plant) -> Bool
    let toggleFavorite: (Plant) -> Void
    let showReorder: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
            count: count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
                .zIndex(1)

            if !isCollapsed {
                if layoutMode == .grid {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(plants) { plant in
                            NavigationLink(value: plant) {
                                PlantGridCard(plant: plant, isFavorite: isFavorite(plant))
                                    .frame(height: PlantGridCard.cardHeight)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                FavoriteContextMenuButton(
                                    isFavorite: isFavorite(plant),
                                    toggleFavorite: {
                                        toggleFavorite(plant)
                                    }
                                )
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(plants) { plant in
                            NavigationLink(value: plant) {
                                PlantListRow(plant: plant, isFavorite: isFavorite(plant))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                FavoriteContextMenuButton(
                                    isFavorite: isFavorite(plant),
                                    toggleFavorite: {
                                        toggleFavorite(plant)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                isCollapsed.toggle()
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)

                    Text("Favorites")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    Text("\(plants.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand favorites" : "Collapse favorites")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            Button {
                showReorder()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .disabled(plants.count < 2)
            .accessibilityLabel("Reorder favorites")
        }
    }
}

private struct PlantSection: View {
    let section: String
    let plants: [Plant]
    let layoutMode: LayoutMode
    @Binding var isCollapsed: Bool
    let isFavorite: (Plant) -> Bool
    let toggleFavorite: (Plant) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        // 3 columns on regular width (iPad full screen), 2 on compact (iPhone, iPad slide-over).
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
            count: count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
                .zIndex(1)

            if !isCollapsed {
                if layoutMode == .grid {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(plants) { plant in
                            NavigationLink(value: plant) {
                                PlantGridCard(plant: plant, isFavorite: isFavorite(plant))
                                    .frame(height: PlantGridCard.cardHeight)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                FavoriteContextMenuButton(
                                    isFavorite: isFavorite(plant),
                                    toggleFavorite: {
                                        toggleFavorite(plant)
                                    }
                                )
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(plants) { plant in
                            NavigationLink(value: plant) {
                                PlantListRow(plant: plant, isFavorite: isFavorite(plant))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                FavoriteContextMenuButton(
                                    isFavorite: isFavorite(plant),
                                    toggleFavorite: {
                                        toggleFavorite(plant)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(section)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("\(plants.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand \(section)" : "Collapse \(section)")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }
}

private struct PlantGridCard: View {
    static let cardHeight: CGFloat = 338

    let plant: Plant
    let isFavorite: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                BundleImage(name: plant.imageName)
                    .frame(width: max(proxy.size.width - 20, 0), height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            FavoriteBadge()
                                .padding(7)
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(plant.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(plant.scientificName)
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                Text(plant.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                BloomSummary(seasons: plant.bloomSeasons, compact: true)
            }
            .frame(width: max(proxy.size.width - 20, 0), height: 92, alignment: .topLeading)

                DifficultyBadge(text: plant.difficulty)
                    .frame(height: 24, alignment: .leading)

                NativeIconStrip(icons: PlantIconography.icons(for: plant), compact: true)
                    .frame(width: max(proxy.size.width - 20, 0), height: 20, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .clipped()
        }
    }
}

private struct PlantListRow: View {
    let plant: Plant
    let isFavorite: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BundleImage(name: plant.imageName)
                .frame(width: 86, height: 86)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(plant.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(plant.scientificName)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(plant.habit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(plant.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                BloomSummary(seasons: plant.bloomSeasons, compact: true)
                DifficultyBadge(text: plant.difficulty)
                NativeIconStrip(icons: PlantIconography.icons(for: plant), compact: true)
                    .frame(height: 20, alignment: .leading)
            }

            Spacer(minLength: 0)

            if isFavorite {
                FavoriteBadge()
            }
        }
        .padding(10)
        .frame(minHeight: 142, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FavoriteBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.yellow)
            .frame(width: 28, height: 28)
            .background(.thinMaterial, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct FavoriteContextMenuButton: View {
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        Button(action: toggleFavorite) {
            Label(
                isFavorite ? "Remove Favorite" : "Favorite",
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
    }
}

private struct DifficultyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(text.localizedCaseInsensitiveContains("moderately") ? Color.orange.opacity(0.16) : Color.green.opacity(0.16))
            .foregroundStyle(text.localizedCaseInsensitiveContains("moderately") ? Color.orange : Color.green)
            .clipShape(Capsule())
    }
}

private struct BloomSummary: View {
    let seasons: [BloomSeason]
    var compact = false

    var body: some View {
        if !seasons.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "camera.macro")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.pink)
                Text(seasons.map(\.title).joined(separator: ", "))
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct NativeIconStrip: View {
    let icons: [PlantFeatureIcon]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            ForEach(icons.prefix(compact ? 6 : 10)) { icon in
                Image(systemName: icon.symbolName)
                    .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                    .foregroundStyle(icon.color)
                    .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                    .background(icon.color.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityLabel(icon.label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FavoritesReorderView: View {
    let plants: [Plant]
    @ObservedObject var store: FavoritePlantsStore
    @Environment(\.dismiss) private var dismiss

    private var plantsByID: [String: Plant] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    favoriteRows
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteRows: some View {
        ForEach($store.favoriteIDs, id: \.self) { $plantID in
            if let plant = plantsByID[plantID] {
                FavoriteReorderRow(plant: plant)
            }
        }
        .reorderable()
    }
}

private struct FavoriteReorderRow: View {
    let plant: Plant

    var body: some View {
        HStack(spacing: 12) {
            BundleImage(name: plant.imageName)
                .frame(width: 52, height: 52)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(plant.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(plant.scientificName)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct PlantDetailView: View {
    let plant: Plant
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BundleImage(name: plant.imageName)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(plant.scientificName)
                        .font(.title3.italic())
                        .foregroundStyle(.secondary)
                    Text(plant.habit)
                        .font(.headline)
                    Text(plant.size)
                    DifficultyBadge(text: plant.difficulty)
                    BloomSummary(seasons: plant.bloomSeasons)
                }

                Text(plant.notes)
                    .font(.body)

                PlantWateringPanel(plant: plant, store: WateringScheduleStore.shared)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plant Cues")
                        .font(.headline)
                    NativeIconStrip(icons: PlantIconography.icons(for: plant))
                }

                if !plant.traits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Traits")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(plant.traits, id: \.self) { trait in
                                ChipLabel(value: trait, isSelected: false)
                            }
                        }
                    }
                }

                Text("Source page \(plant.sourcePage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .tint(.yellow)
                .accessibilityLabel(isFavorite ? "Remove favorite" : "Favorite plant")
            }
        }
        .userActivity("dev.ryleyherrington.NativePlants.viewPlant") { activity in
            if #available(iOS 18.2, *) {
                activity.appEntityIdentifier = EntityIdentifier(for: PlantEntity.self, identifier: plant.id)
            }
        }
    }
}

private struct LegendView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(PlantIconography.legendGroups) { group in
                        LegendGroupView(group: group)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plant Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LegendGroupView: View {
    let group: PlantIconLegendGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(group.icons) { icon in
                    LegendRow(icon: icon)

                    if icon.id != group.icons.last?.id {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct LegendRow: View {
    let icon: PlantFeatureIcon

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(icon.color)
                .frame(width: 28, height: 28)
                .background(icon.color.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(icon.label)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(icon.label)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(proposal: proposal, subviews: subviews).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var items: [(Int, CGRect)] = []

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (items, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
