import ActivityKit
import Foundation

/// Puts the rest countdown on the Lock Screen and in the Dynamic Island.
/// If Live Activities are turned off for the app in iOS Settings, this quietly does nothing.
@MainActor
enum RestLiveActivity {
    private static var current: Activity<RestActivityAttributes>?

    static func show(start: Date, end: Date, title: String, next: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(startDate: start, endDate: end, next: next)
        // "Stale" at the end of rest: iOS then redraws it as "Rest is over" even if the app is asleep.
        let content = ActivityContent(state: state, staleDate: end)
        if let current, current.activityState == .active || current.activityState == .stale {
            Task { await current.update(content) }
        } else {
            current = try? Activity.request(attributes: RestActivityAttributes(title: title), content: content, pushType: nil)
        }
    }

    /// Take it off the Lock Screen. Also clears any left over from an earlier run of the app.
    static func end() {
        current = nil
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
