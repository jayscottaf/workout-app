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
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0

    private var endDate: Date?
    private var timer: Timer?
    private let notificationID = "rest-timer"
    /// UI tests and screenshots skip the notification permission prompt.
    private let notificationsEnabled = !ProcessInfo.processInfo.arguments.contains("-demoData")

    var isRunning: Bool { endDate != nil }
    var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / total)) : 0 }

    var text: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        startTicking()
        scheduleNotification()
    }

    func add(seconds: Int) {
        guard let endDate else { return }
        self.endDate = endDate.addingTimeInterval(TimeInterval(seconds))
        total += TimeInterval(seconds)
        tick()
        scheduleNotification()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = 0
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
            stop()
        }
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
