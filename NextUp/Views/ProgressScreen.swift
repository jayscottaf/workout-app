import SwiftUI
import SwiftData
import Charts

private struct StrengthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct LiftOption: Identifiable, Hashable {
    let id: String // history key
    let label: String
    let sessions: Int
}

/// Records, estimated strength chart, weekly volume per muscle group, calendar and monthly recap.
struct ProgressScreen: View {
    @EnvironmentObject private var health: HealthService
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var selectedKey: String?
    @State private var month = Date()
    @State private var opened: Workout?

    var body: some View {
        let finished = Store.finished(workouts)
        let history = History(finished.map(\.record))

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progress")
                    .font(Theme.rounded(34))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 2)

                if finished.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing to chart yet").font(.system(size: 17, weight: .bold))
                        Text("Finish your first workout and your records, strength trend and calendar will show up here.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                    .card()
                } else {
                    strengthCard(finished: finished, history: history)
                    volumeCard(history: history)
                    recordsCard(finished: finished)
                }
                calendarCard(finished: finished)
                RecapCard(month: month)
                if let weight = health.bodyWeight {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            CapsLabel("Body weight")
                            Text("\(String(format: "%.1f", weight)) lb").font(Theme.rounded(24))
                        }
                        Spacer()
                        Text("from Apple Health\(health.bodyWeightDate.map { " · \($0.shortDay)" } ?? "")")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .card()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screen()
        .sheet(item: $opened) { workout in
            SummaryView(workout: workout, isFresh: false) { opened = nil }
        }
    }

    // MARK: strength

    private func liftOptions(_ finished: [Workout]) -> [LiftOption] {
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        for workout in finished {
            for entry in workout.entries where !entry.completedSets.isEmpty && !entry.isBodyweight {
                counts[entry.historyKey, default: 0] += 1
                if labels[entry.historyKey] == nil {
                    let onMachine = entry.historyKey.contains("@") && !workout.gymName.isEmpty
                    labels[entry.historyKey] = onMachine ? "\(entry.name) · \(workout.gymName)" : entry.name
                }
            }
        }
        return counts
            .map { LiftOption(id: $0.key, label: labels[$0.key] ?? $0.key, sessions: $0.value) }
            .sorted { $0.sessions != $1.sessions ? $0.sessions > $1.sessions : $0.label < $1.label }
    }

    @ViewBuilder
    private func strengthCard(finished: [Workout], history: History) -> some View {
        let options = liftOptions(finished)
        if let chosen = options.first(where: { $0.id == selectedKey }) ?? options.first {
            let points = Stats.strengthSeries(history.sessions(for: chosen.id)).map { StrengthPoint(date: $0.date, value: $0.value) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    CapsLabel("Estimated strength")
                    Spacer()
                    Menu {
                        ForEach(options) { option in
                            Button(option.label) { selectedKey = option.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(chosen.label).lineLimit(1)
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.volt)
                        .frame(minHeight: 44, alignment: .top)
                    }
                    .accessibilityLabel("Exercise shown: \(chosen.label). Change exercise")
                }
                .padding(.bottom, -18)

                if let latest = points.last, let first = points.first {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(latest.value.rounded())) lb").font(Theme.rounded(28))
                        Text(changeText(first: first, latest: latest, count: points.count))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(latest.value >= first.value ? Theme.volt : Theme.muted)
                    }
                }

                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Estimated max", point.value))
                        .foregroundStyle(Theme.volt)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Date", point.date), y: .value("Estimated max", point.value))
                        .foregroundStyle(Theme.volt)
                        .symbolSize(28)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel().foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Chart of estimated strength for \(chosen.label) over \(points.count) sessions")

                Text("The most you could likely lift once, worked out from your sets.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }

    private func changeText(first: StrengthPoint, latest: StrengthPoint, count: Int) -> String {
        guard count > 1 else { return "first session logged" }
        let change = Int((latest.value - first.value).rounded())
        let since = first.date.formatted(.dateTime.month(.abbreviated).day())
        if change > 0 { return "up \(change) lb since \(since)" }
        if change < 0 { return "down \(-change) lb since \(since)" }
        return "level since \(since)"
    }

    // MARK: volume

    private func volumeCard(history: History) -> some View {
        let sets = Stats.weeklySets(history.workouts, weekOf: Date())
        let groups = MuscleGroup.allCases.sorted { (sets[$0] ?? 0) > (sets[$1] ?? 0) }
        let top = max(sets.values.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Sets this week, by muscle group")
            VStack(spacing: 8) {
                ForEach(groups, id: \.self) { group in
                    let count = sets[group] ?? 0
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 13))
                            .frame(width: 72, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line)
                                Capsule().fill(Theme.volt)
                                    .frame(width: count == 0 ? 0 : max(8, proxy.size.width * Double(count) / Double(top)))
                            }
                        }
                        .frame(height: 8)
                        Text("\(count)")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                            .frame(width: 22, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.title): \(count) sets")
                }
            }
        }
        .card()
    }

    // MARK: records

    @ViewBuilder
    private func recordsCard(finished: [Workout]) -> some View {
        let records: [(set: SetEntry, workout: Workout)] = finished
            .flatMap { workout in workout.prSets.map { (set: $0, workout: workout) } }
            .sorted { ($0.set.completedAt ?? .distantPast) > ($1.set.completedAt ?? .distantPast) }
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Recent personal records")
            if records.isEmpty {
                Text("No records yet. They start counting from your second session on each exercise.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(records.prefix(5).enumerated()), id: \.element.set.id) { index, item in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.set.entry?.name ?? "Exercise").font(.system(size: 15, weight: .bold))
                        Text(recordDetail(item.set, item.workout))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(item.set.weight > 0 ? "\(Fmt.weight(item.set.weight)) lb × \(item.set.reps)" : "\(item.set.reps) reps")
                        .font(.system(size: 15, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.volt)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func recordDetail(_ set: SetEntry, _ workout: Workout) -> String {
        var parts = [set.prKind?.text(weight: set.weight, reps: set.reps) ?? "Personal record", workout.startedAt.shortDay]
        if set.entry?.historyKey.contains("@") == true, !workout.gymName.isEmpty { parts.append(workout.gymName) }
        return parts.joined(separator: " · ")
    }

    // MARK: calendar

    private func calendarCard(finished: [Workout]) -> some View {
        let calendar = Calendar.current
        let days = monthDays(calendar)
        let lifting = Dictionary(grouping: finished) { calendar.startOfDay(for: $0.startedAt) }
        let cardio = Set(health.cardio.map { calendar.startOfDay(for: $0.date) })
        let symbols = weekdaySymbols(calendar)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CapsLabel(month.formatted(.dateTime.month(.wide).year()))
                Spacer()
                CircleIconButton(systemName: "chevron.left", label: "Previous month", fill: Theme.surface2) { shiftMonth(-1) }
                CircleIconButton(systemName: "chevron.right", label: "Next month", fill: Theme.surface2) { shiftMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, workout: lifting[day]?.first, hasCardio: cardio.contains(day), calendar: calendar)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Theme.volt, "Lifting")
                legend(Theme.blue, "Cardio")
                Spacer()
                Text("Tap a lifting day to open it")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date, workout: Workout?, hasCardio: Bool, calendar: Calendar) -> some View {
        let number = calendar.component(.day, from: day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()
        if let workout {
            Button { opened = workout } label: {
                Text("\(number)")
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onVolt)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Theme.volt, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.shortDay): \(workout.title). Open workout")
        } else {
            Text("\(number)")
                .font(.system(size: 13, weight: hasCardio ? .heavy : .semibold))
                .monospacedDigit()
                .foregroundStyle(hasCardio ? Theme.blue : (isFuture ? Theme.faint : Theme.muted))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(hasCardio ? Theme.blueDim : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isToday ? Theme.text : Color.clear, lineWidth: 2))
                .accessibilityLabel("\(day.shortDay)\(hasCardio ? ": cardio" : "")\(isToday ? ", today" : "")")
        }
    }

    private func shiftMonth(_ by: Int) {
        month = Calendar.current.date(byAdding: .month, value: by, to: month) ?? month
    }

    /// Days of the shown month, with leading blanks so the 1st lands under the right weekday.
    private func monthDays(_ calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let blanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: blanks)
        for offset in 0..<count {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return days
    }

    private func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

/// The monthly recap, written as plain sentences.
struct RecapCard: View {
    let month: Date
    @EnvironmentObject private var health: HealthService
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    var body: some View {
        let recap = makeRecap()
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("\(recap.monthTitle) recap")
            if recap.workouts > 0 {
                HStack(spacing: 18) {
                    figure("\(recap.workouts)", "workouts")
                    figure("\(recap.sets)", "sets")
                    figure("\(recap.records)", "records")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recap.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.rounded(26)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func makeRecap() -> MonthlyRecap {
        let calendar = Calendar.current
        let cardio = health.cardio.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        return Recap.make(for: month, history: Store.history(workouts), cardioSessions: cardio.count,
                          cardioMiles: cardio.reduce(0) { $0 + ($1.miles ?? 0) }, calendar: calendar)
    }
}

struct RecapSheet: View {
    let month: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly recap")
                .font(Theme.rounded(28))
                .accessibilityAddTraits(.isHeader)
            RecapCard(month: month)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .padding(.top, 12)
        .screen()
        .presentationDetents([.medium, .large])
    }
}
