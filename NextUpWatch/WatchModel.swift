import Foundation
import WatchConnectivity
import WatchKit

/// What the summary screen shows after Finish.
struct FinishedInfo: Equatable {
    var workoutID: UUID
    var title: String
    var minutes: Int
    var sets: Int
    var records: Int
    var calories: Double?
    var averageHeartRate: Double?
    var savedToHealth: Bool
}

/// The Watch's copy of the workout, and its connection to the iPhone.
/// Sets logged here show up at once and are sent to the phone, which keeps the real data.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()

    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var isStarting = false
    @Published private(set) var isFinishing = false
    @Published var finished: FinishedInfo?
    @Published var notice: String?
    @Published var record: String?
    @Published var swapOptions: [WatchSwapOption]?
    @Published var addOptions: [WatchAddOption]?

    let rest = RestClock()
    let tracker = WorkoutTracker()
    /// Sample data with no iPhone needed: used for screenshots (launch with `-demoData`).
    let isDemo = ProcessInfo.processInfo.arguments.contains("-demoData")
    /// The self-test cannot answer Apple's Health permission sheet, so it runs without Health.
    private let skipsHealth = ProcessInfo.processInfo.arguments.contains("-demoData")
        || ProcessInfo.processInfo.arguments.contains("-selfTest")

    /// When this Watch last moved to another exercise, so an older copy from the phone does not move it back.
    private var focusedAt: Date?

    /// Sets logged here that the phone has not confirmed yet.
    private var pending: [UUID: (weight: Double, reps: Int)] = [:]
    private static let savedKey = "savedWorkoutID"
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        // A countdown started, lengthened or skipped here shows on the phone too.
        rest.onChange = { [weak self] value in self?.send(.rest(value)) }
        if isDemo {
            Demo.prepare(self)
            return
        }
        guard let session else { return }
        session.delegate = self
        session.activate()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-selfTest") {
            Task { await SelfTest.run(self) }
        }
        #endif
    }

    var pendingCount: Int { pending.count }

    func setSnapshot(_ value: WatchSnapshot?) {
        snapshot = value
        if value?.active != nil { isStarting = false }
    }

    // MARK: actions

    func refresh() { send(.refresh) }

    func start(quick: Bool) {
        guard !isStarting else { return }
        notice = nil
        if !isDemo, session?.isReachable != true {
            notice = "Can't reach your iPhone. Keep it nearby, then try again."
            return
        }
        isStarting = true
        WKInterfaceDevice.current().play(.start)
        send(.start(quick: quick))
        guard !skipsHealth else { return }
        Task {
            try? await Task.sleep(for: .seconds(15))
            if isStarting, snapshot?.active == nil {
                isStarting = false
                notice = "Your iPhone didn't answer. Open Next Up on it, then try again."
                syncTracking()
            }
        }
        Task {
            // Record heart rate from the moment Start was tapped.
            await tracker.start(at: Date())
            syncTracking()
        }
    }

    func log(_ set: WatchSet, in entry: WatchEntry, weight: Double, reps: Int) {
        guard var current = snapshot, current.markLogged(setID: set.id, weight: weight, reps: reps) else { return }
        pending[set.id] = (weight, reps)
        snapshot = current
        WKInterfaceDevice.current().play(.click)
        send(.log(setID: set.id, weight: weight, reps: reps, at: Date()))
        if current.active?.setsLeft == 0 {
            rest.stop()
        } else {
            rest.start(seconds: current.restOverride > 0 ? current.restOverride : entry.restSeconds)
        }
    }

    func finish() {
        guard let active = snapshot?.active, !isFinishing else { return }
        isFinishing = true
        rest.stop()
        let end = Date()
        let logged = active.doneSets
        Task {
            var saved = false
            let calories = tracker.calories
            let average = tracker.averageHeartRate
            if tracker.isRunning {
                saved = await tracker.end(at: end, save: !logged.isEmpty)
                if saved { UserDefaults.standard.set(active.id.uuidString, forKey: Self.savedKey) }
            }
            if !logged.isEmpty {
                finished = FinishedInfo(
                    workoutID: active.id, title: active.title,
                    minutes: max(1, Int((end.timeIntervalSince(active.startedAt) / 60).rounded())),
                    sets: logged.count, records: logged.filter(\.isRecord).count,
                    calories: saved || isDemo ? calories : nil, averageHeartRate: saved || isDemo ? average : nil,
                    savedToHealth: saved)
                WKInterfaceDevice.current().play(.success)
            }
            snapshot?.active = nil
            pending.removeAll()
            send(.finish(workoutID: active.id, at: end, savedToHealth: saved))
            isFinishing = false
        }
    }

    func askForSwaps(_ entry: WatchEntry) {
        swapOptions = nil
        notice = nil
        if !isDemo, session?.isReachable != true {
            notice = "Swapping needs your iPhone nearby."
            return
        }
        send(.swapOptions(entryID: entry.id))
    }

    func swap(_ entry: WatchEntry, to option: WatchSwapOption) {
        swapOptions = nil
        send(.swap(entryID: entry.id, exerciseID: option.id))
    }

    /// The machine is busy: do this exercise at the end instead.
    func doLater(_ entry: WatchEntry) {
        guard var current = snapshot else { return }
        current.moveToEnd(entryID: entry.id)
        snapshot = current
        send(.later(entryID: entry.id))
    }

    func setStep(_ value: Double, for entry: WatchEntry) {
        guard var current = snapshot else { return }
        current.setIncrement(entryID: entry.id, value)
        snapshot = current
        send(.step(entryID: entry.id, increment: value))
    }

    /// This Watch moved to another exercise: show it on the phone too.
    func focus(_ entryID: UUID) {
        guard var current = snapshot, current.active?.currentEntryID != entryID else { return }
        current.active?.currentEntryID = entryID
        snapshot = current
        focusedAt = Date()
        send(.focus(entryID: entryID))
    }

    func askForAdds() {
        addOptions = nil
        notice = nil
        if !isDemo, session?.isReachable != true {
            notice = "Adding needs your iPhone nearby."
            return
        }
        send(.addOptions)
    }

    func add(_ option: WatchAddOption) {
        addOptions = nil
        send(.add(exerciseID: option.id))
    }

    // MARK: talking to the phone

    private func send(_ command: WatchCommand) {
        if isDemo {
            Demo.handle(command, model: self)
            return
        }
        guard let session, let data = WatchWire.encode(command) else { return }
        let payload: [String: Any] = [WatchWire.command: data]
        guard session.activationState == .activated, session.isReachable else {
            queue(command, payload)
            return
        }
        session.sendMessage(payload, replyHandler: { reply in
            Task { @MainActor in self.receive(reply) }
        }, errorHandler: { _ in
            Task { @MainActor in self.queue(command, payload) }
        })
    }

    /// The phone is out of reach. Things already done are delivered later; requests are dropped.
    private func queue(_ command: WatchCommand, _ payload: [String: Any]) {
        switch command {
        case .log, .finish, .tracking, .healthSaved, .swap, .later, .step, .add, .rest:
            session?.transferUserInfo(payload)
        case .focus:
            break
        case .start:
            isStarting = false
            notice = "Can't reach your iPhone. Keep it nearby, then try again."
            Task { await tracker.end(at: Date(), save: false) }
        case .swapOptions:
            notice = "Swapping needs your iPhone nearby."
        case .addOptions:
            notice = "Adding needs your iPhone nearby."
        case .refresh:
            break
        }
    }

    func receive(_ message: [String: Any]) {
        if let options = WatchWire.decode([WatchSwapOption].self, from: message[WatchWire.swaps]) {
            swapOptions = options
        }
        if let options = WatchWire.decode([WatchAddOption].self, from: message[WatchWire.adds]) {
            addOptions = options
        }
        if let text = message[WatchWire.record] as? String {
            showRecord(text)
        }
        if let incoming = WatchWire.decode(WatchSnapshot.self, from: message[WatchWire.snapshot]) {
            apply(incoming)
        }
    }

    func showRecord(_ text: String) {
        record = text
        WKInterfaceDevice.current().play(.success)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if record == text { record = nil }
        }
    }

    private func apply(_ incoming: WatchSnapshot) {
        if let current = snapshot, incoming.sentAt < current.sentAt { return }
        // Show weights in the unit chosen on the phone.
        Units.current = incoming.unit ?? .lb
        var next = incoming
        // Keep sets logged here that the phone has not heard about yet.
        if let active = next.active {
            for entry in active.entries {
                for set in entry.sets {
                    guard let mine = pending[set.id] else { continue }
                    if set.done {
                        pending[set.id] = nil
                    } else {
                        next.markLogged(setID: set.id, weight: mine.weight, reps: mine.reps)
                    }
                }
            }
        }
        if let focusedAt, incoming.sentAt < focusedAt, let mine = snapshot?.active?.currentEntryID,
           next.active?.entries.contains(where: { $0.id == mine }) == true {
            next.active?.currentEntryID = mine
        }
        snapshot = next
        if let shared = next.rest { rest.follow(shared) }
        if next.active != nil { isStarting = false }
        syncTracking()
    }

    // MARK: heart rate and Apple Health

    /// Keep the heart-rate recording in step with the workout on the phone.
    func syncTracking() {
        guard !skipsHealth, !isFinishing, let snapshot else { return }
        let savedID = UserDefaults.standard.string(forKey: Self.savedKey)

        if let active = snapshot.active {
            let wanted = active.trackHealth && savedID != active.id.uuidString
            if tracker.isRunning {
                if tracker.workoutID == nil {
                    if wanted {
                        tracker.workoutID = active.id
                        send(.tracking(workoutID: active.id))
                    } else {
                        // This workout already has a Health entry: do not record a second one.
                        Task { await tracker.end(at: Date(), save: false) }
                    }
                }
            } else if wanted, WKApplication.shared().applicationState == .active {
                // Started on the phone: pick it up here from when it began.
                let start = max(active.startedAt, Date().addingTimeInterval(-4 * 3600))
                Task {
                    if await tracker.start(at: start) {
                        tracker.workoutID = active.id
                        send(.tracking(workoutID: active.id))
                    }
                }
            }
        } else if tracker.isRunning, tracker.workoutID == nil, !isStarting {
            // Recording started but there is no workout to go with it.
            Task { await tracker.end(at: Date(), save: false) }
        } else if tracker.isRunning, let id = tracker.workoutID, !isStarting {
            // Finished or discarded on the phone.
            rest.stop()
            if let summary = snapshot.summary, summary.workoutID == id {
                let calories = tracker.calories
                let average = tracker.averageHeartRate
                Task {
                    let saved = await tracker.end(at: summary.endedAt, save: true)
                    if saved {
                        UserDefaults.standard.set(id.uuidString, forKey: Self.savedKey)
                        send(.healthSaved(workoutID: id))
                    }
                    finished = FinishedInfo(workoutID: id, title: summary.title, minutes: summary.minutes,
                                            sets: summary.sets, records: summary.records,
                                            calories: saved ? calories : nil, averageHeartRate: saved ? average : nil,
                                            savedToHealth: saved)
                }
            } else {
                Task { await tracker.end(at: Date(), save: false) }
            }
        }
    }

    /// Ask for Apple Health access when the app is first opened, not in the middle of a workout.
    func askForHealthAccess() {
        guard !skipsHealth else { return }
        Task { await tracker.authorize() }
    }

    /// The phone started a workout and opened this app to record it.
    func phoneStartedWorkout() {
        isStarting = true
        Task {
            await tracker.start(at: Date())
            refresh()
            // Give the phone a moment to answer before deciding there is no workout after all.
            try? await Task.sleep(for: .seconds(20))
            isStarting = false
            syncTracking()
        }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.receive(context)
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                self.notice = nil
                self.refresh()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
