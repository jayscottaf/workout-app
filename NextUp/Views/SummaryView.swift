import SwiftUI
import SwiftData

/// Post-workout summary (and the detail view when opening a past workout from the calendar).
struct SummaryView: View {
    let workout: Workout
    var isFresh = false
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @AppStorage("weeklyGoal") private var weeklyGoal = 3
    @State private var confirmDelete = false
    @State private var appeared = false

    var body: some View {
        let records = workout.prSets
        let status = Streak.status(dates: Store.finished(workouts).map(\.startedAt), goal: weeklyGoal)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel(isFresh ? "Workout done" : "Workout", color: Theme.volt)
                    Text(workout.title)
                        .font(Theme.rounded(38))
                        .tracking(-0.8)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 8)

                if !records.isEmpty {
                    recordsCard(records)
                        .scaleEffect(appeared || !isFresh ? 1 : 0.9)
                        .opacity(appeared || !isFresh ? 1 : 0)
                }

                HStack(spacing: 12) {
                    stat(durationText, "time")
                    stat("\(workout.completedSets.count)", "sets")
                    stat(Int(workout.totalVolume).formatted(), "lb moved")
                }

                VStack(alignment: .leading, spacing: 10) {
                    CapsLabel("What it means")
                    Text(Store.summaryText(workout))
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()

                if isFresh { weekCard(status) }

                VStack(alignment: .leading, spacing: 12) {
                    CapsLabel("What you did")
                    ForEach(workout.sortedEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.system(size: 15, weight: .bold))
                            Text(setsLine(entry))
                                .font(.system(size: 14))
                                .monospacedDigit()
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .card()

                if !isFresh {
                    Button("Delete this workout", role: .destructive) { confirmDelete = true }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        .screen()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if workout.savedToHealth {
                    Label("Saved to Apple Health", systemImage: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.text, foreground: Theme.onVolt))
                    .accessibilityIdentifier("summaryDone")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.bg)
        }
        .onAppear {
            guard isFresh else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.15)) { appeared = true }
            if !records.isEmpty { Haptics.success() }
        }
        .confirmationDialog("Delete this workout? Its sets will no longer count toward suggestions or records.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                onDone()
                let store = context
                let removed = workout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    store.delete(removed)
                    try? store.save()
                }
            }
            Button("Keep it", role: .cancel) {}
        }
    }

    private var subtitle: String {
        var parts = [workout.startedAt.longDay]
        if !workout.gymName.isEmpty { parts.append(workout.gymName) }
        if workout.isQuick { parts.append("20 minute version") }
        return parts.joined(separator: " · ")
    }

    private var durationText: String {
        let seconds = Int((workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func setsLine(_ entry: ExerciseEntry) -> String {
        entry.completedSets.map { set in
            set.weight > 0 ? "\(Fmt.weight(set.weight)) × \(set.reps)" : "\(set.reps) reps"
        }.joined(separator: ",  ")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.rounded(24))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 14, radius: 20)
        .accessibilityElement(children: .combine)
    }

    private func recordsCard(_ records: [SetEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").font(.system(size: 22, weight: .bold))
                Text("\(records.count) personal record\(records.count == 1 ? "" : "s")")
                    .font(Theme.rounded(22))
            }
            VStack(spacing: 8) {
                ForEach(records) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(set.entry?.name ?? "Exercise").font(.system(size: 15, weight: .heavy))
                            Text(set.prKind?.text(weight: set.weight, reps: set.reps) ?? "Personal record")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.onVoltSoft)
                        }
                        Spacer(minLength: 8)
                        Text(set.weight > 0 ? "\(Fmt.weight(set.weight)) × \(set.reps)" : "\(set.reps) reps")
                            .font(Theme.rounded(18))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.onVolt.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .foregroundStyle(Theme.onVolt)
        .card(padding: 20, radius: 28, color: Theme.volt)
    }

    private func weekCard(_ status: WeekStatus) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(status.goalReached
                     ? "Week goal reached: \(status.thisWeek) of \(status.goal)"
                     : "\(status.thisWeek) of \(status.goal) this week")
                    .font(.system(size: 16, weight: .bold))
                Text(weekDetail(status))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<status.goal, id: \.self) { i in
                    Capsule()
                        .fill(i < status.thisWeek ? Theme.volt : Theme.line)
                        .frame(width: 12, height: 28)
                }
            }
            .accessibilityHidden(true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func weekDetail(_ status: WeekStatus) -> String {
        if status.goalReached {
            return status.streak > 1 ? "That makes \(status.streak) weeks in a row" : "First week of a new streak"
        }
        return "\(status.remaining) more to reach your weekly goal"
    }
}
