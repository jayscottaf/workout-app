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
    /// Redraws every weight when pounds or kilograms is changed in Settings.
    @AppStorage(Units.key) private var weightUnit = WeightUnit.lb.rawValue
    let workout: Workout
    let onDiscard: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage("keptPairs") private var keptPairs = ""
    /// Hides the one-line tip once you have marked how a set felt.
    @AppStorage("usedEffort") private var usedEffort = false
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
    /// Exercises whose full "why today's targets" text is open. Two lines by default.
    @State private var openExplanations: Set<PersistentIdentifier> = []
    /// Exercises whose form tips are open. Closed by default.
    @State private var openTips: Set<PersistentIdentifier> = []
    /// The machine whose settings (seat, pads) are being edited, and the text so far.
    @State private var editingNotes: Equipment?
    @State private var notesDraft = ""
    /// The set whose weight is being typed in, after a tap on the weight number.
    @State private var typingWeight: SetEntry?

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
        .modifier(TypeWeightAlert(typing: $typingWeight))
        .alert("Machine settings", isPresented: Binding(get: { editingNotes != nil }, set: { if !$0 { editingNotes = nil } }),
               presenting: editingNotes) { machine in
            TextField("Seat 4, back pad 2", text: $notesDraft)
                .accessibilityIdentifier("machineNotesField")
            Button("Save") {
                machine.notes = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: { machine in
            Text("Remembered for \(machine.name) at \(gym?.name ?? "this gym").")
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
                index = workout.allEntries.count - 1
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
                    Text(workout.title).scaledFont(15, weight: .bold)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("\(elapsed(at: timeline.date)) · \(position + 1) of \(max(entries.count, 1))")
                            .scaledFont(13)
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    // Which gym this is. Tap to tick what it has, even mid-workout.
                    if let gym {
                        Button { showEquipment = true } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                Text(gym.name).lineLimit(1)
                                Image(systemName: "chevron.down").scaledFont(9, weight: .heavy)
                            }
                            .scaledFont(13, weight: .semibold)
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
                    if entries.indices.contains(position) {
                        let current = entries[position]
                        if current.supersetID != nil {
                            Button { Store.endSuperset(current, in: workout, context: context) } label: {
                                Label("Stop the superset", systemImage: "link.badge.plus")
                            }
                        } else {
                            let others = entries.filter { $0.id != current.id && !$0.isDone }
                            if !current.isDone, !others.isEmpty {
                                Menu {
                                    ForEach(others) { other in
                                        Button(other.name) { Store.superset(current, with: other, in: workout, context: context) }
                                    }
                                } label: {
                                    Label("Superset \(current.name) with…", systemImage: "link")
                                }
                            }
                        }
                    }
                    if gym != nil {
                        Button { showEquipment = true } label: {
                            Label("Equipment at \(gym?.name ?? "this gym")", systemImage: "dumbbell")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .scaledFont(16, weight: .heavy)
                        .foregroundStyle(Theme.volt)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Add an exercise, make a superset or change gym equipment")
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
                        .scaledFont(30, weight: .heavy, design: .rounded)
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle(entry))
                        .scaledFont(14)
                        .foregroundStyle(Theme.muted)
                    stepMenu(entry)
                    machineNotes(entry)
                    if let partner = workout.partner(of: entry) {
                        Label("Superset with \(partner.name) · alternate sets", systemImage: "link")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(Theme.volt)
                            .accessibilityIdentifier("supersetLabel")
                    }
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

            // Why today's targets: two lines at first, so the set you are doing stays in view. Tap for the rest.
            let explained = openExplanations.contains(entry.persistentModelID)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if explained { openExplanations.remove(entry.persistentModelID) } else { openExplanations.insert(entry.persistentModelID) }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: entry))
                        .scaledFont(15, weight: .heavy)
                        .foregroundStyle(Theme.volt)
                        .accessibilityHidden(true)
                    Text(entry.explanation)
                        .scaledFont(14)
                        .foregroundStyle(Color(hex: 0xDDE8C2))
                        .multilineTextAlignment(.leading)
                        .lineLimit(explained ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .card(padding: 12, radius: 16, color: Theme.voltDim)
            .accessibilityLabel(entry.explanation)
            .accessibilityIdentifier("explanation")

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
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .buttonStyle(.plain)
                if !usedEffort, !entry.completedSets.isEmpty {
                    Text("Tip: press and hold a done set to mark it easy, hard or failed. It's optional, and it fine-tunes the next suggestion.")
                        .scaledFont(12)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// Your settings for this machine at this gym ("Seat 4, back pad 2"). Machines only.
    @ViewBuilder
    private func machineNotes(_ entry: ExerciseEntry) -> some View {
        if let id = entry.equipmentID, let machine = gym?.items.first(where: { $0.id == id }),
           machine.type?.category == .machine {
            Button {
                notesDraft = machine.notes
                editingNotes = machine
            } label: {
                Label(machine.notes.isEmpty ? "Add machine settings" : machine.notes,
                      systemImage: machine.notes.isEmpty ? "plus.circle" : "slider.horizontal.3")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(machine.notes.isEmpty ? Theme.muted : Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(machine.notes.isEmpty ? "Add settings for this machine" : "Machine settings: \(machine.notes). Edit")
            .accessibilityIdentifier("machineNotes")
        }
    }

    /// Heads-up when this exercise repeats the job of one done earlier in the workout.
    private func overlapCard(_ overlap: Overlap, entry: ExerciseEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.2")
                .scaledFont(14, weight: .heavy)
                .foregroundStyle(Theme.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(overlap.message)
                    .scaledFont(14)
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
                .scaledFont(14, weight: .semibold)
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
                        .scaledFont(12, weight: .heavy)
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
                            .scaledFont(15)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    let query = "\(entry.name) proper form".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") { openURL(url) }
                } label: {
                    Label("Watch on YouTube", systemImage: "play.rectangle")
                        .scaledFont(14, weight: .semibold)
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

    /// Choose how far + and − move the weight: 2.5, 5 or 10 lb (1.25, 2.5 or 5 kg).
    private func stepMenu(_ entry: ExerciseEntry) -> some View {
        Menu {
            ForEach(Units.stepChoices(), id: \.self) { step in
                Button {
                    Store.setIncrement(step, for: entry, gym: gym, context: context)
                } label: {
                    if step == entry.increment {
                        Label("\(Fmt.lb(step)) steps", systemImage: "checkmark")
                    } else {
                        Text("\(Fmt.lb(step)) steps")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Fmt.lb(entry.increment)) steps")
                Image(systemName: "chevron.down").scaledFont(10, weight: .heavy)
            }
            .scaledFont(14, weight: .semibold)
            .foregroundStyle(Theme.volt)
            .frame(minHeight: 30)
        }
        .accessibilityLabel("Weight steps: \(Fmt.weight(entry.increment)) \(Units.spoken). Change")
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
        return Fmt.lb(weight)
    }

    private func completedRow(_ set: SetEntry) -> some View {
        Button { Store.reopen(set, context: context) } label: {
            HStack(spacing: 14) {
                Text("\(set.index + 1)")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, alignment: .leading)
                Text("\(weightText(set.weight, entry: nil)) × \(set.reps)")
                    .scaledFont(20, weight: .bold, design: .rounded)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if let effort = set.effort {
                    Text(effort.title.uppercased())
                        .scaledFont(10, weight: .heavy)
                        .foregroundStyle(effort == .easy ? Theme.volt : Theme.amber)
                        .lineLimit(1)
                }
                if set.prKindRaw != nil {
                    Text("RECORD")
                        .scaledFont(11, weight: .heavy)
                        .foregroundStyle(Theme.onVolt)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 6))
                } else if let delta = deltaText(set) {
                    Text(delta)
                        .scaledFont(13, weight: .bold)
                        .foregroundStyle(Theme.volt)
                }
                Image(systemName: "checkmark")
                    .scaledFont(16, weight: .heavy)
                    .foregroundStyle(Theme.volt)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // Optional: how it felt. The next suggestion holds after a failed rep and jumps two steps when every set was easy.
        .contextMenu {
            ForEach(Effort.allCases, id: \.self) { effort in
                Button {
                    set.effort = set.effort == effort ? nil : effort
                    usedEffort = true
                    try? context.save()
                    Haptics.tap()
                } label: {
                    if set.effort == effort { Label(effort.title, systemImage: "checkmark") } else { Text(effort.title) }
                }
            }
        }
        .accessibilityLabel("Set \(set.index + 1) done: \(weightText(set.weight, entry: nil)) for \(set.reps) reps\(set.effort.map { ", \($0.title)" } ?? "")")
        .accessibilityHint("Double tap to edit this set. Press and hold to say how it felt")
        .accessibilityActions {
            ForEach(Effort.allCases, id: \.self) { effort in
                Button("Felt \(effort.title.lowercased())") { set.effort = effort; usedEffort = true; try? context.save() }
            }
        }
    }

    private func deltaText(_ set: SetEntry) -> String? {
        guard let lastWeight = set.lastWeight, let lastReps = set.lastReps, set.beatLastTime else { return nil }
        if set.weight > lastWeight { return "+\(Fmt.lb(set.weight - lastWeight))" }
        let extra = set.reps - lastReps
        return "+\(extra) rep\(extra == 1 ? "" : "s")"
    }

    private func pendingRow(_ set: SetEntry, entry: ExerciseEntry) -> some View {
        HStack(spacing: 14) {
            Text("\(set.index + 1)")
                .scaledFont(13, weight: .bold)
                .frame(width: 22, alignment: .leading)
            Text("\(weightText(set.weight, entry: entry)) × \(set.reps)")
                .scaledFont(20, weight: .bold, design: .rounded)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(set.lastReps == nil ? "up next" : "target")
                .scaledFont(13)
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
                    .scaledFont(13)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 10) {
                stepper(value: set.weight <= 0 ? "BW" : (entry.isBodyweight ? "+" : "") + Fmt.weight(set.weight),
                        unit: set.weight <= 0 ? "body weight" : (entry.isBodyweight ? "\(Units.symbol) held" : Units.symbol),
                        lessLabel: "Lower weight by \(Fmt.weight(entry.increment)) \(Units.spoken)",
                        moreLabel: "Raise weight by \(Fmt.weight(entry.increment)) \(Units.spoken)",
                        less: { set.weight = max(0, set.weight - entry.increment) },
                        more: { set.weight += entry.increment },
                        type: TypeWeightAlert.label(set.weight),
                        onType: { typingWeight = set })
                stepper(value: "\(set.reps)", unit: "reps", lessLabel: "One fewer rep", moreLabel: "One more rep",
                        less: { set.reps = max(1, set.reps - 1) },
                        more: { set.reps += 1 })
            }
            if let bar = entry.plateBar, let plates = Plates.text(total: set.weight, bar: bar) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill")
                        .scaledFont(12, weight: .bold)
                        .foregroundStyle(Theme.volt)
                        .accessibilityHidden(true)
                    Text(plates)
                        .scaledFont(14, weight: .semibold)
                        .monospacedDigit()
                    if bar > 0 {
                        Text("· \(Fmt.lb(bar)) bar")
                            .scaledFont(13)
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
            let range = sets.count > 1 ? "\(low)–\(high) \(Units.symbol)" : "\(low) \(Units.symbol)"
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
                                .scaledFont(13, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if open {
                            Text("not logged")
                                .scaledFont(12)
                                .foregroundStyle(Theme.muted)
                        }
                        Image(systemName: "chevron.down")
                            .scaledFont(12, weight: .heavy)
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
                        Text("\(Fmt.lb(set.weight)) × \(set.reps)")
                            .scaledFont(15, weight: .bold)
                            .monospacedDigit()
                        if let bar, let plates = Plates.text(total: set.weight, bar: bar) {
                            Text(plates)
                                .scaledFont(13)
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

    /// − and + for small changes. When `onType` is given, tapping the number lets you type a value.
    private func stepper(value: String, unit: String, lessLabel: String, moreLabel: String,
                         less: @escaping () -> Void, more: @escaping () -> Void,
                         type typeLabel: String? = nil, onType: (() -> Void)? = nil) -> some View {
        HStack(spacing: 0) {
            CircleIconButton(systemName: "minus", label: lessLabel, fill: Theme.line, repeats: true) {
                less()
                Haptics.tap()
            }
            TypeableValue(label: typeLabel, onType: onType) {
                VStack(spacing: 0) {
                    Text(value)
                        .scaledFont(30, weight: .heavy, design: .rounded)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(unit)
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            CircleIconButton(systemName: "plus", label: moreLabel, fill: Theme.line, repeats: true) {
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
        let everythingDone = workout.allEntries.allSatisfy(\.isDone)
        if everythingDone {
            rest.stop()
        } else if let partner = workout.partner(of: entry), partner.nextSet != nil,
                  let target = workout.sortedEntries.firstIndex(where: { $0.id == partner.id }) {
            // Superset: straight to the other exercise. Rest once both are done for this round.
            index = target
            if partner.order > entry.order {
                rest.stop()
            } else {
                rest.start(seconds: RestSetting.seconds(default: max(entry.restSeconds, partner.restSeconds)), title: workout.title,
                           next: workout.nextUpText(after: partner))
            }
        } else {
            rest.start(seconds: RestSetting.seconds(default: entry.restSeconds), title: workout.title,
                       next: workout.nextUpText(after: entry))
        }
    }

    private var finishTitle: String {
        let left = workout.allEntries.reduce(0) { $0 + $1.allSets.filter { $0.completedAt == nil }.count }
        if workout.completedSets.isEmpty { return "Nothing logged yet. Discard this workout?" }
        return left == 0 ? "Finish this workout?" : "Finish now? \(left) set\(left == 1 ? "" : "s") not logged will be left out."
    }

    private func requestFinish() {
        let left = workout.allEntries.contains { $0.nextSet != nil }
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
                        .scaledFont(34, weight: .heavy, design: .rounded)
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
                .scaledFont(22, weight: .bold)
                .scaleEffect(burst ? 1 : 0.4)
                .rotationEffect(.degrees(burst ? 0 : -25))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).scaledFont(16, weight: .heavy)
                Text(detail).scaledFont(13, weight: .medium).foregroundStyle(Theme.onVoltSoft)
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

/// The number between − and +. With `onType`, a tap on it opens the number pad.
struct TypeableValue<Content: View>: View {
    let label: String?
    let onType: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let onType {
            Button(action: onType) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label ?? "")
            .accessibilityHint("Double tap to type a weight")
            .accessibilityIdentifier("typeWeight")
        } else {
            content()
        }
    }
}

/// Type a weight instead of tapping + many times: 135 to 225 is one tap and three digits.
/// A blank or unreadable entry leaves the weight as it was.
struct TypeWeightAlert: ViewModifier {
    @Binding var typing: SetEntry?
    var onChange: () -> Void = {}
    @State private var draft = ""

    static func label(_ weight: Double) -> String {
        weight > 0 ? "Weight: \(Fmt.weight(weight)) \(Units.spoken)" : "Weight: body weight"
    }

    func body(content: Content) -> some View {
        content.alert("Weight", isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } }),
                      presenting: typing) { target in
            TextField(target.weight > 0 ? Fmt.weight(target.weight) : "0", text: $draft)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("typedWeight")
            Button("Set") {
                if let value = Fmt.parseWeight(draft), value != target.weight {
                    target.weight = value
                    onChange()
                    Haptics.tap()
                }
                draft = ""
            }
            .accessibilityIdentifier("setTypedWeight")
            Button("Cancel", role: .cancel) { draft = "" }
        } message: { _ in
            Text("In \(Units.spoken). 0 means body weight only.")
        }
    }
}
