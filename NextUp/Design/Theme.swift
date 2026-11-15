import SwiftUI
import UIKit

// The look of the app: near-black ground, one "volt" accent, blue for cardio,
// rounded heavy numerals. Matches the design canvas.

enum Theme {
    static let bg = Color(hex: 0x0A0C0B)
    static let surface = Color(hex: 0x151917)
    static let surface2 = Color(hex: 0x1E2421)
    static let line = Color(hex: 0x2A312D)
    static let text = Color(hex: 0xF2F5F0)
    static let muted = Color(hex: 0x9BA59E)
    static let faint = Color(hex: 0x5E6862)
    static let volt = Color(hex: 0xC8F04A)
    static let voltDim = Color(hex: 0x1A210D)
    static let onVolt = Color(hex: 0x0A0C0B)
    static let onVoltSoft = Color(hex: 0x2A3312)
    static let blue = Color(hex: 0x6FB6FF)
    static let blueDim = Color(hex: 0x16263A)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Small all-caps section label.
struct CapsLabel: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    var color: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 22, color: Color = Theme.surface) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, color: color))
    }

    /// Standard screen background and text colour.
    func screen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Keeps scrolled content from showing through behind the clock and battery.
                Color.clear.frame(height: 0).background(Theme.bg)
            }
    }
}

/// Big filled capsule button (volt by default).
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.volt
    var foreground: Color = Theme.onVolt
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Compact capsule button used for chips and secondary actions.
struct ChipButtonStyle: ButtonStyle {
    var fill: Color = Theme.surface
    var foreground: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Round 44pt icon button (plus, minus, etc).
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var fill: Color = Theme.surface2
    var foreground: Color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Row of small bars, e.g. 2 of 3 workouts this week.
struct SegmentBar: View {
    let filled: Int
    let total: Int
    var height: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Theme.volt : Theme.line)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension Date {
    /// "Sunday, Nov 15"
    var longDay: String { formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
    /// "Thu, Nov 12"
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
