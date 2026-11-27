import ActivityKit
import Foundation

/// Puts the rest countdown on the Lock Screen and in the Dynamic Island.
/// If Live Activities are turned off for the app in iOS Settings, this quietly does nothing.
@MainActor
enum RestLiveActivity {
    private static var current: Activity<RestActivityAttributes>?

    /// A rest countdown, or (`resting` false) the card shown between sets.
    static func show(start: Date, end: Date, title: String, next: String, resting: Bool = true, workoutStart: Date? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(startDate: start, endDate: end, next: next, resting: resting,
                                                        workoutStart: workoutStart)
        // "Stale" at the end of rest: iOS then redraws it as "Rest is over" even if the app is asleep.
        let content = ActivityContent(state: state, staleDate: resting ? end : nil)
        if let current, current.activityState == .active || current.activityState == .stale {
            Task { await current.update(content) }
        } else {
            current = try? Activity.request(attributes: RestActivityAttributes(title: title), content: content, pushType: nil)
        }
    }

    /// Pick up the card left by an earlier run of the app (the app can be relaunched in the background
    /// by the Watch mid-workout). Returns false if there is none.
    @discardableResult
    static func adopt() -> Bool {
        current = Activity<RestActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
        return current != nil
    }

    /// Take it off the Lock Screen. Also clears any left over from an earlier run of the app.
    static func end() {
        current = nil
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
