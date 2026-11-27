import SwiftUI
import SwiftData

/// Home screen: offers whichever day is next, plus add-ons, weekly goal and cardio.
struct TodayView: View {
    let onStart: (Workout) -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthService
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @Query private var prefs: [ExercisePrefs]
    @AppStorage("currentGymID") private var currentGymID = ""
    @AppStorage("weeklyGoal") private var weeklyGoal = 3
    @AppStorage("absEveryDays") private var absEveryDays = 3
    @AppStorage("keptPairs") private var keptPairs = ""

    @State private var includeAbs = false
    @State private var extras: [String] = []
    @State private var dayOverride: DayType?
    @State private var showSettings = false
    @State private var showRoutine = false
    @State private var equipmentGym: Gym?
    @ObservedObject private var routine = RoutineStore.shared
    @State private var showRecap = false
    /// Today's exercises after "Edit today" (swaps, removals, additions, order). nil = the routine as planned.
    @State private var customPlan: [PlannedExercise]?
    @State private var editingToday = false
    /// The muscle tag that is open to show its parts (upper, middle, lower chest...).
    @State private var openTag: Muscle?

    private var currentGym: Gym? {
        gyms.first { $0.id.uuidString == currentGymID } ?? gyms.first
    }

    var body: some View {
        let history = Store.history(workouts)
        let gym = currentGym
        // A day picked by hand is looked up again, so edits to the routine show straight away.
        let day = dayOverride.flatMap { picked in routine.days.first { $0.id == picked.id } } ?? Rotation.nextDay(history: history)
        let overrides = Store.rangeOverrides(prefs)
        let plan = customPlan ?? Planner.plan(day: day, includeAbs: includeAbs, quick: false, gym: gym?.info, history: history,
                                               rangeOverrides: overrides)
        let status = Streak.status(dates: Store.finished(workouts).map(\.startedAt), goal: weeklyGoal)
        let active = workouts.first { $0.endedAt == nil }

        ScrollView {
            VStack(spacing: 12) {
                header(gym: gym)
                if let active {
                    resumeCard(active)
                } else {
                    hero(day: day, plan: plan, history: history, gym: gym, overrides: overrides)
                }
                HStack(spacing: 12) {
                    weekCard(status)
                    streakCard(status)
                }
                if active == nil {
                    addOns(day: day, plan: plan, history: history, gym: gym)
                }
                if showsRecapRow { recapRow }
                cardioCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screen()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showRoutine) { RoutineSheet() }
        .sheet(item: $equipmentGym) { item in GymEquipmentSheet(gym: item) }
        .sheet(isPresented: $showRecap) { RecapSheet(month: previousMonth) }
        .sheet(isPresented: $editingToday) {
            TodayEditSheet(day: day, plan: plan, gym: gym, history: history, overrides: overrides) { edited, saveToRoutine in
                editingToday = false
                if saveToRoutine {
                    save(edited, to: day)
                    customPlan = nil
                } else {
                    customPlan = edited
                }
            }
        }
        // Today's edits belong to this day at this gym.
        .onChange(of: dayOverride?.id) { customPlan = nil; openTag = nil }
        .onChange(of: currentGymID) { customPlan = nil }
    }

    // MARK: header

    private func header(gym: Gym?) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel(Date().longDay)
                Text("Today")
                    .font(Theme.rounded(34))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Menu {
                ForEach(gyms) { item in
                    Button {
                        currentGymID = item.id.uuidString
                    } label: {
                        if item.id == gym?.id {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
                if let gym {
                    Divider()
                    Button { equipmentGym = gym } label: {
                        Label("Equipment at \(gym.name)", systemImage: "checklist")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.volt)
                    Text(gym?.name ?? "No gym")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Theme.surface, in: Capsule())
            }
            .accessibilityLabel("Current gym: \(gym?.name ?? "none"). Change gym")
            CircleIconButton(systemName: "gearshape.fill", label: "Settings", fill: Theme.surface, foreground: Theme.muted) {
                showSettings = true
            }
        }
    }

    // MARK: hero

    private func hero(day: DayType, plan: [PlannedExercise], history: History, gym: Gym?,
                      overrides: [String: ClosedRange<Int>]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CapsLabel("Next up · day \(day.number) of \(routine.days.count)", color: Theme.onVolt)
                Spacer()
                Menu {
                    ForEach(DayType.allCases, id: \.self) { option in
                        Button(option.title) { dayOverride = option }
                    }
                    Divider()
                    Button("Edit routine", systemImage: "slider.horizontal.3") { showRoutine = true }
                } label: {
                    HStack(spacing: 4) {
                        Text("Change")
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.onVolt)
                    .frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("Do a different day instead")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(day.title)
                    .font(Theme.rounded(36))
                    .tracking(-0.8)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("\(plan.count) exercises · about \(Planner.estimateMinutes(plan)) min · \(lastDone(day))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.onVoltSoft)
                muscleTags(plan.map(\.exercise.id))
                if let pair = Overlap.firstPair(plan.map(\.exercise), kept: Overlap.keptPairs(keptPairs)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.2").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(pair.exercise.name) and \(pair.overlap.other.name) do the same job.")
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 16) {
                                Button("Change today") { editingToday = true }
                                    .underline()
                                    .accessibilityIdentifier("overlapEditToday")
                                Button("Keep both") {
                                    keptPairs = Overlap.keeping(pair.exercise.id, pair.overlap.other.id, in: keptPairs)
                                }
                                .underline()
                                .accessibilityIdentifier("keepBoth")
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 32)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onVolt)
                    .padding(.top, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("planOverlap")
                }
                HStack(spacing: 14) {
                    Button {
                        editingToday = true
                    } label: {
                        Label(customPlan == nil ? "Edit today's exercises" : "Changed for today · edit", systemImage: "list.bullet")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .accessibilityIdentifier("editToday")
                    if customPlan != nil {
                        Button("Undo") { customPlan = nil }
                            .font(.system(size: 13, weight: .bold))
                            .underline()
                            .accessibilityLabel("Undo today's changes")
                            .accessibilityIdentifier("undoToday")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.onVolt)
                .frame(minHeight: 36)
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                Button("Start workout") {
                    start(day: day, quick: false, history: history, gym: gym, overrides: overrides)
                }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.onVolt, foreground: Theme.text, height: 52))
                .accessibilityIdentifier("startWorkout")
                .disabled(plan.isEmpty)

                if customPlan == nil {
                Button {
                    start(day: day, quick: true, history: history, gym: gym, overrides: overrides)
                } label: {
                    Text("20 min")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onVolt)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .overlay(Capsule().strokeBorder(Theme.onVolt, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start the 20 minute version")
                .accessibilityIdentifier("startQuick")
                }
            }
        }
        .foregroundStyle(Theme.onVolt)
        .card(padding: 22, radius: 28, color: Theme.volt)
    }

    private func resumeCard(_ active: Workout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CapsLabel("Workout in progress", color: Theme.onVolt)
            Text(active.title)
                .font(Theme.rounded(36))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("\(active.completedSets.count) sets logged so far")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.onVoltSoft)
            Button("Pick up where you left off") { onStart(active) }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.onVolt, foreground: Theme.text, height: 52))
        }
        .foregroundStyle(Theme.onVolt)
        .card(padding: 22, radius: 28, color: Theme.volt)
    }

    /// Main muscles as tags. Muscles split into parts (chest, triceps, biceps, shoulders) open to show
    /// which exercise works which part, for example "Upper: Incline dumbbell press".
    @ViewBuilder
    private func muscleTags(_ ids: [String]) -> some View {
        let muscles = MuscleMap.targets(ids)
        if !muscles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(muscles, id: \.self) { muscle in
                        let split = MuscleParts.hasParts(muscle)
                        let open = openTag == muscle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { openTag = open ? nil : muscle }
                        } label: {
                            HStack(spacing: 4) {
                                Text(muscle.title)
                                if split {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .heavy))
                                        .rotationEffect(.degrees(open ? 180 : 0))
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(open ? Theme.volt : Theme.onVolt)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(open ? Theme.onVolt : Theme.onVolt.opacity(0.1), in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(split)
                        .accessibilityRemoveTraits(split ? [] : .isButton)
                        .accessibilityLabel(muscle.title)
                        .accessibilityHint(split ? (open ? "Hides its parts" : "Shows which exercise works which part") : "")
                        .accessibilityIdentifier("tag-\(muscle.rawValue)")
                    }
                }
                if let muscle = openTag, muscles.contains(muscle) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(MuscleParts.breakdown(ids, muscle: muscle), id: \.part) { row in
                            (Text("\(row.part): ").bold()
                             + Text(row.exercises.isEmpty ? "nothing today" : row.exercises.joined(separator: ", ")))
                                .font(.system(size: 13))
                                .foregroundStyle(row.exercises.isEmpty ? Theme.onVoltSoft : Theme.onVolt)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tagParts")
                }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("muscleTags")
        }
    }

    /// "Also change my routine": today's list becomes the day's list. A swapped exercise gets a new
    /// position key so the planner does not bring back what was last done in that spot.
    private func save(_ plan: [PlannedExercise], to day: DayType) {
        guard let index = routine.days.firstIndex(where: { $0.id == day.id }) else { return }
        var updated = routine.days[index]
        let prefix = updated.id + "."
        let old = Dictionary(uniqueKeysWithValues: updated.items.map { ($0.key, $0.exercise) })
        updated.items = plan.filter { !($0.slotID?.hasPrefix("abs.") ?? false) }.map { planned in
            if let slotID = planned.slotID, slotID.hasPrefix(prefix) {
                let key = String(slotID.dropFirst(prefix.count))
                if old[key] == planned.exercise.id { return DaySlot(key: key, exercise: planned.exercise.id) }
            }
            return DaySlot(key: String(UUID().uuidString.prefix(8)), exercise: planned.exercise.id)
        }
        updated.quick = nil
        routine.days[index] = updated
    }

    private func lastDone(_ day: DayType) -> String {
        guard let last = Store.finished(workouts).first(where: { $0.dayRaw == day.id }) else { return "first time" }
        return "last done \(last.startedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func start(day: DayType, quick: Bool, history: History, gym: Gym?, overrides: [String: ClosedRange<Int>]) {
        var plan: [PlannedExercise]
        if let customPlan, !quick {
            plan = customPlan
            if includeAbs {
                plan += Planner.absPlan(quick: false, gym: gym?.info, history: history, rangeOverrides: overrides,
                                        excluding: Set(plan.map(\.exercise.id)))
            }
        } else {
            plan = Planner.plan(day: day, includeAbs: includeAbs, quick: quick, gym: gym?.info, history: history,
                                rangeOverrides: overrides)
        }
        for id in extras {
            guard let exercise = ExerciseCatalog.exercise(id), !plan.contains(where: { $0.exercise.id == id }) else { continue }
            plan.append(Planner.planExercise(exercise, slotID: nil, gym: gym?.info, history: history,
                                             rangeOverrides: overrides, quick: quick))
        }
        // A day with no exercises yet: nothing to start.
        guard !plan.isEmpty else { return }
        let workout = Store.start(plan: plan, day: day, quick: quick, gym: gym, context: context)
        includeAbs = false
        extras = []
        dayOverride = nil
        customPlan = nil
        openTag = nil
        Haptics.tap()
        onStart(workout)
    }

    // MARK: week and streak

    private func weekCard(_ status: WeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("This week")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(status.thisWeek)").font(Theme.rounded(28))
                Text("of \(status.goal) workouts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            SegmentBar(filled: status.thisWeek, total: status.goal)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func streakCard(_ status: WeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Streak")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(status.streak)").font(Theme.rounded(28))
                Text(status.streak == 1 ? "week" : "weeks")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Text(streakHint(status))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .lineLimit(2, reservesSpace: false)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func streakHint(_ status: WeekStatus) -> String {
        if status.goalReached { return "Goal reached this week" }
        let more = "\(status.remaining) more this week"
        return status.streak > 0 ? "\(more) keeps it going" : "\(more) starts a streak"
    }

    // MARK: add-ons

    @ViewBuilder
    private func addOns(day: DayType, plan: [PlannedExercise], history: History, gym: Gym?) -> some View {
        let absOffered = includeAbs || Rotation.absDue(history: history, everyDays: absEveryDays)
        let basePlanIDs = Set(plan.filter { $0.exercise.muscle != .abs }.map(\.exercise.id))
        let ideas = Planner.ideas(history: history, gym: gym?.info, plannedExerciseIDs: basePlanIDs)

        if absOffered || !ideas.isEmpty {
            VStack(spacing: 0) {
                if absOffered {
                    addOnRow(title: "Add abs today", detail: absDetail(history: history, gym: gym), isOn: includeAbs,
                             label: "abs") {
                        includeAbs.toggle()
                    }
                }
                ForEach(Array(ideas.enumerated()), id: \.element.exercise.id) { index, idea in
                    if absOffered || index > 0 {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    addOnRow(title: idea.title, detail: idea.detail, isOn: extras.contains(idea.exercise.id),
                             label: idea.exercise.name) {
                        if let position = extras.firstIndex(of: idea.exercise.id) {
                            extras.remove(at: position)
                        } else {
                            extras.append(idea.exercise.id)
                        }
                    }
                }
            }
            .card(padding: 0)
        }
    }

    private func absDetail(history: History, gym: Gym?) -> String {
        let moves = Planner.absPlan(quick: false, gym: gym?.info, history: history)
        let minutes = Planner.estimateMinutes(moves)
        let last: String
        if let date = history.lastAbsDate {
            let days = Progression.daysBetween(date, Date())
            last = days == 0 ? "Done today" : "Last done \(days) day\(days == 1 ? "" : "s") ago"
        } else {
            last = "Not done yet"
        }
        return "\(last) · \(moves.count) moves, about \(minutes) min"
    }

    private func addOnRow(title: String, detail: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CircleIconButton(systemName: isOn ? "checkmark" : "plus",
                             label: isOn ? "Remove \(label) from today's workout" : "Add \(label) to today's workout",
                             fill: isOn ? Theme.volt : Theme.surface2,
                             foreground: isOn ? Theme.onVolt : Theme.volt,
                             action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    // MARK: recap and cardio

    private var previousMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    /// The recap for last month is surfaced during the first week of a new month.
    private var showsRecapRow: Bool {
        guard Calendar.current.component(.day, from: Date()) <= 7,
              let interval = Calendar.current.dateInterval(of: .month, for: previousMonth) else { return false }
        return Store.finished(workouts).contains { interval.contains($0.startedAt) }
    }

    private var recapRow: some View {
        Button { showRecap = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(previousMonth.formatted(.dateTime.month(.wide))) recap is ready")
                        .font(.system(size: 16, weight: .bold))
                    Text("See what you got done last month")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.volt)
            }
            .frame(minHeight: 44)
            .card()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardioCard: some View {
        if health.connected {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 40, height: 40)
                    .background(Theme.blueDim, in: Circle())
                    .accessibilityHidden(true)
                if let latest = health.cardio.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.title).font(.system(size: 15, weight: .bold))
                        Text("\(latest.date.shortDay) · \(latest.durationText) · from Apple Health")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No runs or walks yet").font(.system(size: 15, weight: .bold))
                        Text("They appear here from Apple Health")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14)
            .accessibilityElement(children: .combine)
        } else if health.isAvailable {
            Button {
                Task { await health.connect() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .frame(width: 40, height: 40)
                        .background(Theme.blueDim, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Apple Health").font(.system(size: 15, weight: .bold))
                        Text("Shows your runs and walks, saves your lifting")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                }
                .card(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }
}
