import SwiftUI

struct PlantFeatureIcon: Identifiable, Hashable {
    let id: String
    let symbolName: String
    let label: String
    let color: Color
}

struct PlantIconLegendGroup: Identifiable {
    let id: String
    let title: String
    let icons: [PlantFeatureIcon]
}

enum PlantIconography {
    static let legendGroups: [PlantIconLegendGroup] = [
        PlantIconLegendGroup(
            id: "plant-type",
            title: "Plant Type",
            icons: [
                PlantFeatureIcon(id: "tree", symbolName: "tree.fill", label: "Tree", color: .green),
                PlantFeatureIcon(id: "shrub", symbolName: "leaf.circle.fill", label: "Shrub", color: .green),
                PlantFeatureIcon(id: "perennial", symbolName: "camera.macro", label: "Perennial or annual", color: .green),
                PlantFeatureIcon(id: "fern", symbolName: "leaf.arrow.triangle.circlepath", label: "Fern", color: .green),
                PlantFeatureIcon(id: "grass", symbolName: "line.3.horizontal", label: "Grass", color: .green),
                PlantFeatureIcon(id: "vine", symbolName: "point.3.connected.trianglepath.dotted", label: "Vine", color: .green)
            ]
        ),
        PlantIconLegendGroup(
            id: "foliage",
            title: "Foliage",
            icons: [
                PlantFeatureIcon(id: "evergreen", symbolName: "leaf.fill", label: "Evergreen", color: .green),
                PlantFeatureIcon(id: "deciduous", symbolName: "leaf", label: "Deciduous", color: .orange),
                PlantFeatureIcon(id: "conifer", symbolName: "tree.fill", label: "Conifer", color: .green),
                PlantFeatureIcon(id: "groundcover", symbolName: "arrow.left.and.right", label: "Groundcover", color: .green)
            ]
        ),
        PlantIconLegendGroup(
            id: "site",
            title: "Site Conditions",
            icons: [
                PlantFeatureIcon(id: "rain-garden", symbolName: "cloud.rain.fill", label: "Rain garden", color: .blue),
                PlantFeatureIcon(id: "wetland", symbolName: "drop.fill", label: "Wetland or riparian", color: .blue),
                PlantFeatureIcon(id: "drought", symbolName: "sun.max.fill", label: "Drought tolerant", color: .yellow),
                PlantFeatureIcon(id: "well-drained", symbolName: "drop.circle.fill", label: "Well-drained soil", color: .brown),
                PlantFeatureIcon(id: "rock", symbolName: "mountain.2.fill", label: "Rock garden", color: .gray),
                PlantFeatureIcon(id: "woodland", symbolName: "tree.circle.fill", label: "Woodland garden", color: .green),
                PlantFeatureIcon(id: "erosion", symbolName: "shield.lefthalf.filled", label: "Erosion control", color: .green)
            ]
        ),
        PlantIconLegendGroup(
            id: "value",
            title: "Garden Value",
            icons: [
                PlantFeatureIcon(id: "edible", symbolName: "takeoutbag.and.cup.and.straw.fill", label: "Edible fruit", color: .purple),
                PlantFeatureIcon(id: "wildlife", symbolName: "pawprint.fill", label: "Wildlife value", color: .brown),
                PlantFeatureIcon(id: "spreads", symbolName: "point.3.connected.trianglepath.dotted", label: "Spreads", color: .green)
            ]
        ),
        PlantIconLegendGroup(
            id: "bloom",
            title: "Bloom",
            icons: BloomSeason.allCases.map { season in
                icon(forBloomSeason: season)
            }
        ),
        PlantIconLegendGroup(
            id: "ease",
            title: "Ease",
            icons: [
                PlantFeatureIcon(id: "easy", symbolName: "checkmark.circle.fill", label: "Easy to grow", color: .green),
                PlantFeatureIcon(id: "moderate", symbolName: "exclamationmark.triangle.fill", label: "Moderately hard to grow", color: .orange)
            ]
        )
    ]

    static func icons(for plant: Plant) -> [PlantFeatureIcon] {
        var icons: [PlantFeatureIcon] = []
        let haystack = ([plant.section, plant.habit, plant.notes] + plant.traits)
            .joined(separator: " ")
            .foldedForSearch

        addPrimaryIcon(for: plant, to: &icons)
        plant.bloomSeasons.forEach { season in
            icons.append(icon(forBloomSeason: season))
        }
        add("Evergreen", symbol: "leaf.fill", color: .green, when: haystack.contains("evergreen"), to: &icons)
        add("Deciduous", symbol: "leaf", color: .orange, when: haystack.contains("deciduous"), to: &icons)
        add("Conifer", symbol: "tree.fill", color: .green, when: haystack.contains("conifer"), to: &icons)
        add("Groundcover", symbol: "arrow.left.and.right", color: .green, when: haystack.contains("groundcover"), to: &icons)
        add("Rain garden", symbol: "cloud.rain.fill", color: .blue, when: haystack.contains("rain garden"), to: &icons)
        add("Wetland or riparian", symbol: "drop.fill", color: .blue, when: haystack.contains("wetland") || haystack.contains("riparian"), to: &icons)
        add("Drought tolerant", symbol: "sun.max.fill", color: .yellow, when: haystack.contains("drought"), to: &icons)
        add("Well-drained soil", symbol: "drop.circle.fill", color: .brown, when: haystack.contains("well-drained"), to: &icons)
        add("Rock garden", symbol: "mountain.2.fill", color: .gray, when: haystack.contains("rock garden"), to: &icons)
        add("Woodland garden", symbol: "tree.circle.fill", color: .green, when: haystack.contains("woodland"), to: &icons)
        add("Edible fruit", symbol: "takeoutbag.and.cup.and.straw.fill", color: .purple, when: haystack.contains("edible"), to: &icons)
        add("Wildlife value", symbol: "pawprint.fill", color: .brown, when: haystack.contains("wildlife"), to: &icons)
        add("Spreads", symbol: "point.3.connected.trianglepath.dotted", color: .green, when: haystack.contains("spreads"), to: &icons)
        add("Erosion control", symbol: "shield.lefthalf.filled", color: .green, when: haystack.contains("erosion control"), to: &icons)

        return icons
    }

    static func icon(forTrait trait: String) -> PlantFeatureIcon {
        let folded = trait.foldedForSearch
        if folded == BloomSeason.spring.title.foldedForSearch {
            return icon(forBloomSeason: .spring)
        } else if folded == BloomSeason.summer.title.foldedForSearch {
            return icon(forBloomSeason: .summer)
        } else if folded == BloomSeason.fall.title.foldedForSearch {
            return icon(forBloomSeason: .fall)
        } else if folded == BloomSeason.winter.title.foldedForSearch {
            return icon(forBloomSeason: .winter)
        } else if folded.contains("tree") {
            return PlantFeatureIcon(id: trait, symbolName: "tree.fill", label: trait, color: .green)
        } else if folded.contains("shrub") {
            return PlantFeatureIcon(id: trait, symbolName: "leaf.circle.fill", label: trait, color: .green)
        } else if folded.contains("perennial") || folded.contains("annual") {
            return PlantFeatureIcon(id: trait, symbolName: "camera.macro", label: trait, color: .green)
        } else if folded.contains("easy to grow") {
            return PlantFeatureIcon(id: trait, symbolName: "checkmark.circle.fill", label: trait, color: .green)
        } else if folded.contains("hard to grow") {
            return PlantFeatureIcon(id: trait, symbolName: "exclamationmark.triangle.fill", label: trait, color: .orange)
        } else if folded.contains("evergreen") {
            return PlantFeatureIcon(id: trait, symbolName: "leaf.fill", label: trait, color: .green)
        } else if folded.contains("deciduous") {
            return PlantFeatureIcon(id: trait, symbolName: "leaf", label: trait, color: .orange)
        } else if folded.contains("conifer") {
            return PlantFeatureIcon(id: trait, symbolName: "tree.fill", label: trait, color: .green)
        } else if folded.contains("rain") || folded.contains("wetland") || folded.contains("riparian") {
            return PlantFeatureIcon(id: trait, symbolName: "drop.fill", label: trait, color: .blue)
        } else if folded.contains("well-drained") {
            return PlantFeatureIcon(id: trait, symbolName: "drop.circle.fill", label: trait, color: .brown)
        } else if folded.contains("drought") {
            return PlantFeatureIcon(id: trait, symbolName: "sun.max.fill", label: trait, color: .yellow)
        } else if folded.contains("rock") {
            return PlantFeatureIcon(id: trait, symbolName: "mountain.2.fill", label: trait, color: .gray)
        } else if folded.contains("woodland") {
            return PlantFeatureIcon(id: trait, symbolName: "tree.circle.fill", label: trait, color: .green)
        } else if folded.contains("edible") {
            return PlantFeatureIcon(id: trait, symbolName: "takeoutbag.and.cup.and.straw.fill", label: trait, color: .purple)
        } else if folded.contains("wildlife") {
            return PlantFeatureIcon(id: trait, symbolName: "pawprint.fill", label: trait, color: .brown)
        } else if folded.contains("spreads") {
            return PlantFeatureIcon(id: trait, symbolName: "point.3.connected.trianglepath.dotted", label: trait, color: .green)
        } else if folded.contains("erosion") {
            return PlantFeatureIcon(id: trait, symbolName: "shield.lefthalf.filled", label: trait, color: .green)
        } else if folded.contains("grass") {
            return PlantFeatureIcon(id: trait, symbolName: "line.3.horizontal", label: trait, color: .green)
        } else if folded.contains("fern") {
            return PlantFeatureIcon(id: trait, symbolName: "leaf.arrow.triangle.circlepath", label: trait, color: .green)
        } else {
            return PlantFeatureIcon(id: trait, symbolName: "leaf", label: trait, color: .green)
        }
    }

    static func icon(forBloomSeason season: BloomSeason) -> PlantFeatureIcon {
        switch season {
        case .spring:
            return PlantFeatureIcon(id: season.id, symbolName: "camera.macro", label: season.title, color: .pink)
        case .summer:
            return PlantFeatureIcon(id: season.id, symbolName: "sun.max.fill", label: season.title, color: .yellow)
        case .fall:
            return PlantFeatureIcon(id: season.id, symbolName: "leaf.fill", label: season.title, color: .orange)
        case .winter:
            return PlantFeatureIcon(id: season.id, symbolName: "snowflake", label: season.title, color: .blue)
        }
    }

    private static func addPrimaryIcon(for plant: Plant, to icons: inout [PlantFeatureIcon]) {
        let text = "\(plant.section) \(plant.habit)".foldedForSearch
        if text.contains("tree") {
            add("Tree", symbol: "tree.fill", color: .green, when: true, to: &icons)
        } else if text.contains("shrub") {
            add("Shrub", symbol: "leaf.circle.fill", color: .green, when: true, to: &icons)
        } else if text.contains("fern") {
            add("Fern", symbol: "leaf.arrow.triangle.circlepath", color: .green, when: true, to: &icons)
        } else if text.contains("grass") {
            add("Grass", symbol: "line.3.horizontal", color: .green, when: true, to: &icons)
        } else if text.contains("vine") {
            add("Vine", symbol: "point.3.connected.trianglepath.dotted", color: .green, when: true, to: &icons)
        } else {
            add("Perennial", symbol: "camera.macro", color: .green, when: true, to: &icons)
        }
    }

    private static func add(
        _ label: String,
        symbol: String,
        color: Color,
        when condition: Bool,
        to icons: inout [PlantFeatureIcon]
    ) {
        guard condition, !icons.contains(where: { $0.label == label }) else {
            return
        }
        icons.append(PlantFeatureIcon(id: label, symbolName: symbol, label: label, color: color))
    }
}
