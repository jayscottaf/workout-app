import Foundation
import HealthKit
import SwiftData
import WatchConnectivity

/// The iPhone's side of the Apple Watch connection.
/// It sends the Watch a copy of today's workout and applies what you do on the Watch to the saved data.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    /// Set when the Watch discards a workout, so the phone can close its workout screen first.
    @Published var closeWorkoutID: UUID?
    /// The exercise showing on both devices. Set by the phone's workout screen or by the Watch.
    @Published private(set) var currentEntryID: UUID?

    private var container: ModelContainer?
    private weak var health: HealthService?
    private var launchedWatchFor: UUID?
    private static let ownedKey = "watchHealthWorkouts"

    private var context: ModelContext? { container?.mainContext }
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate(container: ModelContainer, health: HealthService) {
        self.container = container
        self.health = health
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// The phone's workout screen moved to this exercise: tell the Watch.
    func focus(_ entryID: UUID) {
        guard currentEntryID != entryID else { return }
        currentEntryID = entryID
        push()
    }

    // MARK: Apple Health ownership

    /// Workouts the Watch records (with heart rate) and saves to Apple Health itself.
    private var owned: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.ownedKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(30)), forKey: Self.ownedKey) }
    }

    /// True when the Watch saves this workout to Apple Health, so the phone must not save a second copy.
    func watchSavesToHealth(_ workoutID: UUID) -> Bool {
        owned.contains(workoutID.uuidString)
    }

    private func markOwned(_ workoutID: UUID) {
        guard !watchSavesToHealth(workoutID) else { return }
        owned.append(workoutID.uuidString)
    }

    // MARK: sending

    /// Send the Watch a fresh copy of the current state. Cheap to call often.
    func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let snapshot = makeSnapshot(), let data = WatchWire.encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchWire.snapshot: data])
        launchWatchIfNeeded(for: snapshot.active)
    }

    /// A workout started on the phone opens the Watch app so it can record heart rate.
    private func launchWatchIfNeeded(for active: WatchWorkout?) {
        guard let active, active.trackHealth, launchedWatchFor != active.id,
              !watchSavesToHealth(active.id), HKHealthStore.isHealthDataAvailable() else { return }
        launchedWatchFor = active.id
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        HKHealthStore().startWatchApp(with: configuration) { _, _ in }
    }

    private func fetchWorkouts() -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context?.fetch(descriptor)) ?? []
    }

    private func currentGym() -> Gym? {
        let gyms = (try? context?.fetch(FetchDescriptor<Gym>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let chosen = UserDefaults.standard.string(forKey: "currentGymID") ?? ""
        return gyms.first { $0.id.uuidString == chosen } ?? gyms.first
    }

    private func overrides() -> [String: ClosedRange<Int>] {
        Store.rangeOverrides((try? context?.fetch(FetchDescriptor<ExercisePrefs>())) ?? [])
    }

    private func makeSnapshot() -> WatchSnapshot? {
        guard context != nil else { return nil }
        let workouts = fetchWorkouts()
        var snapshot = WatchSnapshot(restOverride: RestSetting.current, rest: RestTimer.shared.shared, unit: Units.current, sentAt: Date())

        if let active = workouts.first(where: { $0.endedAt == nil }) {
            snapshot.active = WatchWorkout(
                id: active.id, title: active.title, startedAt: active.startedAt,
                trackHealth: !active.savedToHealth,
                currentEntryID: active.allEntries.contains { $0.id == currentEntryID } ? currentEntryID : nil,
                entries: active.sortedEntries.map { entry in
                    WatchEntry(id: entry.id, name: entry.name, restSeconds: entry.restSeconds,
                               increment: entry.increment, isBodyweight: entry.isBodyweight, bar: entry.plateBar,
                               sets: entry.sortedSets.map { set in
                                   WatchSet(id: set.id, index: set.index, weight: set.weight, reps: set.reps,
                                            lastWeight: set.lastWeight, lastReps: set.lastReps,
                                            done: set.completedAt != nil, isRecord: set.prKindRaw != nil)
                               })
                })
        } else {
            let history = Store.history(workouts)
            let day = Rotation.nextDay(history: history)
            let plan = Planner.plan(day: day, includeAbs: false, quick: false, gym: currentGym()?.info, history: history,
                                    rangeOverrides: overrides())
            snapshot.next = WatchNext(dayNumber: day.number, dayCount: Routine.days.count, title: day.title, exerciseCount: plan.count,
                                      minutes: Planner.estimateMinutes(plan))
        }

        if let last = workouts.first(where: { $0.endedAt != nil }), let ended = last.endedAt,
           Calendar.current.isDateInToday(ended) {
            snapshot.summary = WatchSummary(workoutID: last.id, title: last.title, endedAt: ended,
                                            minutes: last.durationMinutes, sets: last.completedSets.count,
                                            records: last.prSets.count)
        }
        return snapshot
    }

    // MARK: receiving

    /// Apply one thing done on the Watch. Returns the reply to send back.
    private func handle(_ payload: [String: Any]) -> [String: Any] {
        var reply: [String: Any] = [:]
        if let command = WatchWire.decode(WatchCommand.self, from: payload[WatchWire.command]), let context {
            switch command {
            case .refresh:
                break
            case .start(let quick):
                start(quick: quick, context: context)
            case .log(let setID, let weight, let reps, let date):
                if let text = log(setID: setID, weight: weight, reps: reps, at: date, context: context) {
                    reply[WatchWire.record] = text
                }
            case .finish(let workoutID, let date, let savedToHealth):
                finish(workoutID: workoutID, at: date, savedToHealth: savedToHealth, context: context)
            case .swapOptions(let entryID):
                if let data = WatchWire.encode(swapOptions(entryID: entryID)) { reply[WatchWire.swaps] = data }
            case .swap(let entryID, let exerciseID):
                swap(entryID: entryID, exerciseID: exerciseID, context: context)
            case .tracking(let workoutID):
                markOwned(workoutID)
            case .healthSaved(let workoutID):
                markOwned(workoutID)
                if let workout = fetchWorkouts().first(where: { $0.id == workoutID }) {
                    workout.savedToHealth = true
                    try? context.save()
                }
            case .later(let entryID):
                if let (workout, entry) = activeEntry(where: { $0.id == entryID }) {
                    Store.moveToEnd(entry, in: workout, context: context)
                }
            case .step(let entryID, let increment):
                if let (workout, entry) = activeEntry(where: { $0.id == entryID }) {
                    Store.setIncrement(increment, for: entry, gym: gym(for: workout), context: context)
                }
            case .addOptions:
                if let data = WatchWire.encode(addOptions()) { reply[WatchWire.adds] = data }
            case .add(let exerciseID):
                add(exerciseID: exerciseID, context: context)
            case .focus(let entryID):
                currentEntryID = entryID
            case .rest(let rest):
                let workout = fetchWorkouts().first { $0.endedAt == nil }
                let current = workout?.allEntries.first { $0.id == currentEntryID }
                RestTimer.shared.follow(rest, title: workout?.title ?? "", next: workout?.nextUpText(after: current) ?? "")
            }
        }
        if let snapshot = makeSnapshot(), let data = WatchWire.encode(snapshot) {
            reply[WatchWire.snapshot] = data
        }
        return reply
    }

    private func start(quick: Bool, context: ModelContext) {
        let workouts = fetchWorkouts()
        guard !workouts.contains(where: { $0.endedAt == nil }) else { return }
        let history = Store.history(workouts)
        let gym = currentGym()
        let day = Rotation.nextDay(history: history)
        let plan = Planner.plan(day: day, includeAbs: false, quick: quick, gym: gym?.info, history: history,
                                rangeOverrides: overrides())
        // A day with no exercises yet: nothing to start.
        guard !plan.isEmpty else { return }
        let workout = Store.start(plan: plan, day: day, quick: quick, gym: gym, context: context)
        // The Watch started this one, so it is already open there.
        launchedWatchFor = workout.id
    }

    private func activeEntry(where match: (ExerciseEntry) -> Bool) -> (Workout, ExerciseEntry)? {
        for workout in fetchWorkouts() where workout.endedAt == nil {
            if let entry = workout.allEntries.first(where: match) { return (workout, entry) }
        }
        return nil
    }

    /// Returns the personal-record text if the set was one.
    private func log(setID: UUID, weight: Double, reps: Int, at date: Date, context: ModelContext) -> String? {
        guard let (_, entry) = activeEntry(where: { $0.allSets.contains { $0.id == setID } }),
              let set = entry.allSets.first(where: { $0.id == setID }), set.completedAt == nil else { return nil }
        set.weight = max(0, weight)
        set.reps = max(1, reps)
        let kind = Store.complete(set, in: entry, history: Store.history(fetchWorkouts()), context: context, at: date)
        return kind?.text(weight: set.weight, reps: set.reps)
    }

    private func finish(workoutID: UUID, at date: Date, savedToHealth: Bool, context: ModelContext) {
        guard let workout = fetchWorkouts().first(where: { $0.id == workoutID }) else { return }
        if savedToHealth { markOwned(workoutID) }
        guard workout.endedAt == nil else {
            if savedToHealth {
                workout.savedToHealth = true
                try? context.save()
            }
            return
        }
        // Finished or discarded on the Watch: take the workout card off the Lock Screen.
        RestTimer.shared.endWorkout()
        guard !workout.completedSets.isEmpty else {
            // Nothing logged: close the phone's workout screen first, then delete.
            closeWorkoutID = workoutID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                Store.finish(workout, context: context)
                self?.closeWorkoutID = nil
                self?.push()
            }
            return
        }
        Store.finish(workout, context: context, at: max(date, workout.startedAt.addingTimeInterval(1)))
        if savedToHealth {
            workout.savedToHealth = true
            try? context.save()
        } else if !watchSavesToHealth(workoutID), !workout.savedToHealth, let health, let end = workout.endedAt {
            // The Watch could not record it (Health is off there), so the phone saves it as before.
            let start = workout.startedAt
            Task { @MainActor in
                if await health.saveLifting(start: start, end: end) {
                    workout.savedToHealth = true
                    try? context.save()
                }
            }
        }
    }

    private func swapOptions(entryID: UUID) -> [WatchSwapOption] {
        guard let (workout, entry) = activeEntry(where: { $0.id == entryID }), let exercise = entry.exercise else { return [] }
        let gym = gym(for: workout)
        return Planner.swapOptions(for: exercise, gym: gym?.info, history: Store.history(fetchWorkouts()))
            .map { WatchSwapOption(id: $0.exercise.id, name: $0.exercise.name, isBestMatch: $0.isBestMatch) }
    }

    private func swap(entryID: UUID, exerciseID: String, context: ModelContext) {
        guard let (workout, entry) = activeEntry(where: { $0.id == entryID }),
              let exercise = ExerciseCatalog.exercise(exerciseID) else { return }
        Store.swap(entry, to: exercise, in: workout, gym: gym(for: workout), history: Store.history(fetchWorkouts()),
                   overrides: overrides(), context: context)
    }

    /// Everything this gym can do that is not already in the workout, grouped by muscle.
    private func addOptions() -> [WatchAddOption] {
        guard let workout = fetchWorkouts().first(where: { $0.endedAt == nil }) else { return [] }
        let gym = gym(for: workout)?.info
        let taken = Set(workout.allEntries.map(\.exerciseID))
        return MuscleGroup.allCases.flatMap { group in
            ExerciseCatalog.all
                .filter { $0.muscle.group == group && !taken.contains($0.id) && Planner.isAvailable($0, gym: gym) }
                .map { WatchAddOption(id: $0.id, name: $0.name, group: group.title) }
        }
    }

    private func add(exerciseID: String, context: ModelContext) {
        guard let workout = fetchWorkouts().first(where: { $0.endedAt == nil }),
              let exercise = ExerciseCatalog.exercise(exerciseID),
              !workout.allEntries.contains(where: { $0.exerciseID == exerciseID }) else { return }
        Store.add(exercise, to: workout, gym: gym(for: workout), history: Store.history(fetchWorkouts()),
                  overrides: overrides(), context: context)
    }

    private func gym(for workout: Workout) -> Gym? {
        let gyms = (try? context?.fetch(FetchDescriptor<Gym>())) ?? []
        return gyms.first { $0.id == workout.gymID }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A different Watch was paired: connect to the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.handle(message))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = self.handle(message)
            self.push()
        }
    }

    /// Things done on the Watch while the phone was out of reach arrive here later, in order.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = self.handle(userInfo)
            self.push()
        }
    }
}
