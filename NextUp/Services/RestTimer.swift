import Foundation
import UIKit
import UserNotifications

/// The rest length chosen in Settings. 0 means automatic (each exercise's own rest).
enum RestSetting {
    static let key = "restSeconds"
    static let choices = [0, 30, 45, 60, 75, 90, 105, 120, 150, 180, 240, 300]

    static var current: Int { UserDefaults.standard.integer(forKey: key) }

    /// The countdown to use after a set, given the exercise's own rest.
    static func seconds(default exerciseRest: Int) -> Int {
        current > 0 ? current : exerciseRest
    }

    static func step(_ value: Int, by offset: Int) -> Int {
        let index = choices.firstIndex(of: value) ?? 0
        return choices[min(max(index + offset, 0), choices.count - 1)]
    }

    static func label(_ seconds: Int) -> String {
        seconds == 0 ? "Automatic" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The automatic rest countdown that starts when a set is logged.
@MainActor
final class RestTimer: ObservableObject {
    /// One countdown for the whole app, shared with the Apple Watch.
    static let shared = RestTimer()

    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0

    private var endDate: Date?
    private var timer: Timer?
    private let notificationID = "rest-timer"
    /// UI tests and screenshots skip the notification permission prompt.
    private let notificationsEnabled = !ProcessInfo.processInfo.arguments.contains("-demoData")
    /// The Lock Screen countdown. Off for UI tests and screenshots unless `-restActivity` asks for it.
    private let liveActivityEnabled = !ProcessInfo.processInfo.arguments.contains("-demoData")
        || ProcessInfo.processInfo.arguments.contains("-restActivity")
    private var title = ""
    private var next = ""
    /// When the countdown was last started, lengthened or skipped here or on the Watch. The newest change wins.
    private(set) var changedAt: Date?
    /// Called after a change made on this phone, so the Watch can follow.
    var onChange: (() -> Void)?

    /// What the Watch should show.
    var shared: WatchRest? {
        changedAt.map { WatchRest(endsAt: endDate, total: total, changedAt: $0) }
    }

    /// A workout is open: the Lock Screen card stays up between rests.
    private var inWorkout = false

    init() {}

    /// At launch: keep the Lock Screen card if a workout is still in progress, else clear any left over.
    func resume(workoutTitle: String?) {
        guard liveActivityEnabled else { return }
        if let workoutTitle {
            inWorkout = true
            title = workoutTitle
            RestLiveActivity.adopt()
        } else {
            RestLiveActivity.end()
        }
    }

    /// The workout screen is open (the app is in front, so iOS lets it put up the Lock Screen card).
    func beginWorkout(title: String, next: String) {
        inWorkout = true
        self.title = title
        self.next = next
        if !isRunning { showBetweenSets() }
    }

    /// The workout was finished or discarded.
    func endWorkout() {
        inWorkout = false
        stop()
        if liveActivityEnabled { RestLiveActivity.end() }
    }

    var isRunning: Bool { endDate != nil }
    var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / total)) : 0 }

    var text: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `title` is the workout's name and `next` says what comes after the rest; both are shown on the Lock Screen.
    func start(seconds: Int, title: String = "", next: String = "") {
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        self.title = title
        self.next = next
        startTicking()
        scheduleNotification()
        showLiveActivity()
        changed()
    }

    func add(seconds: Int) {
        guard let endDate else { return }
        self.endDate = endDate.addingTimeInterval(TimeInterval(seconds))
        total += TimeInterval(seconds)
        tick()
        scheduleNotification()
        showLiveActivity()
        changed()
    }

    func stop() {
        let wasRunning = isRunning
        clear()
        if wasRunning { changed() }
    }

    /// Follow a countdown started, lengthened or skipped on the Watch, if it is newer than this one.
    func follow(_ rest: WatchRest, title: String, next: String = "") {
        if let changedAt, rest.changedAt <= changedAt { return }
        changedAt = rest.changedAt
        guard let end = rest.endsAt, end > Date() else {
            clear()
            return
        }
        endDate = end
        total = max(rest.total, end.timeIntervalSinceNow)
        remaining = end.timeIntervalSinceNow
        if !title.isEmpty { self.title = title }
        if !next.isEmpty { self.next = next }
        startTicking()
        scheduleNotification()
        showLiveActivity()
    }

    private func changed() {
        changedAt = Date()
        onChange?()
    }

    private func clear() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = 0
        if inWorkout { showBetweenSets() } else if liveActivityEnabled { RestLiveActivity.end() }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            clear()
        }
    }

    private func showBetweenSets() {
        guard liveActivityEnabled else { return }
        let now = Date()
        RestLiveActivity.show(start: now, end: now, title: title, next: next, resting: false)
    }

    private func showLiveActivity() {
        guard liveActivityEnabled, let endDate else { return }
        RestLiveActivity.show(start: endDate.addingTimeInterval(-total), end: endDate, title: title, next: next)
    }

    /// So the phone still buzzes if the app is in the background when rest ends.
    private func scheduleNotification() {
        guard notificationsEnabled, let endDate else { return }
        let center = UNUserNotificationCenter.current()
        let id = notificationID
        let delay = max(1, endDate.timeIntervalSinceNow)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Rest is over"
            content.body = "Time for your next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
