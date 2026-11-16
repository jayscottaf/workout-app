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
    }

    /// The workout's name, e.g. "Chest & triceps".
    var title: String
}
#endif
