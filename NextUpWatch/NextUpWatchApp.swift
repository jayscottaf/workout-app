import HealthKit
import SwiftUI
import WatchKit

@main
struct NextUpWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.rest)
                .environmentObject(model.tracker)
                .tint(Look.volt)
        }
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchModel.shared.activate() }
    }

    func applicationDidBecomeActive() {
        Task { @MainActor in
            WatchModel.shared.askForHealthAccess()
            WatchModel.shared.refresh()
            WatchModel.shared.syncTracking()
        }
    }

    /// The iPhone started a workout and asked the Watch to record it.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in WatchModel.shared.phoneStartedWorkout() }
    }
}

/// Colours and type, matching the iPhone app.
enum Look {
    static let volt = Color(red: 0xC8 / 255, green: 0xF0 / 255, blue: 0x4A / 255)
    static let onVolt = Color(red: 0x0A / 255, green: 0x0C / 255, blue: 0x0B / 255)
    static let onVoltSoft = Color(red: 0x2A / 255, green: 0x33 / 255, blue: 0x12 / 255)
    static let surface = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let surface2 = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    static let muted = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255)
    static let red = Color(red: 1, green: 0x69 / 255, blue: 0x61 / 255)
    static let redDim = Color(red: 0x3A / 255, green: 0x1A / 255, blue: 0x18 / 255)
    static let orange = Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func weight(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A full-width pill button, like the ones on the phone.
struct PillStyle: ButtonStyle {
    var fill: Color = Look.volt
    var foreground: Color = Look.onVolt
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Caps: View {
    let text: String
    var color: Color = Look.muted

    init(_ text: String, color: Color = Look.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        NavigationStack {
            if let done = model.finished {
                SummaryScreen(info: done)
            } else if let active = model.snapshot?.active {
                WorkoutScreen(workout: active)
            } else {
                TodayScreen()
            }
        }
    }
}
