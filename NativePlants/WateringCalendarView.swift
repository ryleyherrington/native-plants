import SwiftUI

struct WateringCalendarView: View {
    let plants: [Plant]
    @ObservedObject var store: WateringScheduleStore
    var focusPlantID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var editorPlantID: String?

    private var plantByID: [String: Plant] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
    }

    private var dueSchedules: [WateringSchedule] {
        store.schedulesSortedByNextDate().filter { $0.isDue() }
    }

    private var upcomingSchedules: [WateringSchedule] {
        store.schedulesSortedByNextDate().filter { !$0.isDue() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.schedules.isEmpty {
                    ContentUnavailableView(
                        "No Watering Scheduled",
                        systemImage: "drop.circle",
                        description: Text("Add a plant to create a recurring watering schedule that Siri can update.")
                    )
                } else {
                    List {
                        if !dueSchedules.isEmpty {
                            Section("Due Today") {
                                ForEach(dueSchedules) { schedule in
                                    WateringScheduleRow(
                                        schedule: schedule,
                                        plant: plantByID[schedule.plantID],
                                        isDue: true,
                                        markWatered: { store.markWatered(scheduleID: schedule.id) },
                                        delete: { store.delete(scheduleID: schedule.id) }
                                    )
                                }
                            }
                        }

                        if !upcomingSchedules.isEmpty {
                            Section("Upcoming") {
                                ForEach(upcomingSchedules) { schedule in
                                    WateringScheduleRow(
                                        schedule: schedule,
                                        plant: plantByID[schedule.plantID],
                                        isDue: false,
                                        markWatered: { store.markWatered(scheduleID: schedule.id) },
                                        delete: { store.delete(scheduleID: schedule.id) }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Watering Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorPlantID = focusPlantID
                        showsEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add watering schedule")
                }
            }
            .safeAreaInset(edge: .top) {
                if !store.schedules.isEmpty {
                    WateringCalendarSummary(dueCount: dueSchedules.count, totalCount: store.schedules.count)
                }
            }
            .sheet(isPresented: $showsEditor) {
                WateringScheduleEditor(
                    plants: plants,
                    initialPlantID: editorPlantID,
                    store: store
                )
            }
            .onAppear {
                if let focusPlantID, store.schedule(for: focusPlantID) == nil {
                    editorPlantID = focusPlantID
                    showsEditor = true
                }
            }
        }
    }
}

struct PlantWateringPanel: View {
    let plant: Plant
    @ObservedObject var store: WateringScheduleStore

    @State private var showsEditor = false

    private var schedule: WateringSchedule? {
        store.schedule(for: plant.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Watering", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(Color.green)

                Spacer(minLength: 0)

                Button(schedule == nil ? "Add" : "Edit") {
                    showsEditor = true
                }
                .font(.subheadline.weight(.semibold))
            }

            if let schedule {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(WateringDateFormatter.relativeText(for: schedule))
                            .font(.title3.bold())
                        Text(WateringDateFormatter.shared.string(from: schedule.nextWateringDate()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Repeats every \(schedule.intervalDays) days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !schedule.notes.isEmpty {
                        Text(schedule.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        store.markWatered(scheduleID: schedule.id)
                    } label: {
                        Label("Mark Watered", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            } else {
                Text("Suggested cadence: every \(plant.suggestedWateringIntervalDays) days while this planting is getting established.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showsEditor) {
            WateringScheduleEditor(
                plants: [plant],
                initialPlantID: plant.id,
                store: store
            )
        }
    }
}

private struct WateringCalendarSummary: View {
    let dueCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Label(dueCount == 0 ? "Nothing due today" : "\(dueCount) due today", systemImage: "drop.fill")
                .foregroundStyle(dueCount == 0 ? Color.secondary : Color.green)

            Spacer(minLength: 0)

            Text("\(totalCount) scheduled")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct WateringScheduleRow: View {
    let schedule: WateringSchedule
    let plant: Plant?
    let isDue: Bool
    let markWatered: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let plant {
                BundleImage(name: plant.imageName)
                    .frame(width: 58, height: 58)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "leaf.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 58, height: 58)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.plantName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(WateringDateFormatter.relativeText(for: schedule))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isDue ? Color.green : Color.secondary)

                    Text(WateringDateFormatter.shared.string(from: schedule.nextWateringDate()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Every \(schedule.intervalDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !schedule.notes.isEmpty {
                    Text(schedule.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button {
                markWatered()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.green)
            .accessibilityLabel("Mark \(schedule.plantName) watered")
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct WateringScheduleEditor: View {
    let plants: [Plant]
    let initialPlantID: String?
    @ObservedObject var store: WateringScheduleStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlantID: String
    @State private var startDate = Date()
    @State private var intervalDays = 7
    @State private var notes = ""

    private var selectedPlant: Plant {
        plants.first { $0.id == selectedPlantID } ?? plants[0]
    }

    init(plants: [Plant], initialPlantID: String?, store: WateringScheduleStore) {
        self.plants = plants
        self.initialPlantID = initialPlantID
        self.store = store

        let plant = plants.first { $0.id == initialPlantID } ?? plants[0]
        let schedule = store.schedule(for: plant.id)
        _selectedPlantID = State(initialValue: plant.id)
        _startDate = State(initialValue: schedule?.startDate ?? Date())
        _intervalDays = State(initialValue: schedule?.intervalDays ?? plant.suggestedWateringIntervalDays)
        _notes = State(initialValue: schedule?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plant") {
                    Picker("Plant", selection: $selectedPlantID) {
                        ForEach(plants) { plant in
                            Text(plant.name).tag(plant.id)
                        }
                    }
                    .disabled(plants.count == 1)
                }

                Section("Schedule") {
                    DatePicker("First watering", selection: $startDate, displayedComponents: .date)

                    Stepper(value: $intervalDays, in: 1...60) {
                        Text("Every \(intervalDays) days")
                    }
                }

                Section("Notes") {
                    TextField("Water deeply during dry spells", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(store.schedule(for: selectedPlantID) == nil ? "Add Watering" : "Edit Watering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.upsertSchedule(
                            for: selectedPlant,
                            startDate: startDate,
                            intervalDays: intervalDays,
                            notes: notes
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPlantID) { _, plantID in
                guard let plant = plants.first(where: { $0.id == plantID }) else {
                    return
                }

                if let schedule = store.schedule(for: plantID) {
                    startDate = schedule.startDate
                    intervalDays = schedule.intervalDays
                    notes = schedule.notes
                } else {
                    intervalDays = plant.suggestedWateringIntervalDays
                    notes = ""
                }
            }
        }
    }
}
