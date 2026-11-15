import SwiftUI
import SwiftData

/// One-tap swap to an equivalent exercise when a machine is taken or missing.
struct SwapSheet: View {
    let entry: ExerciseEntry
    let gym: Gym?
    let history: History
    let onPick: (ExerciseDef) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = entry.exercise
        let options = current.map { Planner.swapOptions(for: $0, gym: gym?.info, history: history) } ?? []
        let missing = current.map { Planner.unavailableSwaps(for: $0, gym: gym?.info) } ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Swap \(entry.name.lowercased())")
                        .font(Theme.rounded(26))
                        .accessibilityAddTraits(.isHeader)
                    Text("Same muscles, using what \(gym?.name ?? "this gym") has. Tap one and keep going.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }

                if options.isEmpty {
                    Text("Nothing equivalent is set up for this gym. Add more equipment under Gyms.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .card(color: Theme.surface2)
                }

                VStack(spacing: 8) {
                    ForEach(options, id: \.exercise.id) { option in
                        Button { onPick(option.exercise) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(option.exercise.name).font(.system(size: 17, weight: .bold))
                                        if option.isBestMatch {
                                            Text("BEST MATCH")
                                                .font(.system(size: 11, weight: .heavy))
                                                .foregroundStyle(Theme.onVolt)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Theme.volt, in: RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                    Text(option.detail)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(option.isBestMatch ? Theme.volt : Theme.muted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(option.isBestMatch ? Theme.volt : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("swap-\(option.exercise.id)")
                    }
                }

                if !missing.isEmpty {
                    CapsLabel("Not at this gym")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(missing) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.system(size: 15, weight: .semibold))
                                Text("Needs: \(exercise.equipmentType.name.lowercased())").font(.system(size: 13))
                            }
                            .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }

                Text("Your choice is remembered for this gym, so it is offered here next time too.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .padding(.top, 8)
        }
        .foregroundStyle(Theme.text)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}

/// Pick any exercise this gym can do, grouped by muscle group.
struct AddExerciseSheet: View {
    let gym: Gym?
    let excluded: Set<String>
    let onPick: (ExerciseDef) -> Void

    var body: some View {
        let info = gym?.info
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add an exercise")
                    .font(Theme.rounded(26))
                    .accessibilityAddTraits(.isHeader)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let exercises = ExerciseCatalog.all.filter {
                        $0.muscle.group == group && !excluded.contains($0.id) && Planner.isAvailable($0, gym: info)
                    }
                    if !exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(group.title)
                            VStack(spacing: 0) {
                                ForEach(exercises) { exercise in
                                    Button { onPick(exercise) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(exercise.name).font(.system(size: 16, weight: .semibold))
                                                Text("\(exercise.muscle.title) · \(exercise.equipmentType.name)")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "plus").foregroundStyle(Theme.volt)
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .foregroundStyle(Theme.text)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}

/// Weekly goal, abs frequency, Apple Health and rep ranges.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthService
    @Query private var prefs: [ExercisePrefs]
    @AppStorage("weeklyGoal") private var weeklyGoal = 3
    @AppStorage("absEveryDays") private var absEveryDays = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Weekly goal: \(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s")", value: $weeklyGoal, in: 1...7)
                    Stepper("Offer abs every \(absEveryDays) day\(absEveryDays == 1 ? "" : "s")", value: $absEveryDays, in: 1...14)
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Your streak counts weeks where you reach the weekly goal, not individual days.")
                }

                Section {
                    if health.connected {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.volt)
                        if let weight = health.bodyWeight {
                            LabeledContent("Body weight", value: "\(String(format: "%.1f", weight)) lb")
                        }
                    } else if health.isAvailable {
                        Button("Connect Apple Health") { Task { await health.connect() } }
                    } else {
                        Text("Apple Health is not available on this device.")
                    }
                    if let error = health.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Reads your runs, walks and body weight. Saves each lifting session as a strength workout.")
                }

                Section {
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        NavigationLink(group.title) { RepRangeList(group: group) }
                    }
                } header: {
                    Text("Rep ranges")
                } footer: {
                    Text("Each exercise has a rep range. Reach the top number on every set and the app suggests the next weight up.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct RepRangeList: View {
    let group: MuscleGroup
    @Environment(\.modelContext) private var context
    @Query private var prefs: [ExercisePrefs]

    var body: some View {
        List {
            ForEach(ExerciseCatalog.all.filter { $0.muscle.group == group }) { exercise in
                let range = current(exercise)
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name).font(.headline)
                    Stepper("At least \(range.lowerBound) reps", value: Binding(
                        get: { range.lowerBound },
                        set: { save(exercise, low: $0, high: max(range.upperBound, $0 + 1)) }), in: 1...29)
                    Stepper("Up to \(range.upperBound) reps", value: Binding(
                        get: { range.upperBound },
                        set: { save(exercise, low: min(range.lowerBound, $0 - 1), high: $0) }), in: 2...30)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func current(_ exercise: ExerciseDef) -> ClosedRange<Int> {
        Store.rangeOverrides(prefs)[exercise.id] ?? exercise.range
    }

    private func save(_ exercise: ExerciseDef, low: Int, high: Int) {
        let low = max(1, low)
        let high = max(low + 1, high)
        if let existing = prefs.first(where: { $0.exerciseID == exercise.id }) {
            existing.repLow = low
            existing.repHigh = high
        } else {
            context.insert(ExercisePrefs(exerciseID: exercise.id, repLow: low, repHigh: high))
        }
        try? context.save()
    }
}
