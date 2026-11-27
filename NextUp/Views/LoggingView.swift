import SwiftUI
import SwiftData

/// Full-screen flow for one workout: logging while it is in progress, summary once finished.
struct WorkoutFlowView: View {
    let workout: Workout
    let onClose: () -> Void

    var body: some View {
        if workout.endedAt == nil {
            LoggingView(workout: workout, onDiscard: onClose)
        } else {
            SummaryView(workout: workout, isFresh: true, onDone: onClose)
        }
    }
}

private struct RecordBanner: Equatable {
    let id = UUID()
    let title: String
    let detail: String
}

/// Fast set logging: sets are pre-filled, one tap confirms, +/- adjusts, rest starts by itself.
struct LoggingView: View {
    let workout: Workout
    let onDiscard: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage("keptPairs") private var keptPairs = ""
    @EnvironmentObject private var rest: RestTimer
    @EnvironmentObject private var health: HealthService
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @Query private var prefs: [ExercisePrefs]

    @State private var index = 0
    @State private var swapping: ExerciseEntry?
    @State private var showAdd = false
    @State private var showEquipment = false
    @State private var confirmFinish = false
    @State private var banner: RecordBanner?
    /// Exercises whose warm-up list is open. Closed by default to keep the working set in view.
    @State private var openWarmUps: Set<PersistentIdentifier> = []
    /// Exercises whose form tips are open. Closed by default.
    @State private var openTips: Set<PersistentIdentifier> = []

    private var gym: Gym? { gyms.first { $0.id == workout.gymID } }

    var body: some View {
        let entries = workout.sortedEntries
        let history = Store.history(workouts)
        let position = min(index, max(entries.count - 1, 0))

        VStack(spacing: 0) {
            topBar(entries: entries, position: position)
            ScrollView {
                if entries.indices.contains(position) {
                    exerciseBody(entries[position], entries: entries, position: position, history: history)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                        .id(entries[position].id)
                } else {
                    Text("No exercises in this workout yet.")
                        .foregroundStyle(Theme.muted)
                        .padding(40)
                }
            }
        }
        .screen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if rest.isRunning { RestBar() }
        }
        .overlay(alignment: .top) {
            if let banner {
                RecordBannerView(title: banner.title, detail: banner.detail)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            // The Lock Screen card stays up for the whole workout, so rests started on the Watch show there too.
            rest.beginWorkout(title: workout.title, next: workout.nextUpText(after: nil), started: workout.startedAt)
            // Reopened after Finish: start on the first exercise with sets left, else the last one.
            // Open on the exercise the Watch is showing, if any.
            if let shared = WatchLink.shared.currentEntryID, let match = entries.firstIndex(where: { $0.id == shared }) {
                index = match
            } else {
                index = entries.firstIndex { !$0.isDone } ?? max(entries.count - 1, 0)
            }
        }
        // Keep the Watch on the same exercise as this screen, and follow it when it moves.
        .onChange(of: entries.indices.contains(position) ? entries[position].id : nil, initial: true) { _, id in
            if let id { WatchLink.shared.focus(id) }
        }
        .onReceive(WatchLink.shared.$currentEntryID) { id in
            if let id, let target = workout.sortedEntries.firstIndex(where: { $0.id == id }), target != index {
                index = target
            }
        }
        .animation(.spring(duration: 0.35), value: banner)
        .animation(.easeOut(duration: 0.2), value: rest.isRunning)
        .sheet(item: $swapping) { entry in
            SwapSheet(entry: entry, gym: gym, history: history) { exercise in
                // If sets were already logged, the new exercise is added right after: move on to it.
                if !entry.completedSets.isEmpty { index = position + 1 }
                Store.swap(entry, to: exercise, in: workout, gym: gym, history: history,
                           overrides: Store.rangeOverrides(prefs), context: context)
                swapping = nil
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExerciseSheet(gym: gym, excluded: Set(entries.map(\.exerciseID)), current: entries.map(\.exerciseID)) { exercise in
                Store.add(exercise, to: workout, gym: gym, history: history,
                          overrides: Store.rangeOverrides(prefs), context: context)
                index = workout.entries.count - 1
                showAdd = false
            }
        }
        .sheet(isPresented: $showEquipment) {
            if let gym { GymEquipmentSheet(gym: gym) }
        }
        .confirmationDialog(finishTitle, isPresented: $confirmFinish, titleVisibility: .visible) {
            if workout.completedSets.isEmpty {
                Button("Discard workout", role: .destructive) { discard() }
            } else {
                Button("Finish workout") { finish() }
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: top bar

    private func topBar(entries: [ExerciseEntry], position: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button("Finish") { requestFinish() }
                    .buttonStyle(ChipButtonStyle())
                    .accessibilityIdentifier("finishWorkout")
                Spacer()
                VStack(spacing: 1) {
                    Text(workout.title).font(.system(size: 15, weight: .bold))
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("\(elapsed(at: timeline.date)) · \(position + 1) of \(max(entries.count, 1))")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    // Which gym this is. Tap to tick what it has, even mid-workout.
                    if let gym {
                        Button { showEquipment = true } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                Text(gym.name).lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.volt)
                            .frame(minHeight: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("At \(gym.name). Change its equipment")
                        .accessibilityIdentifier("gymButton")
                    }
                }
                Spacer()
                Menu {
                    Button { showAdd = true } label: { Label("Add an exercise", systemImage: "plus") }
                    if gym != nil {
                        Button { showEquipment = true } label: {
                            Label("Equipment at \(gym?.name ?? "this gym")", systemImage: "dumbbell")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.volt)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Add an exercise or change gym equipment")
                .accessibilityIdentifier("addMenu")
            }
            HStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    Button { index = offset } label: {
                        Capsule()
                            .fill(entry.isDone ? Theme.volt : (offset == position ? Theme.volt.opacity(0.5) : Theme.line))
                            .frame(height: 4)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.name), exercise \(offset + 1) of \(entries.count)\(entry.isDone ? ", done" : "")")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(workout.startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: exercise

    @ViewBuilder
    private func exerciseBody(_ entry: ExerciseEntry, entries: [ExerciseEntry], position: Int, history: History) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(Theme.rounded(30))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle(entry))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                    stepMenu(entry)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Button { swapping = entry } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Swap")
                        }
                    }
                    .buttonStyle(ChipButtonStyle(foreground: Theme.volt))
                    .accessibilityLabel("Swap \(entry.name) for an equivalent exercise")
                    .accessibilityIdentifier("swapExercise")
                    if !entry.isDone, entries.contains(where: { $0.id != entry.id && !$0.isDone }) {
                        Button {
                            withAnimation { Store.moveToEnd(entry, in: workout, context: context) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Later")
                            }
                        }
                        .buttonStyle(ChipButtonStyle())
                        .accessibilityLabel("Do \(entry.name) later. Moves it to the end of the workout")
                        .accessibilityIdentifier("doLater")
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: entry))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.volt)
                    .accessibilityHidden(true)
                Text(entry.explanation)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0xDDE8C2))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 12, radius: 16, color: Theme.voltDim)

            if let exercise = entry.exercise,
               let overlap = Overlap.find(exercise, among: entries.prefix(position).compactMap(\.exercise), kept: Overlap.keptPairs(keptPairs)) {
                overlapCard(overlap, entry: entry)
            }

            if let first = entry.nextSet, entry.completedSets.isEmpty, !entry.isBodyweight, position == 0 || entry.plateBar != nil {
                warmUpCard(target: first.weight, entry: entry)
            }

            VStack(spacing: 8) {
                ForEach(entry.sortedSets) { set in
                    if set.completedAt != nil {
                        completedRow(set)
                    } else if set.id == entry.nextSet?.id {
                        activeCard(set, entry: entry, history: history)
                    } else {
                        pendingRow(set, entry: entry)
                    }
                }
                Button("Add a set") { Store.addSet(to: entry, context: context) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .buttonStyle(.plain)
            }

            formCard(entry)

            if entry.isDone {
                if let next = entries.indices.first(where: { !entries[$0].isDone }) {
                    Button("Next: \(entries[next].name)") { index = next }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("nextExercise")
                } else {
                    Button("Finish workout") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    /// Heads-up when this exercise repeats the job of one done earlier in the workout.
    private func overlapCard(_ overlap: Overlap, entry: ExerciseEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.2")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(overlap.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    if !entry.isDone {
                        Button("Swap it") { swapping = entry }
                            .accessibilityIdentifier("overlapSwap")
                    }
                    Button("Keep both") {
                        withAnimation { keptPairs = Overlap.keeping(entry.exerciseID, overlap.other.id, in: keptPairs) }
                    }
                    .accessibilityIdentifier("overlapKeep")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .buttonStyle(.plain)
                .frame(minHeight: 32)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, radius: 16, color: Theme.amberDim)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overlapCard")
    }

    /// Short form cues, closed by default, and a YouTube search for the exercise.
    private func formCard(_ entry: ExerciseEntry) -> some View {
        let tips = FormTips.tips(for: entry.exerciseID)
        let open = openTips.contains(entry.persistentModelID)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if open { openTips.remove(entry.persistentModelID) } else { openTips.insert(entry.persistentModelID) }
                }
            } label: {
                HStack(spacing: 8) {
                    CapsLabel("How to do it")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "How to do it. Hide" : "How to do it. Show form tips")
            .accessibilityIdentifier("formToggle")
            if open {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.volt).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(tip)
                            .font(.system(size: 15))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    let query = "\(entry.name) proper form".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") { openURL(url) }
                } label: {
                    Label("Watch on YouTube", systemImage: "play.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.volt)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a YouTube search for this exercise")
                .accessibilityIdentifier("watchYouTube")
            }
        }
        .card(padding: 14, radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formCard")
    }

    private func subtitle(_ entry: ExerciseEntry) -> String {
        [entry.equipmentName, "\(entry.repLow) to \(entry.repHigh) reps"].joined(separator: " · ")
    }

    /// Choose how far + and − move the weight: 2.5, 5 or 10 lb.
    private func stepMenu(_ entry: ExerciseEntry) -> some View {
        Menu {
            ForEach(Store.stepChoices, id: \.self) { step in
                Button {
                    Store.setIncrement(step, for: entry, gym: gym, context: context)
                } label: {
                    if step == entry.increment {
                        Label("\(Fmt.weight(step)) lb steps", systemImage: "checkmark")
                    } else {
                        Text("\(Fmt.weight(step)) lb steps")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Fmt.weight(entry.increment)) lb steps")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.volt)
            .frame(minHeight: 30)
        }
        .accessibilityLabel("Weight steps: \(Fmt.weight(entry.increment)) pounds. Change")
        .accessibilityIdentifier("stepMenu")
    }

    private func icon(for entry: ExerciseEntry) -> String {
        switch SuggestionKind(rawValue: entry.kindRaw) ?? .progress {
        case .increase: return "arrow.up.circle.fill"
        case .layoff, .backOff: return "arrow.down.circle.fill"
        case .hold: return "pause.circle.fill"
        case .firstTime: return "sparkles"
        case .progress: return "target"
        }
    }

    private func weightText(_ weight: Double, entry: ExerciseEntry?) -> String {
        if weight <= 0 { return "Body weight" }
        return "\(Fmt.weight(weight)) lb"
    }

    private func completedRow(_ set: SetEntry) -> some View {
        Button { Store.reopen(set, context: context) } label: {
            HStack(spacing: 14) {
                Text("\(set.index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, alignment: .leading)
                Text("\(weightText(set.weight, entry: nil)) × \(set.reps)")
                    .font(Theme.rounded(20, .bold))
                    .monospacedDigit()
                Spacer(minLength: 0)
                if set.prKindRaw != nil {
                    Text("RECORD")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.onVolt)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 6))
                } else if let delta = deltaText(set) {
                    Text(delta)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.volt)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.volt)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(set.index + 1) done: \(weightText(set.weight, entry: nil)) for \(set.reps) reps")
        .accessibilityHint("Double tap to edit this set")
    }

    private func deltaText(_ set: SetEntry) -> String? {
        guard let lastWeight = set.lastWeight, let lastReps = set.lastReps, set.beatLastTime else { return nil }
        if set.weight > lastWeight { return "+\(Fmt.weight(set.weight - lastWeight)) lb" }
        let extra = set.reps - lastReps
        return "+\(extra) rep\(extra == 1 ? "" : "s")"
    }

    private func pendingRow(_ set: SetEntry, entry: ExerciseEntry) -> some View {
        HStack(spacing: 14) {
            Text("\(set.index + 1)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, alignment: .leading)
            Text("\(weightText(set.weight, entry: entry)) × \(set.reps)")
                .font(Theme.rounded(20, .bold))
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(set.lastReps == nil ? "up next" : "target")
                .font(.system(size: 13))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func activeCard(_ set: SetEntry, entry: ExerciseEntry, history: History) -> some View {
        VStack(spacing: 14) {
            HStack {
                CapsLabel("Set \(set.index + 1)", color: Theme.volt)
                Spacer()
                Text(set.target.beatText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 10) {
                stepper(value: set.weight <= 0 ? "BW" : (entry.isBodyweight ? "+" : "") + Fmt.weight(set.weight),
                        unit: set.weight <= 0 ? "body weight" : (entry.isBodyweight ? "lb held" : "lb"),
                        lessLabel: "Lower weight by \(Fmt.weight(entry.increment)) pounds",
                        moreLabel: "Raise weight by \(Fmt.weight(entry.increment)) pounds",
                        less: { set.weight = max(0, set.weight - entry.increment) },
                        more: { set.weight += entry.increment })
                stepper(value: "\(set.reps)", unit: "reps", lessLabel: "One fewer rep", moreLabel: "One more rep",
                        less: { set.reps = max(1, set.reps - 1) },
                        more: { set.reps += 1 })
            }
            if let bar = entry.plateBar, let plates = Plates.text(total: set.weight, bar: bar) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.volt)
                        .accessibilityHidden(true)
                    Text(plates)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                    if bar > 0 {
                        Text("· \(Fmt.weight(bar)) lb bar")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("platesLine")
            }
            Button {
                log(set, entry: entry, history: history)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Log set")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("logSet")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.volt, lineWidth: 2))
    }

    /// Lighter sets to do first. They are a guide only and are not logged.
    @ViewBuilder
    private func warmUpCard(target: Double, entry: ExerciseEntry) -> some View {
        let bar = entry.plateBar
        let sets = WarmUp.sets(target: target, step: entry.increment, bar: bar ?? 0)
        if !sets.isEmpty {
            let open = openWarmUps.contains(entry.persistentModelID)
            let low = sets.first.map { Fmt.weight($0.weight) } ?? ""
            let high = sets.last.map { Fmt.weight($0.weight) } ?? ""
            let range = sets.count > 1 ? "\(low)–\(high) lb" : "\(low) lb"
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if open { openWarmUps.remove(entry.persistentModelID) } else { openWarmUps.insert(entry.persistentModelID) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        CapsLabel("Warm-up first")
                        if !open {
                            Text("\(sets.count) \(sets.count == 1 ? "set" : "sets") · \(range)")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if open {
                            Text("not logged")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Warm-up sets, not logged. Hide" : "Warm-up: \(sets.count) sets, \(range). Show")
                .accessibilityIdentifier("warmUpToggle")
                if open {
                ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                    HStack(spacing: 10) {
                        Text("\(Fmt.weight(set.weight)) lb × \(set.reps)")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                        if let bar, let plates = Plates.text(total: set.weight, bar: bar) {
                            Text(plates)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                }
            }
            .card(padding: 14, radius: 18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("warmUpCard")
        }
    }

    private func stepper(value: String, unit: String, lessLabel: String, moreLabel: String,
                         less: @escaping () -> Void, more: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            CircleIconButton(systemName: "minus", label: lessLabel, fill: Theme.line) {
                less()
                Haptics.tap()
            }
            VStack(spacing: 0) {
                Text(value)
                    .font(Theme.rounded(30))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "plus", label: moreLabel, fill: Theme.line) {
                more()
                Haptics.tap()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: actions

    private func log(_ set: SetEntry, entry: ExerciseEntry, history: History) {
        let kind = Store.complete(set, in: entry, history: history, context: context)
        if let kind {
            Haptics.success()
            let shown = RecordBanner(title: "New record: \(kind.text(weight: set.weight, reps: set.reps))",
                                     detail: "\(entry.name) · \(weightText(set.weight, entry: entry)) × \(set.reps)")
            banner = shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if banner == shown { banner = nil }
            }
        } else {
            Haptics.tap()
        }
        let everythingDone = workout.entries.allSatisfy(\.isDone)
        if everythingDone {
            rest.stop()
        } else {
            rest.start(seconds: RestSetting.seconds(default: entry.restSeconds), title: workout.title,
                       next: workout.nextUpText(after: entry))
        }
    }

    private var finishTitle: String {
        let left = workout.entries.reduce(0) { $0 + $1.sets.filter { $0.completedAt == nil }.count }
        if workout.completedSets.isEmpty { return "Nothing logged yet. Discard this workout?" }
        return left == 0 ? "Finish this workout?" : "Finish now? \(left) set\(left == 1 ? "" : "s") not logged will be left out."
    }

    private func requestFinish() {
        let left = workout.entries.contains { $0.nextSet != nil }
        if left || workout.completedSets.isEmpty {
            confirmFinish = true
        } else {
            finish()
        }
    }

    private func finish() {
        rest.endWorkout()
        guard !workout.completedSets.isEmpty else {
            discard()
            return
        }
        Store.finish(workout, context: context)
        Haptics.success()
        let start = workout.startedAt
        let end = workout.endedAt ?? Date()
        // When the Apple Watch recorded this workout (with heart rate), it saves it to Health itself.
        guard !WatchLink.shared.watchSavesToHealth(workout.id) else { return }
        Task { @MainActor in
            // If this workout was finished before and reopened, its earlier Health entry is replaced.
            if await health.saveLifting(start: start, end: end) {
                workout.savedToHealth = true
                try? context.save()
            }
        }
    }

    private func discard() {
        rest.endWorkout()
        onDiscard()
        // Delete after the screen has closed, so nothing on screen is still showing the workout.
        let store = context
        let abandoned = workout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Store.finish(abandoned, context: store)
        }
    }
}

// MARK: - pieces

/// Bottom bar with the rest countdown.
struct RestBar: View {
    @EnvironmentObject private var rest: RestTimer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    CapsLabel("Rest")
                    Text(rest.text)
                        .font(Theme.rounded(34))
                        .monospacedDigit()
                        .accessibilityLabel("\(rest.text) of rest left")
                }
                Spacer()
                Button("+15 s") { rest.add(seconds: 15) }
                    .buttonStyle(ChipButtonStyle(fill: Theme.line))
                    .accessibilityLabel("Add 15 seconds of rest")
                Button("Skip") { rest.stop() }
                    .buttonStyle(ChipButtonStyle(fill: Theme.line))
                    .accessibilityLabel("Skip rest")
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(Theme.volt).frame(width: proxy.size.width * rest.progress)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.surface)
                .ignoresSafeArea(edges: .bottom)
        )
        .transition(.move(edge: .bottom))
    }
}

/// The personal-record celebration that drops in from the top.
struct RecordBannerView: View {
    let title: String
    let detail: String
    @State private var burst = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 22, weight: .bold))
                .scaleEffect(burst ? 1 : 0.4)
                .rotationEffect(.degrees(burst ? 0 : -25))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .heavy))
                Text(detail).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.onVoltSoft)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onVolt)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .center) { sparks }
        .padding(.horizontal, 16)
        .shadow(color: Theme.volt.opacity(0.35), radius: 24, y: 8)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { burst = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    /// A small burst of dots flying outward.
    private var sparks: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi
                Circle()
                    .fill(i % 2 == 0 ? Theme.volt : Theme.text)
                    .frame(width: 6, height: 6)
                    .offset(x: burst ? cos(angle) * 150 : 0, y: burst ? sin(angle) * 70 : 0)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 0.9), value: burst)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
