import SwiftUI
import SwiftData

/// One-tap swap to an equivalent exercise when a machine is taken or missing.
struct SwapSheet: View {
    let entry: ExerciseEntry
    let gym: Gym?
    let history: History
    let onPick: (ExerciseDef) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

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
                    CapsLabel("Not ticked at \(gym?.name ?? "this gym") yet")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(missing) { exercise in
                            Button {
                                // Using it here means the gym has it: tick it and swap in one go.
                                if let gym { Store.setHas(exercise.equipmentType, true, gym: gym, context: context) }
                                onPick(exercise)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                        Text("Tap to add \(exercise.equipmentType.name.lowercased()) to this gym and use it")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.muted)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "plus.circle").foregroundStyle(Theme.volt)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("swapNew-\(exercise.id)")
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
    /// Exercises already in the workout or day, in order, to warn about ones that do the same job.
    var current: [String] = []
    let onPick: (ExerciseDef) -> Void
    @AppStorage("keptPairs") private var keptPairs = ""
    @State private var creating = false
    @Environment(\.modelContext) private var context

    var body: some View {
        let info = gym?.info
        let already = current.compactMap { ExerciseCatalog.exercise($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add an exercise")
                    .font(Theme.rounded(26))
                    .accessibilityAddTraits(.isHeader)
                Button { creating = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create your own").font(.system(size: 16, weight: .semibold))
                            Text("Not on the list? Add it once and it stays.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.volt)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("createExercise")
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let all = ExerciseCatalog.all.filter { $0.muscle.group == group && !excluded.contains($0.id) }
                    let exercises = all.filter { Planner.isAvailable($0, gym: info) }
                    let unticked = all.filter { !Planner.isAvailable($0, gym: info) }
                    if !all.isEmpty {
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
                                                if let overlap = Overlap.find(exercise, among: already, kept: Overlap.keptPairs(keptPairs)) {
                                                    Label(overlap.message, systemImage: "exclamationmark.2")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(Theme.amber)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "plus").foregroundStyle(Theme.volt)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .frame(minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("add-\(exercise.id)")
                                }
                                // Equipment not ticked at this gym yet: picking one ticks it here and adds the exercise.
                                ForEach(unticked) { exercise in
                                    Button {
                                        if let gym { Store.setHas(exercise.equipmentType, true, gym: gym, context: context) }
                                        onPick(exercise)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(exercise.name).font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(Theme.text.opacity(0.75))
                                                Text("\(exercise.equipmentType.name) · not ticked here yet, tap to add")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle").foregroundStyle(Theme.muted)
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("addNew-\(exercise.id)")
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
        .sheet(isPresented: $creating) {
            CreateExerciseSheet(gym: gym) { exercise in
                creating = false
                onPick(exercise)
            }
        }
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
    @AppStorage(RestSetting.key) private var restSeconds = 0

    @AppStorage("keptPairs") private var keptPairs = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Weekly goal: \(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s")", value: $weeklyGoal, in: 1...7)
                    Stepper("Offer abs every \(absEveryDays) day\(absEveryDays == 1 ? "" : "s")", value: $absEveryDays, in: 1...14)
                    NavigationLink("Days and exercises") { RoutineEditor() }
                        .accessibilityIdentifier("routine")
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Days and exercises is where you rename days, add or remove them, change what each one starts with, or switch to a ready-made routine. Your streak counts weeks where you reach the weekly goal, not individual days.")
                }

                Section {
                    Stepper {
                        Text("Rest between sets: \(RestSetting.label(restSeconds))")
                    } onIncrement: {
                        restSeconds = RestSetting.step(restSeconds, by: 1)
                    } onDecrement: {
                        restSeconds = RestSetting.step(restSeconds, by: -1)
                    }
                    .accessibilityIdentifier("restSetting")
                } header: {
                    Text("Rest timer")
                } footer: {
                    Text(restSeconds == 0
                         ? "Automatic: 2:00 after big lifts like presses and squats, 1:15 after smaller ones, 1:00 in the 20 minute version."
                         : "Every rest countdown starts at \(RestSetting.label(restSeconds)). You can still add 15 seconds or skip during a workout.")
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
                    NavigationLink("Your exercises and machines") { CustomList() }
                        .accessibilityIdentifier("customList")
                } header: {
                    Text("Rep ranges")
                } footer: {
                    Text("Each exercise has a rep range. Reach the top number on every set and the app suggests the next weight up. Exercises and machines that are not on the built-in list can be added under Your exercises and machines.")
                }

                if !keptPairs.isEmpty {
                    Section {
                        Button("Show hidden warnings again") { keptPairs = "" }
                            .accessibilityIdentifier("resetKeptPairs")
                    } footer: {
                        let count = Overlap.keptPairs(keptPairs).count
                        Text("You chose Keep both for \(count) \(count == 1 ? "pair" : "pairs") of exercises that do the same job, so the app stopped pointing them out.")
                    }
                }

                Section {
                    LabeledContent("Version", value: Self.versionText)
                        .accessibilityIdentifier("appVersion")
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

extension SettingsView {
    /// "1.0 (build 12)", matching the version and build TestFlight shows.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (build \(build))"
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
