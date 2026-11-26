import Foundation

/// Your routine: the days and their exercises. Saved on the phone and shared with the planning rules.
@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()
    private static let key = "routineDays"

    /// Sample-data runs (screenshots and UI tests) always start from the original three days and save nothing.
    private let demo = ProcessInfo.processInfo.arguments.contains("-demoData")

    @Published var days: [DayType] {
        didSet {
            guard days != oldValue else { return }
            Routine.days = days
            if !demo, let data = try? JSONEncoder().encode(days) {
                UserDefaults.standard.set(data, forKey: RoutineStore.key)
            }
            // The Watch shows the next day too.
            WatchLink.shared.push()
        }
    }

    private init() {
        var saved: [DayType] = []
        if !demo, let data = UserDefaults.standard.data(forKey: RoutineStore.key) {
            saved = (try? JSONDecoder().decode([DayType].self, from: data)) ?? []
        }
        days = saved.isEmpty ? Presets.classic.days : saved
        Routine.days = days
    }

    /// Which ready-made routine this is, if it has not been changed.
    var preset: RoutinePreset? { Presets.all.first { $0.days == days } }

    func use(_ preset: RoutinePreset) { days = preset.days }

    func addDay() {
        days.append(DayType(title: "Day \(days.count + 1)", exercises: []))
    }
}
