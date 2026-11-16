import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NextUpRestBundle: WidgetBundle {
    var body: some Widget {
        RestActivityWidget()
    }
}

private enum Look {
    static let volt = Color(red: 0xC8 / 255, green: 0xF0 / 255, blue: 0x4A / 255)
    static let muted = Color(red: 0x9B / 255, green: 0xA5 / 255, blue: 0x9E / 255)
    static let bg = Color(red: 0x0A / 255, green: 0x0C / 255, blue: 0x0B / 255)
}

/// The rest countdown shown on the Lock Screen and in the Dynamic Island while the phone is locked
/// or another app is open. The countdown is drawn by iOS itself, so it keeps ticking with the app asleep.
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenView(state: context.state, title: context.attributes.title, isOver: context.isStale)
                .activityBackgroundTint(Look.bg.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Rest over" : "Rest", systemImage: "timer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Look.volt)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state, isOver: context.isStale)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 90, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.next)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !context.isStale {
                            ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: true,
                                         label: { EmptyView() }, currentValueLabel: { EmptyView() })
                                .tint(Look.volt)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Look.volt)
            } compactTrailing: {
                Countdown(state: context.state, isOver: context.isStale)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Look.volt)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Look.volt)
            }
        }
    }
}

/// "1:27" counting down, or "Go" once rest is over.
private struct Countdown: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        if isOver || state.endDate <= state.startDate {
            Text("Go")
        } else {
            Text(timerInterval: state.startDate...state.endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LockScreenView: View {
    let state: RestActivityAttributes.ContentState
    let title: String
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOver ? "REST IS OVER" : "REST")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Look.volt)
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Look.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Countdown(state: state, isOver: isOver)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            if !isOver {
                ProgressView(timerInterval: state.startDate...state.endDate, countsDown: true,
                             label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .tint(Look.volt)
            }
            Text(state.next)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(16)
    }
}
