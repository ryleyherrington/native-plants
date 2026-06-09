import SwiftUI

private enum LayoutMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

struct ContentView: View {
    @State private var plants = PlantCatalog.load()
    @State private var searchText = ""
    @State private var layoutMode = LayoutMode.grid
    @State private var selectedSections = Set<String>()
    @State private var selectedDifficulties = Set<String>()
    @State private var selectedBloomTimes = Set<String>()
    @State private var selectedTraits = Set<String>()
    @State private var showsLegend = false
    @State private var showsPlanner = false
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
        plants.filter { plant in
            let queryMatches = searchText.isEmpty || plant.searchableText.contains(searchText.foldedForSearch)
            let sectionMatches = selectedSections.isEmpty || selectedSections.contains(plant.section)
            let difficultyMatches = selectedDifficulties.isEmpty || selectedDifficulties.contains(plant.difficulty)
            let bloomMatches = selectedBloomTimes.isEmpty || !selectedBloomTimes.isDisjoint(with: plant.bloomSeasons.map(\.title))
            let traitMatches = selectedTraits.isEmpty || !selectedTraits.isDisjoint(with: plant.traits)
            return queryMatches && sectionMatches && difficultyMatches && bloomMatches && traitMatches
        }
    }

    private var groupedPlants: [(String, [Plant])] {
        PlantCatalog.sectionOrder.compactMap { section in
            let matches = filteredPlants.filter { $0.section == section }
            return matches.isEmpty ? nil : (section, matches)
        }
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
    }

    private var catalogColumn: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FilterPanel(
                        sections: PlantCatalog.sectionOrder,
                        difficulties: difficulties,
                        bloomTimes: bloomTimes,
                        traits: traits,
                        selectedSections: $selectedSections,
                        selectedDifficulties: $selectedDifficulties,
                        selectedBloomTimes: $selectedBloomTimes,
                        selectedTraits: $selectedTraits
                    )

                    ForEach(groupedPlants, id: \.0) { section, plants in
                        PlantSection(section: section, plants: plants, layoutMode: layoutMode)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Native Plants")
            .searchable(text: $searchText, prompt: "Search names, bloom, notes, traits")
            .toolbar {
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
                        showsLegend = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Show plant icon key")
                }
            }
        }
    }

    @ViewBuilder
    private var plannerDetail: some View {
        if showsPlanner {
            PlantPlannerView(plants: plants) {
                showsPlanner = false
                preferredCompactColumn = .sidebar
            }
        } else {
            PlannerPlaceholderView(openPlanner: openPlanner)
        }
    }

    private func openPlanner() {
        showsPlanner = true
        columnVisibility = .all
        preferredCompactColumn = .detail
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

private struct FilterPanel: View {
    let sections: [String]
    let difficulties: [String]
    let bloomTimes: [String]
    let traits: [String]
    @Binding var selectedSections: Set<String>
    @Binding var selectedDifficulties: Set<String>
    @Binding var selectedBloomTimes: Set<String>
    @Binding var selectedTraits: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    selectedSections.removeAll()
                    selectedDifficulties.removeAll()
                    selectedBloomTimes.removeAll()
                    selectedTraits.removeAll()
                }
                .disabled(selectedSections.isEmpty && selectedDifficulties.isEmpty && selectedBloomTimes.isEmpty && selectedTraits.isEmpty)
            }

            ChipRow(title: "Section", values: sections, selection: $selectedSections)
            ChipRow(title: "Ease", values: difficulties, selection: $selectedDifficulties)
            ChipRow(title: "Bloom", values: bloomTimes, selection: $selectedBloomTimes)
            ChipRow(title: "Traits", values: traits, selection: $selectedTraits)
        }
        .padding(.top, 8)
    }
}

private struct ChipRow: View {
    let title: String
    let values: [String]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                .padding(.vertical, 1)
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

private struct PlantSection: View {
    let section: String
    let plants: [Plant]
    let layoutMode: LayoutMode

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section)
                    .font(.title3.bold())
                Text("\(plants.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if layoutMode == .grid {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(plants) { plant in
                        NavigationLink(value: plant) {
                            PlantGridCard(plant: plant)
                                .frame(height: PlantGridCard.cardHeight)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(plants) { plant in
                        NavigationLink(value: plant) {
                            PlantListRow(plant: plant)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: Plant.self) { plant in
            PlantDetailView(plant: plant)
        }
    }
}

private struct PlantGridCard: View {
    static let cardHeight: CGFloat = 338

    let plant: Plant

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                BundleImage(name: plant.imageName)
                    .frame(width: max(proxy.size.width - 20, 0), height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

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
        }
        .padding(10)
        .frame(minHeight: 142, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private struct PlantDetailView: View {
    let plant: Plant

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
