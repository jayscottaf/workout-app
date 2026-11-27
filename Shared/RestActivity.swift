#if os(iOS)
import ActivityKit
import Foundation

/// What the rest countdown on the Lock Screen and in the Dynamic Island shows.
/// Shared by the iPhone app (which starts it) and the small extension that draws it.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        /// "Next: Bench press · 135 lb × 8"
        var next: String
        /// false between sets: the card stays up for the whole workout so a rest started on the Watch
        /// can show while the phone is locked (iOS only lets a locked app update a card, not start one).
        /// nil on cards from older builds, which were always resting.
        var resting: Bool?
        /// When the workout started: between sets the card counts the workout time up from here.
        /// nil on cards from older builds, which show "Go" instead.
        var workoutStart: Date? = nil
    }

    /// The workout's name, e.g. "Chest & triceps".
    var title: String
}
#endif
