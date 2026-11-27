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
    @State private var showAll = false

    var body: some View {
        let current = entry.exercise
        let options = current.map { Planner.swapOptions(for: $0, gym: gym?.info, history: history) } ?? []
        let missing = current.map { Planner.unavailableSwaps(for: $0, gym: gym?.info) } ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Swap \(entry.name.lowercased())")
                        .scaledFont(26, weight: .heavy, design: .rounded)
                        .accessibilityAddTraits(.isHeader)
                    Text("Same muscles, using what \(gym?.name ?? "this gym") has. Tap one and keep going.")
                        .scaledFont(14)
                        .foregroundStyle(Theme.muted)
                }

                if options.isEmpty {
                    Text("Nothing equivalent is set up for this gym. Add more equipment under Gyms.")
                        .scaledFont(15)
                        .foregroundStyle(Theme.muted)
                        .card(color: Theme.surface2)
                }

                VStack(spacing: 8) {
                    // The closest eight; the rest of the library on request.
                    ForEach(showAll ? options : Array(options.prefix(8)), id: \.exercise.id) { option in
                        Button { onPick(option.exercise) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(option.exercise.name).scaledFont(17, weight: .bold)
                                        if option.isBestMatch {
                                            Text("BEST MATCH")
                                                .scaledFont(11, weight: .heavy)
                                                .foregroundStyle(Theme.onVolt)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Theme.volt, in: RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                    Text(option.detail)
                                        .scaledFont(13)
                                        .foregroundStyle(Theme.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .scaledFont(14, weight: .heavy)
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
                    if !showAll, options.count > 8 {
                        Button("Show \(options.count - 8) more") { showAll = true }
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(Theme.volt)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("moreSwaps")
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
                                        Text(exercise.name).scaledFont(15, weight: .semibold).foregroundStyle(Theme.text)
                                        Text("Tap to add \(exercise.equipmentType.name.lowercased()) to this gym and use it")
                                            .scaledFont(13)
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
                    .scaledFont(13)
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


/// Weekly goal, abs frequency, Apple Health and rep ranges.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthService
    @Query private var prefs: [ExercisePrefs]
    @AppStorage("weeklyGoal") private var weeklyGoal = 3
    @AppStorage(CardioSetting.key) private var cardioCounts = true
    @AppStorage("absEveryDays") private var absEveryDays = 3
    @AppStorage(RestSetting.key) private var restSeconds = 0
    @AppStorage(Units.key) private var unitRaw = WeightUnit.lb.rawValue

    @AppStorage("keptPairs") private var keptPairs = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Weekly goal: \(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s")", value: $weeklyGoal, in: 1...7)
                    Toggle("Cardio counts toward the goal", isOn: $cardioCounts)
                        .accessibilityIdentifier("cardioCounts")
                    Stepper("Offer abs every \(absEveryDays) day\(absEveryDays == 1 ? "" : "s")", value: $absEveryDays, in: 1...14)
                    NavigationLink("Days and exercises") { RoutineEditor() }
                        .accessibilityIdentifier("routine")
                } header: {
                    Text("Routine")
                } footer: {
                    Text("Days and exercises is where you rename days, add or remove them, change what each one starts with, or switch to a ready-made routine. Your streak counts weeks where you reach the weekly goal, not individual days. With cardio counting, each day with a run, ride or other cardio workout in Apple Health counts as one workout.")
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
                    Picker("Weights in", selection: Binding(
                        get: { WeightUnit(rawValue: unitRaw) ?? .lb },
                        set: { unit in
                            Store.switchUnit(to: unit, context: context)
                            unitRaw = unit.rawValue
                            WatchLink.shared.push()
                        })) {
                        Text("Pounds (lb)").tag(WeightUnit.lb)
                        Text("Kilograms (kg)").tag(WeightUnit.kg)
                    }
                    .accessibilityIdentifier("weightUnit")
                } header: {
                    Text("Units")
                } footer: {
                    Text("Changes how weights are shown and typed, the plates you load (20 kg bar and kilogram plates) and the weight steps (5 lb becomes 2.5 kg). Your logged workouts are not changed.")
                }

                Section {
                    if health.connected {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.volt)
                        if let weight = health.bodyWeight {
                            LabeledContent("Body weight", value: Fmt.lb(weight))
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
                    Text("Reads your cardio workouts (runs, walks, rides, elliptical, stairs, hikes and more) and body weight. Saves each lifting session as a strength workout.")
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

                ExportSection()

                Section {
                    LabeledContent("Version", value: Self.versionText)
                        .accessibilityIdentifier("appVersion")
                    Link("Privacy policy", destination: Self.privacyPolicyURL)
                        .accessibilityIdentifier("privacyPolicy")
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
    /// The published privacy policy (a Google Site; the text is in docs/privacy.md). Also goes in App Store Connect.
    static let privacyPolicyURL = URL(string: "https://sites.google.com/view/next-up-privacy-policy")!

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
