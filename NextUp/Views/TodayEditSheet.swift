import SwiftUI

/// Change today's exercises before starting: swap, remove, add or reorder, for today only
/// or saved into the routine.
struct TodayEditSheet: View {
    let day: DayType
    let gym: Gym?
    let history: History
    let overrides: [String: ClosedRange<Int>]
    /// The edited list, and whether to also change the routine.
    let onDone: ([PlannedExercise], Bool) -> Void

    @State private var items: [PlannedExercise]
    @State private var saveToRoutine = false
    @State private var adding = false
    @AppStorage("keptPairs") private var keptPairs = ""
    @Environment(\.dismiss) private var dismiss

    init(day: DayType, plan: [PlannedExercise], gym: Gym?, history: History, overrides: [String: ClosedRange<Int>],
         onDone: @escaping ([PlannedExercise], Bool) -> Void) {
        self.day = day
        self.gym = gym
        self.history = history
        self.overrides = overrides
        self.onDone = onDone
        _items = State(initialValue: plan)
    }

    var body: some View {
        let kept = Overlap.keptPairs(keptPairs)
        NavigationStack {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.exercise.id) { index, item in
                        NavigationLink {
                            swapList(for: index)
                        } label: {
                            row(item, overlap: Overlap.find(item.exercise, among: items.prefix(index).map(\.exercise), kept: kept))
                        }
                        .accessibilityIdentifier("todayRow-\(item.exercise.id)")
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        adding = true
                    } label: {
                        Label("Add an exercise", systemImage: "plus")
                    }
                    .accessibilityIdentifier("todayAdd")
                } header: {
                    HStack {
                        Text("\(day.title) · today")
                        Spacer()
                        EditButton().font(.subheadline.weight(.semibold)).textCase(nil)
                    }
                } footer: {
                    Text("Tap an exercise to swap it. Swipe left to remove one. Tap Edit to change the order.")
                }

                Section {
                    Toggle("Also change my \(day.title) routine", isOn: $saveToRoutine)
                        .accessibilityIdentifier("saveToRoutine")
                } footer: {
                    Text(saveToRoutine
                         ? "These exercises become the \(day.title) day from now on."
                         : "Only today changes. Next time the \(day.title) day is back to normal.")
                }
            }
            .navigationTitle("Today's exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(items, saveToRoutine) }
                        .bold()
                        .disabled(items.isEmpty)
                        .accessibilityIdentifier("todayDone")
                }
            }
            .sheet(isPresented: $adding) {
                AddExerciseSheet(gym: gym, excluded: Set(items.map(\.exercise.id)), current: items.map(\.exercise.id)) { exercise in
                    items.append(plan(exercise, slotID: nil))
                    adding = false
                }
            }
        }
    }

    private func row(_ item: PlannedExercise, overlap: Overlap?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.exercise.name)
            Text("\(item.exercise.muscle.title) · \(item.exercise.equipmentType.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let overlap {
                Label(overlap.message, systemImage: "exclamationmark.2")
                    .font(.footnote)
                    .foregroundStyle(Theme.amber)
                Button("Keep both") {
                    keptPairs = Overlap.keeping(item.exercise.id, overlap.other.id, in: keptPairs)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("todayKeepBoth")
            }
        }
        .padding(.vertical, 2)
    }

    /// Exercises that can stand in for the one at `index`, best match first.
    private func swapList(for index: Int) -> some View {
        let current = items[index]
        let taken = Set(items.map(\.exercise.id))
        return TodaySwapList(current: current.exercise, gymName: gym?.name,
                             options: Planner.swapOptions(for: current.exercise, gym: gym?.info, history: history, excluding: taken)) { picked in
            if items.indices.contains(index) { items[index] = plan(picked, slotID: current.slotID) }
        }
    }

    private func plan(_ exercise: ExerciseDef, slotID: String?) -> PlannedExercise {
        Planner.planExercise(exercise, slotID: slotID, gym: gym?.info, history: history, rangeOverrides: overrides)
    }
}

private struct TodaySwapList: View {
    let current: ExerciseDef
    let gymName: String?
    let options: [SwapOption]
    let onPick: (ExerciseDef) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.exercise.id) { option in
                    Button {
                        onPick(option.exercise)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(option.exercise.name).foregroundStyle(Theme.text)
                                if option.isBestMatch {
                                    Text("Best match").font(.caption.weight(.bold)).foregroundStyle(Theme.volt)
                                }
                            }
                            Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("todaySwap-\(option.exercise.id)")
                }
            } header: {
                Text("Instead of \(current.name)")
            } footer: {
                if options.isEmpty { Text("Nothing at \(gymName ?? "this gym") does the same job.") }
            }
        }
        .navigationTitle("Swap")
        .navigationBarTitleDisplayMode(.inline)
    }
}
