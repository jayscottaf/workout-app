import SwiftUI
import WatchKit

// MARK: - Today

/// First screen: the workout that is next, with Start and the 20 minute version.
struct TodayScreen: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = model.snapshot?.next {
                Caps("Day \(next.dayNumber) of \(next.dayCount ?? 3)")
                    .padding(.top, 6)
                Text(next.title)
                    .font(Look.rounded(24))
                    .tracking(-0.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
                    .accessibilityAddTraits(.isHeader)
                Text("\(next.exerciseCount) exercises · \(next.minutes) min")
                    .font(.system(size: 13))
                    .foregroundStyle(Look.muted)
                    .padding(.top, 4)
                Spacer(minLength: 4)
                if let notice = model.notice {
                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(Look.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
                HStack(spacing: 6) {
                    Button(model.isStarting ? "Starting" : "Start") { model.start(quick: false) }
                        .buttonStyle(PillStyle())
                        .accessibilityIdentifier("start")
                    Button { model.start(quick: true) } label: {
                        Text("20 min")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Look.volt)
                            .frame(width: 62, height: 40)
                            .overlay(Capsule().strokeBorder(Look.volt, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start the 20 minute version")
                }
                .disabled(model.isStarting)
            } else {
                Spacer()
                Text("Open Next Up on your iPhone")
                    .font(Look.rounded(17, .bold))
                Text("Your workouts live on the phone. Keep it nearby and this screen fills in.")
                    .font(.system(size: 12))
                    .foregroundStyle(Look.muted)
                    .padding(.top, 4)
                Spacer()
                Button("Try again") { model.refresh() }
                    .buttonStyle(PillStyle(fill: Look.surface2, foreground: .white))
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle {
            Text("Next Up").foregroundStyle(Look.volt)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout

/// A workout in progress: swipe between logging sets and the live numbers.
struct WorkoutScreen: View {
    let workout: WatchWorkout
    @EnvironmentObject private var model: WatchModel
    @State private var entryID: UUID?
    @State private var page = UserDefaults.standard.string(forKey: "demoScreen") == "live" ? 1 : 0

    private var position: Int {
        if let entryID, let index = workout.entries.firstIndex(where: { $0.id == entryID }) { return index }
        return workout.firstOpenIndex ?? max(workout.entries.count - 1, 0)
    }

    var body: some View {
        let entry = workout.entries.indices.contains(position) ? workout.entries[position] : nil
        TabView(selection: $page) {
            LogPage(workout: workout, entry: entry, position: position, entryID: $entryID)
                .tag(0)
            LivePage(workout: workout, entry: entry, position: position)
                .tag(1)
        }
        .tabViewStyle(.page)
        // Stay on the same exercise as the phone: follow it when it moves, and tell it when this Watch moves.
        .onChange(of: workout.currentEntryID, initial: true) { _, id in
            if let id, id != entryID, workout.entries.contains(where: { $0.id == id }) { entryID = id }
        }
        .onChange(of: entry?.id) { _, id in
            if let id, id != workout.currentEntryID { model.focus(id) }
        }
        .navigationTitle {
            Text(page == 0 ? (entry?.name ?? workout.title) : workout.title)
                .foregroundStyle(Look.volt)
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let record = model.record {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                    Text(record).lineLimit(2).minimumScaleFactor(0.8)
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Look.onVolt)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Look.volt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.spring(duration: 0.35), value: model.record)
    }
}

/// Log a set: tap weight or reps, turn the crown to change it, then Log set.
struct LogPage: View {
    let workout: WatchWorkout
    let entry: WatchEntry?
    let position: Int
    @Binding var entryID: UUID?

    @EnvironmentObject private var model: WatchModel
    @EnvironmentObject private var rest: RestClock
    @State private var weight: Double = 0
    /// What the crown turns. The weight shown and logged is this, snapped to the exercise's step.
    @State private var crown: Double = 0
    @State private var reps: Double = 8
    @State private var showList = false
    @FocusState private var focus: Field?

    private enum Field { case weight, reps }

    var body: some View {
        Group {
            if rest.isRunning {
                RestView(next: nextText)
            } else if let entry, let set = entry.nextSet {
                logging(entry, set)
            } else {
                allDone
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showList) { exerciseList }
    }

    private func logging(_ entry: WatchEntry, _ set: WatchSet) -> some View {
        // The plates line needs room: everything else sits a little tighter when it shows.
        let plates = entry.bar.flatMap { Plates.text(total: weight, bar: $0) }
        return VStack(spacing: plates == nil ? 5 : 2) {
            Button { showList = true } label: {
                HStack(spacing: 4) {
                    Caps("Set \(set.index + 1) of \(entry.sets.count)")
                    Spacer(minLength: 2)
                    Text("\(position + 1) of \(workout.entries.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Look.muted)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Look.muted)
                }
                .frame(minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exercise \(position + 1) of \(workout.entries.count). Choose another exercise")

            HStack(spacing: 6) {
                box(value: weight <= 0 ? "BW" : Look.weight(weight),
                    unit: weight <= 0 ? "body" : "\(Units.symbol) · ±\(Look.weight(step(entry)))", active: focus == .weight)
                    .focusable()
                    .focused($focus, equals: .weight)
                    .digitalCrownRotation($crown, from: 0, through: 1500, by: step(entry),
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel(weight <= 0 ? "Body weight" : "\(Look.weight(weight)) \(Units.spoken)")
                    .accessibilityHint("Turn the crown to change the weight")
                box(value: "\(Int(reps))", unit: "reps", active: focus == .reps)
                    .focusable()
                    .focused($focus, equals: .reps)
                    .digitalCrownRotation($reps, from: 1, through: 100, by: 1,
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel("\(Int(reps)) reps")
                    .accessibilityHint("Turn the crown to change the reps")
            }
            .frame(height: plates == nil ? 58 : 52)

            Text(lastText(set))
                .font(.system(size: 12))
                .foregroundStyle(Look.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            if let plates {
                Text(plates)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Look.volt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                    .accessibilityIdentifier("platesLine")
            }

            Spacer(minLength: 0)

            Button {
                model.log(set, in: entry, weight: weight, reps: Int(reps))
                // After the last set of this exercise, move on to the next one with sets left.
                if entry.sets.filter({ !$0.done }).count <= 1 { entryID = nil }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                    Text("Log set")
                }
            }
            .buttonStyle(PillStyle(height: plates == nil ? 40 : 37))
            .doubleTapToPress()
            .accessibilityIdentifier("logSet")
        }
        .onChange(of: set.id, initial: true) { _, _ in
            weight = set.weight
            crown = set.weight
            reps = Double(set.reps)
            if focus == nil { focus = .weight }
        }
        .onChange(of: set.weight) { _, value in
            weight = value
            crown = value
        }
        .onChange(of: crown) { _, value in
            // The crown can stop between steps (127.3): always show and log a real weight.
            weight = Self.snap(value, to: step(entry))
        }
        .onChange(of: entry.increment) { _, _ in
            weight = Self.snap(weight, to: step(entry))
            crown = weight
        }
    }

    private func step(_ entry: WatchEntry) -> Double { max(entry.increment, 0.5) }

    static func snap(_ value: Double, to step: Double) -> Double {
        guard step > 0 else { return value }
        return max(0, (value / step).rounded() * step)
    }

    private func box(value: String, unit: String, active: Bool) -> some View {
        VStack(spacing: -3) {
            Text(value)
                .font(Look.rounded(26))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(Look.muted)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(active ? Look.volt : .clear, lineWidth: 2)
        )
        .focusEffectDisabled()
    }

    private func lastText(_ set: WatchSet) -> String {
        guard let lastReps = set.lastReps else { return "First time · crown changes it" }
        if let lastWeight = set.lastWeight, lastWeight > 0 {
            return "Last time \(Look.weight(lastWeight)) × \(lastReps)"
        }
        return "Last time \(lastReps) reps"
    }

    private var nextText: String {
        guard let index = workout.firstOpenIndex else { return "" }
        let upcoming = entryID.flatMap { id in workout.entries.first { $0.id == id && !$0.isDone } } ?? workout.entries[index]
        guard let set = upcoming.nextSet else { return "" }
        let amount = set.weight > 0 ? "\(Look.weight(set.weight)) × \(set.reps)" : "\(set.reps) reps"
        if upcoming.id == entry?.id { return "Next: set \(set.index + 1) · \(amount)" }
        return "Next: \(upcoming.name)"
    }

    private var allDone: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Look.volt)
            Text(workout.setsLeft == 0 ? "All sets done" : "This exercise is done")
                .font(Look.rounded(17, .bold))
            Spacer(minLength: 0)
            if workout.setsLeft == 0 {
                Button(model.isFinishing ? "Saving" : "Finish workout") { model.finish() }
                    .buttonStyle(PillStyle())
                    .disabled(model.isFinishing)
            } else {
                Button("Next exercise") { entryID = nil }
                    .buttonStyle(PillStyle())
            }
        }
    }

    private static var steps: [Double] { Units.stepChoices() }

    /// Opened from the top line: weight steps and Later for this exercise, every exercise, and Add.
    private var exerciseList: some View {
        NavigationStack {
            List {
                if let entry, !entry.isDone {
                    Section {
                        if true {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Weight steps").font(.system(size: 12)).foregroundStyle(Look.muted)
                                HStack(spacing: 4) {
                                    ForEach(Self.steps, id: \.self) { value in
                                        let chosen = value == entry.increment
                                        Button {
                                            model.setStep(value, for: entry)
                                        } label: {
                                            Text(Look.weight(value))
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(chosen ? Look.onVolt : .white)
                                                .frame(maxWidth: .infinity, minHeight: 32)
                                                .background(chosen ? Look.volt : Look.surface2, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(Look.weight(value)) \(Units.isKg ? "kilogram" : "pound") steps\(chosen ? ", chosen" : "")")
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        if workout.entries.contains(where: { $0.id != entry.id && !$0.isDone }) {
                            Button {
                                model.doLater(entry)
                                entryID = nil
                                showList = false
                            } label: {
                                Label("Do this one later", systemImage: "clock.arrow.circlepath")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .accessibilityIdentifier("doLater")
                        }
                    } header: {
                        Text(entry.name)
                    }
                }
                Section("Exercises") {
                    ForEach(Array(workout.entries.enumerated()), id: \.element.id) { offset, item in
                        Button {
                            entryID = item.id
                            showList = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.system(size: 15, weight: .semibold))
                                    Text("\(item.sets.filter(\.done).count) of \(item.sets.count) sets")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Look.muted)
                                }
                                Spacer()
                                if item.isDone {
                                    Image(systemName: "checkmark").foregroundStyle(Look.volt)
                                } else if offset == position {
                                    Circle().fill(Look.volt).frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        AddExerciseList(onAdded: { showList = false })
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Look.volt)
                    }
                    .accessibilityIdentifier("addExercise")
                }
            }
        }
    }
}

/// Exercises the gym can do, by muscle group. The phone sends the list.
struct AddExerciseList: View {
    let onAdded: () -> Void
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        Group {
            if let options = model.addOptions {
                let groups = options.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
                if options.isEmpty {
                    Text("Nothing else is set up for this gym.")
                        .font(.system(size: 14)).foregroundStyle(Look.muted)
                } else {
                    List(groups, id: \.self) { group in
                        NavigationLink(group) {
                            List(options.filter { $0.group == group }) { option in
                                Button(option.name) {
                                    model.add(option)
                                    onAdded()
                                }
                                .font(.system(size: 15, weight: .semibold))
                            }
                            .navigationTitle(group)
                        }
                    }
                }
            } else if let notice = model.notice {
                Text(notice).font(.system(size: 14)).foregroundStyle(Look.orange)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Add")
        .onAppear { model.askForAdds() }
    }
}

extension View {
    /// On newer Watches, pinching finger and thumb twice presses this button.
    @ViewBuilder
    func doubleTapToPress() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

/// The rest countdown, shown after a set is logged.
struct RestView: View {
    let next: String
    @EnvironmentObject private var rest: RestClock

    var body: some View {
        VStack(spacing: 4) {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let left = rest.remaining(at: timeline.date)
                ZStack {
                    Circle().stroke(Look.surface2, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: rest.total > 0 ? min(1, left / rest.total) : 0)
                        .stroke(Look.volt, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: left)
                    VStack(spacing: -2) {
                        Caps("Rest")
                        Text(Look.clock(left))
                            .font(Look.rounded(28))
                            .monospacedDigit()
                    }
                }
                .padding(4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Look.clock(left)) of rest left")
            }
            Text(next)
                .font(.system(size: 12))
                .foregroundStyle(Look.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                Button("+15 s") { rest.add(seconds: 15) }
                    .buttonStyle(PillStyle(fill: Look.surface2, foreground: .white, height: 36))
                    .accessibilityLabel("Add 15 seconds of rest")
                Button("Skip") { rest.stop() }
                    .buttonStyle(PillStyle(height: 36))
                    .doubleTapToPress()
                    .accessibilityLabel("Skip rest")
            }
        }
    }
}

/// Live numbers: time, heart rate, calories, plus Swap and Finish.
struct LivePage: View {
    let workout: WatchWorkout
    let entry: WatchEntry?
    let position: Int

    @EnvironmentObject private var model: WatchModel
    @EnvironmentObject private var tracker: WorkoutTracker
    @State private var confirmFinish = false
    @State private var showSwaps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(Look.clock(timeline.date.timeIntervalSince(workout.startedAt).rounded(.down)))
                        .font(Look.rounded(32))
                        .monospacedDigit()
                        .foregroundStyle(Look.volt)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 4)
                Text("\(position + 1) of \(workout.entries.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Look.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Look.red)
                Text(tracker.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(Look.rounded(26))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Look.red)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tracker.heartRate.map { "Heart rate \(Int($0.rounded())) beats per minute" } ?? "Heart rate not available")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(tracker.calories.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(Look.rounded(26))
                    .monospacedDigit()
                Text("ACTIVE CAL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Look.orange)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tracker.calories.map { "\(Int($0.rounded())) active calories" } ?? "Calories not available")
            Spacer(minLength: 2)
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Look.orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 6) {
                Button("Swap") {
                    guard let entry else { return }
                    model.askForSwaps(entry)
                    showSwaps = model.notice == nil
                }
                .buttonStyle(PillStyle(fill: Look.surface2, foreground: .white, height: 36))
                .disabled(entry == nil || entry?.isDone == true)
                Button(model.isFinishing ? "Saving" : "Finish") {
                    if workout.setsLeft > 0 { confirmFinish = true } else { model.finish() }
                }
                .buttonStyle(PillStyle(fill: Look.redDim, foreground: Look.red, height: 36))
                .disabled(model.isFinishing)
                .accessibilityIdentifier("finish")
            }
        }
        .padding(.horizontal, 4)
        .confirmationDialog(finishTitle, isPresented: $confirmFinish, titleVisibility: .visible) {
            Button(workout.doneSets.isEmpty ? "Discard workout" : "Finish workout",
                   role: workout.doneSets.isEmpty ? .destructive : nil) { model.finish() }
            Button("Keep going", role: .cancel) {}
        }
        .sheet(isPresented: $showSwaps, onDismiss: { model.swapOptions = nil }) { swapList }
    }

    private var finishTitle: String {
        if workout.doneSets.isEmpty { return "Nothing logged yet. Discard this workout?" }
        let left = workout.setsLeft
        return "Finish now? \(left) set\(left == 1 ? "" : "s") not logged will be left out."
    }

    @ViewBuilder
    private var swapList: some View {
        if let options = model.swapOptions {
            if options.isEmpty {
                Text("Nothing equivalent is set up for this gym.")
                    .font(.system(size: 14))
                    .foregroundStyle(Look.muted)
            } else {
                List(options) { option in
                    Button {
                        if let entry { model.swap(entry, to: option) }
                        showSwaps = false
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.name).font(.system(size: 15, weight: .semibold))
                            if option.isBestMatch {
                                Text("BEST MATCH")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Look.volt)
                            }
                        }
                    }
                }
                .navigationTitle("Swap")
            }
        } else if let notice = model.notice {
            Text(notice).font(.system(size: 14)).foregroundStyle(Look.orange)
        } else {
            ProgressView()
        }
    }
}

// MARK: - Summary

/// Shown after Finish: sets, records, calories and average heart rate.
struct SummaryScreen: View {
    let info: FinishedInfo
    @EnvironmentObject private var model: WatchModel

    /// The phone may report more records once it has checked every set.
    private var records: Int {
        if let summary = model.snapshot?.summary, summary.workoutID == info.workoutID {
            return max(info.records, summary.records)
        }
        return info.records
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Look.volt)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Workout done")
                            .font(Look.rounded(16))
                            .accessibilityAddTraits(.isHeader)
                        Text("\(info.title) · \(info.minutes) min")
                            .font(.system(size: 11))
                            .foregroundStyle(Look.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    GridRow {
                        tile("\(info.sets)", info.sets == 1 ? "set" : "sets")
                        tile("\(records)", records == 1 ? "record" : "records", highlighted: records > 0)
                    }
                    GridRow {
                        tile(info.calories.map { "\(Int($0.rounded()))" } ?? "--", "calories")
                        tile(info.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--", "avg bpm")
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(info.savedToHealth ? Look.red : Look.muted)
                    Text(info.savedToHealth ? "Saved to Apple Health" : "Saved on your iPhone")
                }
                .font(.system(size: 11))
                .foregroundStyle(Look.muted)
                .accessibilityElement(children: .combine)
                Button("Done") { model.finished = nil }
                    .buttonStyle(PillStyle(fill: Look.surface2, foreground: .white, height: 36))
                    .accessibilityIdentifier("summaryDone")
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle {
            Text("Next Up").foregroundStyle(Look.volt)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ value: String, _ label: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(value)
                .font(Look.rounded(20))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(highlighted ? Look.onVoltSoft : Look.muted)
        }
        .foregroundStyle(highlighted ? Look.onVolt : .white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Look.volt : Look.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
