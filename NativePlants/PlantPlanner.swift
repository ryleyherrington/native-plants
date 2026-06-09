import Foundation
import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

enum PlantPlannerBackend: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case appleIntelligence = "Apple Intelligence"
    case catalog = "Catalog"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .automatic:
            return "wand.and.sparkles"
        case .appleIntelligence:
            return "sparkles"
        case .catalog:
            return "leaf.fill"
        }
    }
}

enum PlannerMessageRole {
    case user
    case assistant
}

struct PlannerPhoto: Identifiable, Equatable {
    let id = UUID()
    let data: Data
}

struct PlannerMessage: Identifiable, Equatable {
    let id = UUID()
    let role: PlannerMessageRole
    let text: String
    var source: PlantPlannerResponseSource?
    var recommendations: [Plant] = []
    var photo: PlannerPhoto?
}

struct PlannerHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let question: String
    let response: String
    let source: PlantPlannerResponseSource
    let recommendations: [Plant]
    let messageID: UUID
    let hasPhoto: Bool
}

enum PlantPlannerResponseSource: String, Equatable {
    case appleIntelligence = "Apple Intelligence"
    case catalog = "Catalog"

    var symbolName: String {
        switch self {
        case .appleIntelligence:
            return "sparkles"
        case .catalog:
            return "leaf.fill"
        }
    }
}

struct PlantPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    let plants: [Plant]
    let closeAction: (() -> Void)?

    @State private var messages: [PlannerMessage]
    @State private var draft = ""
    @State private var backend = PlantPlannerBackend.automatic
    @State private var isSending = false
    @State private var runtimeStatus = PlantPlannerRuntimeStatus.current
    @State private var history: [PlannerHistoryItem] = []
    @State private var showsHistory = false
    @State private var scrollTarget: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhoto: PlannerPhoto?
    @State private var photoLoadError: String?

    private let suggestions = [
        "8 by 6 ft bed, part shade, moist soil, wildlife friendly",
        "Narrow sunny strip, dry soil, low maintenance",
        "Small shady corner with spring blooms"
    ]

    init(plants: [Plant], closeAction: (() -> Void)? = nil) {
        self.plants = plants
        self.closeAction = closeAction
        _messages = State(initialValue: [
            PlannerMessage(
                role: .assistant,
                text: "Share the space, light, soil, and what you want from it. I will suggest Oregon native plants from this catalog.",
                source: .catalog
            )
        ])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlannerStatusBar(status: runtimeStatus, backend: backend)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                PlannerMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if isSending {
                                PlannerThinkingBubble(backend: backend)
                                    .id("thinking")
                            }

                            if messages.count == 1 {
                                PlannerSuggestionRow(suggestions: suggestions) { suggestion in
                                    send(suggestion)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isSending) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else {
                            return
                        }
                        withAnimation(.snappy(duration: 0.24)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }

                PlannerComposer(
                    draft: $draft,
                    selectedPhoto: $selectedPhoto,
                    selectedPhotoItem: $selectedPhotoItem,
                    photoLoadError: photoLoadError,
                    isSending: isSending,
                    isInputFocused: $isInputFocused,
                    send: { send(draft) }
                )
            }
            .navigationTitle("Plant Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Planner", selection: $backend) {
                            ForEach(PlantPlannerBackend.allCases) { option in
                                Label(option.rawValue, systemImage: option.symbolName)
                                    .tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: backend.symbolName)
                    }
                    .accessibilityLabel("Planner source")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showsHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(history.isEmpty)
                    .accessibilityLabel("Show planner history")

                    Button("Done") {
                        close()
                    }
                }
            }
            .sheet(isPresented: $showsHistory) {
                PlannerHistoryView(items: history) { item in
                    showsHistory = false
                    scrollTarget = item.messageID
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                loadSelectedPhoto(item)
            }
            .task {
                runtimeStatus = PlantPlannerRuntimeStatus.current
            }
        }
    }

    private func close() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        selectedPhoto = nil
                        photoLoadError = "That photo could not be loaded."
                    }
                    return
                }

                await MainActor.run {
                    selectedPhoto = PlannerPhoto(data: data)
                    photoLoadError = nil
                }
            } catch {
                await MainActor.run {
                    selectedPhoto = nil
                    photoLoadError = "That photo could not be loaded."
                }
            }
        }
    }

    private func send(_ rawText: String) {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedPhoto = selectedPhoto
        guard (!trimmedText.isEmpty || attachedPhoto != nil), !isSending else {
            return
        }

        let text = trimmedText.isEmpty ? "Use the attached yard photo to help plan this space." : trimmedText
        draft = ""
        selectedPhoto = nil
        selectedPhotoItem = nil
        photoLoadError = nil
        isInputFocused = false
        isSending = true
        let userMessage = PlannerMessage(role: .user, text: text, photo: attachedPhoto)
        messages.append(userMessage)
        let conversation = messages
        let selectedBackend = backend
        let catalog = plants

        Task {
            let response = await PlantPlannerResponder.response(
                for: text,
                history: conversation,
                plants: catalog,
                backend: selectedBackend,
                photo: attachedPhoto
            )

            await MainActor.run {
                runtimeStatus = PlantPlannerRuntimeStatus.current
                let assistantMessage = PlannerMessage(
                    role: .assistant,
                    text: response.text,
                    source: response.source,
                    recommendations: response.recommendations
                )
                messages.append(assistantMessage)
                history.append(
                    PlannerHistoryItem(
                        question: text,
                        response: response.text,
                        source: response.source,
                        recommendations: response.recommendations,
                        messageID: userMessage.id,
                        hasPhoto: attachedPhoto != nil
                    )
                )
                isSending = false
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.snappy(duration: 0.2)) {
                if isSending {
                    proxy.scrollTo("thinking", anchor: .bottom)
                } else if let lastID = messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

private struct PlannerHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [PlannerHistoryItem]
    let select: (PlannerHistoryItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No questions yet")
                            .font(.headline)
                        Text("Questions you ask in this planner session will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(items.reversed()) { item in
                        Button {
                            select(item)
                        } label: {
                            PlannerHistoryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Planner History")
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

private struct PlannerHistoryRow: View {
    let item: PlannerHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.source.rawValue, systemImage: item.source.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if item.hasPhoto {
                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.response)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !item.recommendations.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.recommendations.prefix(3)) { plant in
                        Text(plant.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.16))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PlannerStatusBar: View {
    let status: PlantPlannerRuntimeStatus
    let backend: PlantPlannerBackend

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.isAvailable ? Color.green : Color.orange)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var statusText: String {
        if backend == .catalog {
            return "Using catalog ranking."
        }
        return status.message
    }
}

private struct PlannerMessageBubble: View {
    let message: PlannerMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if let source = message.source, !isUser {
                    Label(source.rawValue, systemImage: source.symbolName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let photo = message.photo {
                    PlannerPhotoThumbnail(photo: photo)
                        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.recommendations.isEmpty {
                    PlannerRecommendationStrip(plants: message.recommendations)
                }
            }
            .padding(12)
            .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
            .background(isUser ? Color.green : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !isUser {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct PlannerPhotoThumbnail: View {
    let photo: PlannerPhoto
    var width: CGFloat = 210
    var height: CGFloat = 138

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: photo.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Label("Photo attached", systemImage: "photo")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlannerRecommendationStrip: View {
    let plants: [Plant]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plants.prefix(5)) { plant in
                    VStack(alignment: .leading, spacing: 5) {
                        BundleImage(name: plant.imageName)
                            .frame(width: 132, height: 76)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(plant.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(plant.size)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let bloom = plant.bloomDescription {
                            Label(bloom, systemImage: "camera.macro")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                    .padding(8)
                    .frame(width: 148, height: 158, alignment: .topLeading)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PlannerThinkingBubble: View {
    let backend: PlantPlannerBackend

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Label(backend == .catalog ? "Catalog" : "Planning", systemImage: backend.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ProgressView()
                    .controlSize(.small)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 36)
        }
    }
}

private struct PlannerSuggestionRow: View {
    let suggestions: [String]
    let action: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        action(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(width: 184, height: 54, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PlannerComposer: View {
    @Binding var draft: String
    @Binding var selectedPhoto: PlannerPhoto?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let photoLoadError: String?
    let isSending: Bool
    var isInputFocused: FocusState<Bool>.Binding
    let send: () -> Void

    private var canSend: Bool {
        !isSending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPhoto != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedPhoto {
                HStack(spacing: 10) {
                    PlannerPhotoThumbnail(photo: selectedPhoto, width: 86, height: 58)

                    Label("Yard photo attached", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        self.selectedPhoto = nil
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached photo")
                }
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let photoLoadError {
                Label(photoLoadError, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: selectedPhoto == nil ? "photo.badge.plus" : "photo.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 32, height: 32)
                }
                .disabled(isSending)
                .accessibilityLabel(selectedPhoto == nil ? "Attach yard photo" : "Replace yard photo")

                TextField("Space, light, soil, goals", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused(isInputFocused)
                    .disabled(isSending)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

struct PlantPlannerResponse {
    let text: String
    let source: PlantPlannerResponseSource
    let recommendations: [Plant]
}

struct PlantPlannerGeneratedPlan {
    let text: String
    let plantIDs: [String]
}

private struct PlantPlannerGeneratedContent: Decodable {
    let profileSummary: String
    let layoutStrategy: String
    let recommendationIDs: [String]
    let fitReasons: [String]
    let cautions: [String]
    let followUpQuestion: String?
}

enum PlantPlannerResponder {
    static func response(
        for question: String,
        history: [PlannerMessage],
        plants: [Plant],
        backend: PlantPlannerBackend,
        photo: PlannerPhoto?
    ) async -> PlantPlannerResponse {
        if backend != .catalog,
           let aiPlan = await PlantPlannerAppleIntelligence.response(
            for: question,
            history: history,
            plants: plants,
            hasPhoto: photo != nil
           ) {
            let recommendations = aiPlan.plantIDs.compactMap { id in
                plants.first { $0.id == id }
            }

            return PlantPlannerResponse(
                text: aiPlan.text,
                source: .appleIntelligence,
                recommendations: recommendations.isEmpty
                    ? PlantPlanningMatcher.rankedPlants(for: question, in: plants, limit: 5)
                    : recommendations
            )
        }

        let localResponse = PlantPlanningMatcher.localResponse(for: question, plants: plants, hasPhoto: photo != nil)
        return PlantPlannerResponse(
            text: localResponse.text,
            source: .catalog,
            recommendations: localResponse.plants
        )
    }
}

struct PlantPlannerRuntimeStatus: Equatable {
    let isAvailable: Bool
    let message: String
    let symbolName: String

    static var current: PlantPlannerRuntimeStatus {
        PlantPlannerAppleIntelligence.status
    }
}

enum PlantPlannerAppleIntelligence {
    static var status: PlantPlannerRuntimeStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return PlantPlannerRuntimeStatus(
                    isAvailable: true,
                    message: "Apple Intelligence is available.",
                    symbolName: "sparkles"
                )
            case .unavailable(.appleIntelligenceNotEnabled):
                return PlantPlannerRuntimeStatus(
                    isAvailable: false,
                    message: "Apple Intelligence is not enabled, so the catalog planner will answer.",
                    symbolName: "sparkles"
                )
            case .unavailable(.deviceNotEligible):
                return PlantPlannerRuntimeStatus(
                    isAvailable: false,
                    message: "This device is not eligible for Apple Intelligence, so the catalog planner will answer.",
                    symbolName: "iphone.slash"
                )
            case .unavailable(.modelNotReady):
                return PlantPlannerRuntimeStatus(
                    isAvailable: false,
                    message: "The Apple Intelligence model is not ready yet, so the catalog planner will answer.",
                    symbolName: "clock"
                )
            @unknown default:
                return PlantPlannerRuntimeStatus(
                    isAvailable: false,
                    message: "Apple Intelligence is not available right now, so the catalog planner will answer.",
                    symbolName: "sparkles"
                )
            }
        }
        #endif

        return PlantPlannerRuntimeStatus(
            isAvailable: false,
            message: "Apple Intelligence requires iOS 26. The catalog planner will answer here.",
            symbolName: "leaf.fill"
        )
    }

    static func response(
        for question: String,
        history: [PlannerMessage],
        plants: [Plant],
        hasPhoto: Bool
    ) async -> PlantPlannerGeneratedPlan? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return nil
            }

            let candidates = PlantPlanningMatcher.rankedPlants(for: question, in: plants, limit: 32)
            guard !candidates.isEmpty else {
                return nil
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: Instructions(
                        """
                        You are a practical Oregon native plant planning assistant.
                        Use the current request and recent conversation to infer a site profile.
                        Recommend only plants from the candidate catalog and return plant IDs exactly as given.
                        Prefer concrete layouts, mature size fit, bloom timing, ease, and site-condition tradeoffs.
                        Ask one focused follow-up question only when a missing detail could materially change the plan.
                        Keep every generated field concise enough to read on an iPhone.
                        """
                    )
                )

                let schema = try planSchema(for: candidates)
                let response = try await session.respond(
                    to: prompt(for: question, history: history, candidates: candidates, hasPhoto: hasPhoto),
                    schema: schema,
                    options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 650)
                )
                return try generatedPlan(from: response.content, candidates: candidates)
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func planSchema(for candidates: [Plant]) throws -> GenerationSchema {
        let plantIDSchema = DynamicGenerationSchema(
            name: "PlantID",
            description: "A plant ID from the candidate catalog.",
            anyOf: candidates.map(\.id)
        )
        let recommendationIDsSchema = DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(referenceTo: "PlantID"),
            minimumElements: 3,
            maximumElements: 5
        )
        let shortTextArraySchema = DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self),
            minimumElements: 0,
            maximumElements: 5
        )
        let fitReasonsSchema = DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self),
            minimumElements: 3,
            maximumElements: 5
        )
        let root = DynamicGenerationSchema(
            name: "PlantPlan",
            description: "A concise Oregon native planting plan using only candidate catalog IDs.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "profileSummary",
                    description: "A one-sentence summary of the inferred space, light, water, and goals.",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
                DynamicGenerationSchema.Property(
                    name: "layoutStrategy",
                    description: "A one- or two-sentence planting layout strategy.",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
                DynamicGenerationSchema.Property(
                    name: "recommendationIDs",
                    description: "Three to five unique plant IDs from the candidate catalog, ordered by fit.",
                    schema: recommendationIDsSchema
                ),
                DynamicGenerationSchema.Property(
                    name: "fitReasons",
                    description: "A concise fit reason for each recommended plant, in the same order as recommendationIDs.",
                    schema: fitReasonsSchema
                ),
                DynamicGenerationSchema.Property(
                    name: "cautions",
                    description: "Short warnings about mature size, water, light, maintenance, or uncertainty.",
                    schema: shortTextArraySchema
                ),
                DynamicGenerationSchema.Property(
                    name: "followUpQuestion",
                    description: "One focused follow-up question if a missing site detail could change the recommendations.",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: true
                )
            ]
        )

        return try GenerationSchema(root: root, dependencies: [plantIDSchema])
    }

    @available(iOS 26.0, *)
    private static func generatedPlan(
        from content: GeneratedContent,
        candidates: [Plant]
    ) throws -> PlantPlannerGeneratedPlan {
        let data = Data(content.jsonString.utf8)
        let generatedContent = try JSONDecoder().decode(PlantPlannerGeneratedContent.self, from: data)
        let plantIDs = uniquePlantIDs(
            generatedContent.recommendationIDs,
            allowedIDs: Set(candidates.map(\.id))
        )
        let text = formattedPlanText(
            content: generatedContent,
            candidates: candidates,
            plantIDs: plantIDs
        )
        return PlantPlannerGeneratedPlan(text: text, plantIDs: plantIDs)
    }
    #endif

    private static func prompt(
        for question: String,
        history: [PlannerMessage],
        candidates: [Plant],
        hasPhoto: Bool
    ) -> String {
        let recentHistory = history.dropLast().suffix(6).map { message in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role): \(message.text)"
        }
        .joined(separator: "\n")

        let catalog = candidates.map { plant in
            let bloom = plant.bloomDescription ?? "not listed"
            let traits = plant.traits.isEmpty ? "none listed" : plant.traits.joined(separator: ", ")
            return "- id: \(plant.id); \(plant.name) (\(plant.scientificName)): \(plant.section); \(plant.size); \(plant.difficulty); bloom: \(bloom); traits: \(traits); notes: \(plant.notes)"
        }
        .joined(separator: "\n")
        let photoContext = hasPhoto
            ? "A yard photo or sketch is attached to this turn as user-visible context. Do not infer exact image details unless they are also described in text. If visible layout, light, water, dimensions, or existing plants matter and are not described, use followUpQuestion to ask for that detail."
            : "No yard photo is attached to this turn."

        return """
        Recent conversation:
        \(recentHistory.isEmpty ? "None" : recentHistory)

        User request:
        \(question)

        Photo context:
        \(photoContext)

        Candidate plants from the app catalog:
        \(catalog)

        Generate a structured planting plan. Use only the listed id values for recommendationIDs, and do not repeat an id. Keep cautions practical and include followUpQuestion only when the missing answer would change plant selection or placement.
        """
    }

    private static func formattedPlanText(
        content: PlantPlannerGeneratedContent,
        candidates: [Plant],
        plantIDs: [String]
    ) -> String {
        let plantByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var sections: [String] = []

        if let profileSummary = cleanText(content.profileSummary) {
            sections.append("Profile: \(profileSummary)")
        }

        if let layoutStrategy = cleanText(content.layoutStrategy) {
            sections.append("Layout: \(layoutStrategy)")
        }

        let plantLines = plantIDs.enumerated().compactMap { index, plantID -> String? in
            guard let plant = plantByID[plantID] else {
                return nil
            }
            let reason = content.fitReasons.indices.contains(index)
                ? cleanText(content.fitReasons[index])
                : nil
            return "\(index + 1). \(plant.name) - \(reason ?? plant.habit)"
        }
        if !plantLines.isEmpty {
            sections.append("Plants:\n\(plantLines.joined(separator: "\n"))")
        }

        let cautions = content.cautions.compactMap(cleanText)
        if !cautions.isEmpty {
            sections.append("Watch: \(cautions.joined(separator: " "))")
        }

        if let followUpQuestion = cleanOptionalQuestion(content.followUpQuestion) {
            sections.append("Follow-up: \(followUpQuestion)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func cleanText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanOptionalQuestion(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let folded = trimmed.foldedForSearch
        let emptyAnswers = ["none", "n/a", "not needed", "no follow-up needed", "no follow up needed"]
        return emptyAnswers.contains(folded) ? nil : trimmed
    }

    private static func uniquePlantIDs(_ ids: [String], allowedIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in
            guard allowedIDs.contains(id), !seen.contains(id) else {
                return false
            }
            seen.insert(id)
            return true
        }
    }
}

enum PlantPlanningMatcher {
    struct LocalResponse {
        let text: String
        let plants: [Plant]
    }

    private struct ScoredPlant {
        let plant: Plant
        let score: Int
        let reasons: [String]
    }

    static func localResponse(for question: String, plants: [Plant], hasPhoto: Bool = false) -> LocalResponse {
        if hasPhoto && question.foldedForSearch.contains("attached yard photo") {
            return LocalResponse(
                text: "I have the yard photo attached as context, but I still need a few details in text before I can make a reliable catalog plan. Tell me the bed dimensions, approximate sun exposure, summer water, and whether you want flowers, screening, wildlife value, or low maintenance.",
                plants: []
            )
        }

        let scored = scoredPlants(for: question, in: plants)
        let recommendations = Array(scored.prefix(5))
        let recommendedPlants = recommendations.map(\.plant)

        guard !recommendations.isEmpty else {
            return LocalResponse(
                text: "I could not find a confident match in the catalog. Try adding the space size, light, soil moisture, and whether you want flowers, screening, wildlife value, or low maintenance.",
                plants: []
            )
        }

        let profile = PlanningProfile(question: question)
        var lines: [String] = []

        if let spaceSummary = profile.spaceSummary {
            lines.append("For \(spaceSummary), I would keep the plan layered and avoid plants that outgrow the narrowest side.")
        } else {
            lines.append("I would start with a layered native planting and confirm the exact mature spread before buying.")
        }

        for (index, item) in recommendations.enumerated() {
            let plant = item.plant
            let reason = item.reasons.prefix(3).joined(separator: ", ")
            let bloom = plant.bloomDescription.map { " Bloom: \($0)." } ?? ""
            lines.append("\(index + 1). \(plant.name) - \(reason.isEmpty ? plant.habit : reason). \(plant.size). \(plant.difficulty).\(bloom)")
        }

        if profile.dimensions == nil {
            lines.append("A tighter plan needs the bed dimensions, hours of sun, and whether the soil stays dry, average, or wet.")
        } else if profile.lightSignals.isEmpty || profile.waterSignals.isEmpty {
            lines.append("I would still verify light and summer water before final placement.")
        }

        return LocalResponse(text: lines.joined(separator: "\n\n"), plants: recommendedPlants)
    }

    static func rankedPlants(for question: String, in plants: [Plant], limit: Int) -> [Plant] {
        Array(scoredPlants(for: question, in: plants).prefix(limit).map(\.plant))
    }

    static func mentionedPlants(in text: String, plants: [Plant]) -> [Plant] {
        let folded = text.foldedForSearch
        return plants.filter { plant in
            folded.contains(plant.name.foldedForSearch)
        }
    }

    private static func scoredPlants(for question: String, in plants: [Plant]) -> [ScoredPlant] {
        let profile = PlanningProfile(question: question)
        return plants
            .map { plant in
                score(plant, profile: profile)
            }
            .filter { $0.score > -8 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                let lhsSection = PlantCatalog.sectionOrder.firstIndex(of: lhs.plant.section) ?? Int.max
                let rhsSection = PlantCatalog.sectionOrder.firstIndex(of: rhs.plant.section) ?? Int.max
                if lhsSection != rhsSection {
                    return lhsSection > rhsSection
                }
                return lhs.plant.name < rhs.plant.name
            }
    }

    private static func score(_ plant: Plant, profile: PlanningProfile) -> ScoredPlant {
        let haystack = ([plant.section, plant.habit, plant.size, plant.difficulty, plant.notes] + plant.traits)
            .joined(separator: " ")
            .foldedForSearch
        var score = 0
        var reasons: [String] = []

        if profile.wantsEasy, plant.difficulty.foldedForSearch.contains("easy") {
            score += 3
            reasons.append("easy to grow")
        }

        if profile.wantsSmallSpace {
            if plant.section == "Perennials, annuals and ferns" || plant.section == "Small and medium shrubs" {
                score += 5
                reasons.append("good scale for a smaller space")
            } else if plant.section == "Large trees" {
                score -= 9
            }
        }

        if profile.wantsTree {
            if plant.section.contains("trees") {
                score += 4
                reasons.append("tree form")
            } else {
                score -= 2
            }
        }

        if profile.wantsScreening {
            if haystack.contains("evergreen") || haystack.contains("shrub") || haystack.contains("wind break") {
                score += 4
                reasons.append("useful for screening")
            }
        }

        if let narrowSide = profile.dimensions.map({ min($0.width, $0.depth) }),
           let matureWidth = matureWidth(from: plant.size) {
            if matureWidth <= max(narrowSide * 1.25, narrowSide + 2) {
                score += 5
                reasons.append("mature width fits the space")
            } else if matureWidth > max(narrowSide * 2, narrowSide + 8) {
                score -= 8
            }
        }

        for signal in profile.lightSignals {
            if signal.matches(haystack: haystack) {
                score += 4
                reasons.append(signal.reason)
            }
        }

        for signal in profile.waterSignals {
            if signal.matches(haystack: haystack) {
                score += 4
                reasons.append(signal.reason)
            }
        }

        for signal in profile.goalSignals {
            if signal.matches(haystack: haystack) {
                score += 3
                reasons.append(signal.reason)
            }
        }

        for season in profile.bloomSeasons where plant.bloomSeasons.contains(season) {
            score += 3
            reasons.append("\(season.title.lowercased()) bloom")
        }

        if reasons.isEmpty {
            reasons.append(plant.habit)
        }

        return ScoredPlant(plant: plant, score: score, reasons: unique(reasons))
    }

    private static func matureWidth(from size: String) -> Double? {
        guard let wideRange = size.range(of: "wide", options: [.caseInsensitive]) else {
            return nil
        }
        let beforeWide = String(size[..<wideRange.lowerBound])
        let lastSegment = beforeWide.components(separatedBy: ",").last ?? beforeWide
        let matches = lastSegment.matches(of: /[0-9]+(?:\.[0-9]+)?/)
        let values = matches.compactMap { Double(String($0.output)) }
        return values.max()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            if seen.contains(value) {
                return false
            }
            seen.insert(value)
            return true
        }
    }
}

private struct PlanningProfile {
    struct Dimensions {
        let width: Double
        let depth: Double
    }

    let question: String
    let foldedQuestion: String
    let dimensions: Dimensions?
    let lightSignals: [PlanningSignal]
    let waterSignals: [PlanningSignal]
    let goalSignals: [PlanningSignal]
    let bloomSeasons: [BloomSeason]
    let wantsSmallSpace: Bool
    let wantsTree: Bool
    let wantsScreening: Bool
    let wantsEasy: Bool

    init(question: String) {
        self.question = question
        self.foldedQuestion = question.foldedForSearch
        self.dimensions = Self.parseDimensions(from: question.foldedForSearch)
        self.lightSignals = Self.lightSignals(from: question.foldedForSearch)
        self.waterSignals = Self.waterSignals(from: question.foldedForSearch)
        self.goalSignals = Self.goalSignals(from: question.foldedForSearch)
        self.bloomSeasons = BloomSeason.allCases.filter { season in
            question.foldedForSearch.contains(season.title.foldedForSearch)
        }
        self.wantsSmallSpace = Self.containsAny(
            ["small", "narrow", "strip", "curb", "hellstrip", "container", "patio", "corner", "bed"],
            in: question.foldedForSearch
        )
        self.wantsTree = Self.containsAny(["tree", "canopy", "shade tree"], in: question.foldedForSearch)
        self.wantsScreening = Self.containsAny(["screen", "privacy", "hedge", "wind break", "windbreak"], in: question.foldedForSearch)
        self.wantsEasy = Self.containsAny(["easy", "low maintenance", "simple", "beginner"], in: question.foldedForSearch)
    }

    var spaceSummary: String? {
        guard let dimensions else {
            return nil
        }
        return "\(format(dimensions.width)) by \(format(dimensions.depth)) ft"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : "\(value)"
    }

    private static func lightSignals(from text: String) -> [PlanningSignal] {
        var signals: [PlanningSignal] = []
        if containsAny(["part shade", "partial shade", "shade", "shady", "woodland"], in: text) {
            signals.append(.shade)
        }
        if containsAny(["full sun", "sunny", "sun"], in: text) {
            signals.append(.sun)
        }
        return signals
    }

    private static func waterSignals(from text: String) -> [PlanningSignal] {
        var signals: [PlanningSignal] = []
        if containsAny(["wet", "moist", "rain garden", "rain", "riparian", "flood", "bog"], in: text) {
            signals.append(.wet)
        }
        if containsAny(["dry", "drought", "low water", "xeric"], in: text) {
            signals.append(.dry)
        }
        if containsAny(["well drained", "well-drained", "drained"], in: text) {
            signals.append(.wellDrained)
        }
        return signals
    }

    private static func goalSignals(from text: String) -> [PlanningSignal] {
        var signals: [PlanningSignal] = []
        if containsAny(["wildlife", "bird", "birds", "habitat"], in: text) {
            signals.append(.wildlife)
        }
        if containsAny(["pollinator", "pollinators", "bee", "bees", "butterfly", "butterflies", "hummingbird"], in: text) {
            signals.append(.pollinator)
        }
        if containsAny(["edible", "berries", "fruit"], in: text) {
            signals.append(.edible)
        }
        if containsAny(["evergreen", "winter interest", "year round", "year-round"], in: text) {
            signals.append(.evergreen)
        }
        if containsAny(["rock", "rocky", "slope", "erosion"], in: text) {
            signals.append(.rockOrSlope)
        }
        return signals
    }

    private static func parseDimensions(from text: String) -> Dimensions? {
        let normalized = text
            .replacingOccurrences(of: "feet", with: "ft")
            .replacingOccurrences(of: "foot", with: "ft")
            .replacingOccurrences(of: "by", with: "x")
            .replacingOccurrences(of: "×", with: "x")

        guard let match = normalized.firstMatch(of: /([0-9]+(?:\.[0-9]+)?)\s*(?:ft|')?\s*x\s*([0-9]+(?:\.[0-9]+)?)/),
              let width = Double(String(match.1)),
              let depth = Double(String(match.2)) else {
            return nil
        }

        return Dimensions(width: width, depth: depth)
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

private enum PlanningSignal {
    case shade
    case sun
    case wet
    case dry
    case wellDrained
    case wildlife
    case pollinator
    case edible
    case evergreen
    case rockOrSlope

    var reason: String {
        switch self {
        case .shade:
            return "shade tolerance"
        case .sun:
            return "sun tolerance"
        case .wet:
            return "handles moist or wet sites"
        case .dry:
            return "drought or dry-summer fit"
        case .wellDrained:
            return "well-drained soil fit"
        case .wildlife:
            return "wildlife value"
        case .pollinator:
            return "flower or pollinator value"
        case .edible:
            return "edible fruit value"
        case .evergreen:
            return "evergreen structure"
        case .rockOrSlope:
            return "rock garden or erosion fit"
        }
    }

    func matches(haystack: String) -> Bool {
        switch self {
        case .shade:
            return haystack.contains("shade") || haystack.contains("woodland")
        case .sun:
            return haystack.contains("full sun") || haystack.contains("drought") || haystack.contains("rock garden")
        case .wet:
            return haystack.contains("wetland") || haystack.contains("riparian") || haystack.contains("rain garden") || haystack.contains("wet soil") || haystack.contains("flood")
        case .dry:
            return haystack.contains("drought") || haystack.contains("dry summer") || haystack.contains("well-drained") || haystack.contains("rock garden")
        case .wellDrained:
            return haystack.contains("well-drained") || haystack.contains("well- drained")
        case .wildlife:
            return haystack.contains("wildlife") || haystack.contains("habitat")
        case .pollinator:
            return haystack.contains("pollinator") || haystack.contains("butterfly") || haystack.contains("hummingbird") || haystack.contains("flower")
        case .edible:
            return haystack.contains("edible") || haystack.contains("fruit")
        case .evergreen:
            return haystack.contains("evergreen")
        case .rockOrSlope:
            return haystack.contains("rock garden") || haystack.contains("erosion")
        }
    }
}
