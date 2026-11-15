import Foundation
import UIKit
import UserNotifications

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
