import Foundation

struct Plant: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let scientificName: String
    let section: String
    let habit: String
    let size: String
    let difficulty: String
    let notes: String
    let sourcePage: Int
    let imageName: String
    let iconStripName: String
    let traits: [String]

    var bloomSeasons: [BloomSeason] {
        BloomSeasonParser.seasons(from: notes)
    }

    var bloomDescription: String? {
        let seasons = bloomSeasons
        guard !seasons.isEmpty else {
            return nil
        }
        return seasons.map(\.title).joined(separator: ", ")
    }

    var searchableText: String {
        ([name, scientificName, section, habit, size, difficulty, notes, bloomDescription ?? ""] + traits)
            .joined(separator: " ")
            .foldedForSearch
    }
}

enum BloomSeason: String, CaseIterable, Identifiable, Hashable {
    case spring
    case summer
    case fall
    case winter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spring:
            return "Spring"
        case .summer:
            return "Summer"
        case .fall:
            return "Fall"
        case .winter:
            return "Winter"
        }
    }
}

enum BloomSeasonParser {
    static func seasons(from notes: String) -> [BloomSeason] {
        let folded = notes.foldedForSearch
        let bloomSegments = folded
            .split(whereSeparator: { ";.,\n".contains($0) })
            .map(String.init)
            .filter(containsBloomCue)

        var seasons = Set<BloomSeason>()
        for segment in bloomSegments {
            seasons.formUnion(seasonsInBloomSegment(segment))
        }

        return BloomSeason.allCases.filter { seasons.contains($0) }
    }

    private static func containsBloomCue(_ segment: String) -> Bool {
        let cues = [
            "flower",
            "flowers",
            "bloom",
            "blooms",
            "blossom",
            "blossoms",
            "catkin",
            "catkins",
            "spikelet",
            "spikelets"
        ]
        return cues.contains { segment.contains($0) }
    }

    private static func seasonsInBloomSegment(_ segment: String) -> Set<BloomSeason> {
        var seasons = Set<BloomSeason>()

        if segment.contains("spring to fall") || segment.contains("spring through fall") {
            seasons.formUnion([.spring, .summer, .fall])
        }

        if segment.contains("spring to summer")
            || segment.contains("spring through summer")
            || segment.contains("spring and summer")
            || segment.contains("spring/summer") {
            seasons.formUnion([.spring, .summer])
        }

        if segment.contains("summer to fall")
            || segment.contains("summer through fall")
            || segment.contains("summer and fall")
            || segment.contains("summer/fall") {
            seasons.formUnion([.summer, .fall])
        }

        if segment.contains("winter to spring")
            || segment.contains("winter through spring")
            || segment.contains("winter and spring")
            || segment.contains("december through spring") {
            seasons.formUnion([.winter, .spring])
        }

        if segment.contains("spring") {
            seasons.insert(.spring)
        }
        if segment.contains("summer") {
            seasons.insert(.summer)
        }
        if segment.contains("fall") || segment.contains("autumn") {
            seasons.insert(.fall)
        }
        if segment.contains("winter") || segment.contains("december") || segment.contains("january") || segment.contains("february") {
            seasons.insert(.winter)
        }

        return seasons
    }
}

extension String {
    var foldedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum PlantCatalog {
    static let sectionOrder = [
        "Large trees",
        "Small trees",
        "Large shrubs",
        "Small and medium shrubs",
        "Perennials, annuals and ferns"
    ]

    static func load() -> [Plant] {
        guard let url = Bundle.main.url(forResource: "plants", withExtension: "json") else {
            assertionFailure("plants.json is missing from the app bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Plant].self, from: data)
        } catch {
            assertionFailure("Unable to load plants.json: \(error)")
            return []
        }
    }
}
