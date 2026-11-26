import Foundation

/// Sample data so the Watch app can run with no iPhone, for screenshots and trying the screens.
/// Launch with `-demoData`, and optionally `-demoScreen log|rest|live|summary`.
@MainActor
enum Demo {
    static func prepare(_ model: WatchModel) {
        var snapshot = WatchSnapshot(next: WatchNext(dayNumber: 1, title: "Chest & triceps", exerciseCount: 6, minutes: 45))
        let screen = UserDefaults.standard.string(forKey: "demoScreen") ?? "today"
        guard screen != "today" else {
            model.setSnapshot(snapshot)
            return
        }
        var workout = makeWorkout()
        snapshot.next = nil
        model.tracker.heartRate = 128
        model.tracker.averageHeartRate = 121
        model.tracker.calories = 214
        switch screen {
        case "rest":
            workout.entries[0].sets[0].done = true
            snapshot.active = workout
            model.setSnapshot(snapshot)
            model.rest.start(seconds: 90)
        case "live":
            workout.startedAt = Date().addingTimeInterval(-760)
            for e in 0..<3 {
                for s in workout.entries[e].sets.indices { workout.entries[e].sets[s].done = true }
            }
            snapshot.active = workout
            model.setSnapshot(snapshot)
        case "summary":
            model.setSnapshot(snapshot)
            model.finished = FinishedInfo(workoutID: workout.id, title: workout.title, minutes: 42, sets: 18, records: 2,
                                          calories: 312, averageHeartRate: 121, savedToHealth: true)
        default:
            snapshot.active = workout
            model.setSnapshot(snapshot)
        }
    }

    static func handle(_ command: WatchCommand, model: WatchModel) {
        guard var snapshot = model.snapshot else { return }
        switch command {
        case .start:
            snapshot.next = nil
            snapshot.active = makeWorkout()
            model.tracker.heartRate = 112
            model.tracker.averageHeartRate = 110
            model.tracker.calories = 4
            model.setSnapshot(snapshot)
        case .log(let setID, _, let reps, _):
            // Pretend the phone found a record on a strong set.
            if let set = snapshot.active?.entries.flatMap(\.sets).first(where: { $0.id == setID }),
               let last = set.lastReps, reps > last + 1 {
                model.showRecord("Most reps yet")
            }
        case .finish:
            snapshot.next = WatchNext(dayNumber: 2, title: "Back & biceps", exerciseCount: 6, minutes: 45)
            snapshot.active = nil
            model.setSnapshot(snapshot)
        case .swapOptions:
            model.swapOptions = [
                WatchSwapOption(id: "a", name: "Dumbbell bench press", isBestMatch: true),
                WatchSwapOption(id: "b", name: "Machine chest press", isBestMatch: false),
                WatchSwapOption(id: "c", name: "Push-up", isBestMatch: false),
            ]
        case .swap(let entryID, let exerciseID):
            let names = ["a": "Dumbbell bench press", "b": "Machine chest press", "c": "Push-up"]
            if let index = snapshot.active?.entries.firstIndex(where: { $0.id == entryID }) {
                snapshot.active?.entries[index].name = names[exerciseID] ?? "Swapped"
                model.setSnapshot(snapshot)
            }
        case .addOptions:
            model.addOptions = [
                WatchAddOption(id: "crunch", name: "Crunch", group: "Abs"),
                WatchAddOption(id: "plank", name: "Plank", group: "Abs"),
                WatchAddOption(id: "hanging_knee_raise", name: "Hanging knee raise", group: "Abs"),
                WatchAddOption(id: "leg_ext", name: "Leg extension", group: "Legs"),
            ]
        case .add(let exerciseID):
            let names = ["crunch": "Crunch", "plank": "Plank", "hanging_knee_raise": "Hanging knee raise", "leg_ext": "Leg extension"]
            guard var active = snapshot.active else { return }
            active.entries.append(WatchEntry(id: UUID(), name: names[exerciseID] ?? exerciseID, restSeconds: 60,
                                             increment: 5, isBodyweight: exerciseID != "leg_ext",
                                             sets: (0..<3).map { WatchSet(id: UUID(), index: $0, weight: 0, reps: 15,
                                                                         lastWeight: nil, lastReps: nil, done: false) }))
            snapshot.active = active
            model.setSnapshot(snapshot)
        case .refresh, .tracking, .healthSaved, .later, .step, .focus, .rest:
            break
        }
    }

    private static func makeWorkout() -> WatchWorkout {
        let plan: [(String, Double, Int, Int, Bool)] = [
            ("Bench press", 160, 9, 120, false),
            ("Incline dumbbell press", 25, 10, 120, false),
            ("Cable fly", 20, 12, 75, false),
            ("Triceps pushdown", 40, 11, 75, false),
            ("Overhead triceps extension", 25, 10, 75, false),
            ("Dip", 0, 8, 75, true),
        ]
        let entries = plan.map { name, weight, reps, rest, body in
            WatchEntry(id: UUID(), name: name, restSeconds: rest, increment: 5, isBodyweight: body,
                       bar: name == "Bench press" ? Plates.barWeight : nil,
                       sets: (0..<3).map { index in
                           WatchSet(id: UUID(), index: index, weight: weight, reps: reps,
                                    lastWeight: weight > 0 ? weight - 5 : 0, lastReps: reps + 1, done: false)
                       })
        }
        return WatchWorkout(id: UUID(), title: "Chest & triceps", startedAt: Date(), entries: entries)
    }
}

#if DEBUG
/// Runs a short workout against the real iPhone app with no taps, and prints what happened.
/// Used to check the phone-to-Watch connection in paired simulators (launch with `-selfTest`).
@MainActor
enum SelfTest {
    static func run(_ model: WatchModel) async {
        setvbuf(stdout, nil, _IONBF, 0)
        print("SELFTEST begin")
        guard await wait("plan arrived from the phone", { model.snapshot?.next != nil || model.snapshot?.active != nil }) else { return }
        if model.snapshot?.active == nil { model.start(quick: true) }
        print("SELFTEST start asked, notice: \(model.notice ?? "none")")
        guard await wait("workout started on the phone", { model.snapshot?.active != nil }),
              let workout = model.snapshot?.active, let entry = workout.entries.first, let set = entry.nextSet else { return }
        print("SELFTEST workout: \(workout.title), \(workout.entries.count) exercises, first: \(entry.name)")
        model.log(set, in: entry, weight: set.weight + entry.increment, reps: set.reps + 1)
        print("SELFTEST rest running: \(model.rest.isRunning), \(Int(model.rest.total)) s")
        guard await wait("phone confirmed the logged set", { model.pendingCount == 0 && model.snapshot?.active?.doneSets.count == 1 }) else { return }
        model.finish()
        guard await wait("summary came back from the phone", { model.snapshot?.active == nil && model.snapshot?.summary?.sets == 1 }) else { return }
        if let summary = model.snapshot?.summary, let done = model.finished {
            print("SELFTEST summary: \(summary.title), \(summary.sets) set, next up: \(model.snapshot?.next?.title ?? "none"), saved to Health by Watch: \(done.savedToHealth)")
        }
        print("SELFTEST PASSED")
    }

    private static func wait(_ what: String, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<90 {
            if condition() {
                print("SELFTEST ok: \(what)")
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        print("SELFTEST FAILED: \(what)")
        return false
    }
}
#endif
