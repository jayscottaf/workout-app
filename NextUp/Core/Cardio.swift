import Foundation

/// Kinds of cardio read from Apple Health. Recording stays with Apple Fitness and the Watch;
/// Next Up only shows what was done and, if you like, counts it toward your week.
enum CardioKind: String, CaseIterable, Codable {
    case run, walk, cycle, elliptical, stairs, hike, row, swim, hiit, other

    var title: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Ride"
        case .elliptical: return "Elliptical"
        case .stairs: return "Stairs"
        case .hike: return "Hike"
        case .row: return "Row"
        case .swim: return "Swim"
        case .hiit: return "Intervals"
        case .other: return "Cardio"
        }
    }

    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .elliptical: return "figure.elliptical"
        case .stairs: return "figure.stair.stepper"
        case .hike: return "figure.hiking"
        case .row: return "figure.rower"
        case .swim: return "figure.pool.swim"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .other: return "heart.circle"
        }
    }
}

/// Whether cardio from Apple Health counts toward the weekly goal and streak. On unless turned off.
enum CardioSetting {
    static let key = "cardioCountsTowardGoal"
}

/// "2 lifts + 1 cardio", for the week card.
enum WeekText {
    static func breakdown(lifts: Int, cardio: Int) -> String {
        let liftText = "\(lifts) lift\(lifts == 1 ? "" : "s")"
        return cardio > 0 ? "\(liftText) + \(cardio) cardio" : liftText
    }
}
