import SwiftUI

/// Your routine: which days you rotate through and what each day starts with.
struct RoutineEditor: View {
    @ObservedObject private var routine = RoutineStore.shared
    @State private var pending: RoutinePreset?

    var body: some View {
        List {
            Section {
                ForEach($routine.days) { $day in
                    NavigationLink {
                        DayEditor(day: $day)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.title.isEmpty ? "Day \(day.number)" : day.title)
                            Text(summary(day)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("day-\(day.number)")
                    .deleteDisabled(routine.days.count <= 1)
                }
                .onMove { routine.days.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { routine.days.remove(atOffsets: $0) }
                Button("Add a day") { routine.addDay() }
                    .accessibilityIdentifier("addDay")
            } header: {
                Text("Your days")
            } footer: {
                Text("Days take turns in this order: finish one and the app offers the next. Tap a day to rename it or change its exercises. Tap Edit to reorder or delete days.")
            }

            Section {
                ForEach(Presets.all) { preset in
                    Button {
                        pending = preset
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(Theme.text)
                                Text(preset.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if routine.preset?.id == preset.id {
                                Image(systemName: "checkmark").foregroundStyle(Theme.volt)
                            }
                        }
                    }
                    .accessibilityIdentifier("preset-\(preset.id)")
                }
            } header: {
                Text("Ready-made routines")
            } footer: {
                Text("Choosing one replaces your days above. Workouts you already logged, your records and your weights are kept.")
            }
        }
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        .confirmationDialog("Replace your days with \(pending?.name ?? "this routine")?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Use this routine") {
                if let pending { routine.use(pending) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Your logged workouts and records are kept.")
        }
    }

    private func summary(_ day: DayType) -> String {
        let names = day.slots.compactMap { ExerciseCatalog.exercise($0)?.name }
        if names.isEmpty { return "No exercises yet" }
        return "\(names.count) exercise\(names.count == 1 ? "" : "s") · " + names.joined(separator: ", ")
    }
}

/// The Routine screen on its own, opened from Today.
struct RoutineSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RoutineEditor()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// One day: its name and the exercises it starts with.
struct DayEditor: View {
    @Binding var day: DayType
    @State private var adding = false

    var body: some View {
        List {
            Section("Name") {
                TextField("For example: Push day", text: $day.title)
                    .accessibilityIdentifier("dayName")
            }

            Section {
                ForEach(Array(day.items.enumerated()), id: \.element.key) { index, slot in
                    let exercise = ExerciseCatalog.exercise(slot.exercise)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise?.name ?? "Removed exercise")
                        if let exercise {
                            Text("\(exercise.muscle.title) · \(exercise.equipmentType.name)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { day.remove(at: index) }
                    }
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    day.move(from: from, to: destination > from ? destination - 1 : destination)
                }
                Button("Add an exercise") { adding = true }
                    .accessibilityIdentifier("addToDay")
            } header: {
                Text("Exercises")
            } footer: {
                Text("This is the order you do them in. If a gym does not have what an exercise needs, the app puts in the closest thing it has. The 20 minute version uses the first exercises for each main muscle.")
            }
        }
        .navigationTitle(day.title.isEmpty ? "Day" : day.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        .sheet(isPresented: $adding) {
            AddExerciseSheet(gym: nil, excluded: Set(day.slots)) { exercise in
                day.add(exercise.id)
                adding = false
            }
        }
    }
}
