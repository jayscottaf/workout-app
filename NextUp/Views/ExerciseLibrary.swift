import SwiftUI
import SwiftData

/// The exercise library. Opens short: search at the top, then your recent exercises and one tile per
/// muscle group. A group opens a short list you can narrow by equipment, showing what this gym has
/// unless you ask for everything. The full A–Z list is one tap further, for when you want it.
struct AddExerciseSheet: View {
    let gym: Gym?
    let excluded: Set<String>
    /// Exercises already in the workout or day, in order, to warn about ones that do the same job.
    var current: [String] = []
    let onPick: (ExerciseDef) -> Void

    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add an exercise")
                        .scaledFont(26, weight: .heavy, design: .rounded)
                        .accessibilityAddTraits(.isHeader)
                    searchField
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        home
                    } else {
                        results
                    }
                }
                .padding(20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.surface)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryList.self) { list in
                LibraryListView(list: list, gym: gym, excluded: excluded, current: current, onPick: onPick)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .sheet(isPresented: $creating) {
            CreateExerciseSheet(gym: gym) { exercise in
                creating = false
                onPick(exercise)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search 380+ exercises", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("exerciseSearch")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: before you type

    @ViewBuilder
    private var home: some View {
        let recent = recentExercises
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel("Recent")
                LibraryRows(exercises: recent, gym: gym, current: current, onPick: onPick)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel("By muscle")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    NavigationLink(value: LibraryList(group: group)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title).scaledFont(16, weight: .semibold)
                            Text("\(count(group)) exercises").scaledFont(12).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group-\(group.rawValue)")
                }
            }
        }
        HStack(spacing: 10) {
            NavigationLink(value: LibraryList(group: nil)) {
                Label("All A–Z", systemImage: "list.bullet").frame(maxWidth: .infinity, minHeight: 48)
            }
            .accessibilityIdentifier("allExercises")
            Button { creating = true } label: {
                Label("Create your own", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 48)
            }
            .accessibilityIdentifier("createExercise")
        }
        .scaledFont(14, weight: .semibold)
        .foregroundStyle(Theme.volt)
        .buttonStyle(.plain)
    }

    /// Exercises from your last workouts, newest first, at most eight.
    private var recentExercises: [ExerciseDef] {
        var seen = Set<String>(), list: [ExerciseDef] = []
        for workout in workouts.prefix(10) {
            for entry in workout.sortedEntries where !seen.contains(entry.exerciseID) && !excluded.contains(entry.exerciseID) {
                seen.insert(entry.exerciseID)
                if let exercise = ExerciseCatalog.exercise(entry.exerciseID), !ExerciseCatalog.isRetired(exercise.id) {
                    list.append(exercise)
                }
                if list.count == 8 { return list }
            }
        }
        return list
    }

    private func count(_ group: MuscleGroup) -> Int {
        ExerciseCatalog.all.filter { $0.muscle.group == group && !excluded.contains($0.id) }.count
    }

    // MARK: searching

    @ViewBuilder
    private var results: some View {
        let found = ExerciseSearch.matches(query, in: ExerciseCatalog.all.filter { !excluded.contains($0.id) })
        if found.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing called \u{201C}\(query)\u{201D}.").scaledFont(15).foregroundStyle(Theme.muted)
                Button { creating = true } label: { Label("Create \u{201C}\(query)\u{201D}", systemImage: "square.and.pencil") }
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(Theme.volt)
                    .accessibilityIdentifier("createExercise")
            }
        } else {
            let info = gym?.info
            // What this gym has first, then the rest.
            let here = found.filter { Planner.isAvailable($0, gym: info) }
            let elsewhere = found.filter { !Planner.isAvailable($0, gym: info) }
            LibraryRows(exercises: Array((here + elsewhere).prefix(40)), gym: gym, current: current, onPick: onPick)
        }
    }
}

/// One muscle group, or everything A–Z when `group` is nil.
struct LibraryList: Hashable {
    var group: MuscleGroup?
}

/// Equipment filter chips.
enum EquipmentFilter: String, CaseIterable {
    case all = "All", machine = "Machine", cable = "Cable", dumbbell = "Dumbbell", barbell = "Barbell",
         bodyweight = "Body weight", kettlebell = "Kettlebell"

    func matches(_ exercise: ExerciseDef) -> Bool {
        let id = exercise.equipment
        switch self {
        case .all: return true
        case .cable: return ["cable", "latPulldown", "seatedRow"].contains(id)
        case .machine: return exercise.equipmentType.category == .machine && !EquipmentFilter.cable.matches(exercise)
        case .dumbbell: return id == "dumbbells"
        case .barbell: return ["barbell", "ezBar", "trapBar"].contains(id)
        case .bodyweight: return exercise.equipmentType.category == .bodyweight
        case .kettlebell: return id == "kettlebell"
        }
    }
}

struct LibraryListView: View {
    let list: LibraryList
    let gym: Gym?
    let excluded: Set<String>
    let current: [String]
    let onPick: (ExerciseDef) -> Void
    @State private var filter: EquipmentFilter = .all
    @State private var onlyHere = true

    var body: some View {
        let info = gym?.info
        let inGroup = ExerciseCatalog.all.filter { (list.group == nil || $0.muscle.group == list.group) && !excluded.contains($0.id) }
        let chips = EquipmentFilter.allCases.filter { chip in chip == .all || inGroup.contains { chip.matches($0) } }
        let shown = inGroup
            .filter { filter.matches($0) && (!onlyHere || gym == nil || Planner.isAvailable($0, gym: info)) }
        // A group: the everyday exercises first, then the rest A–Z. Everything: A–Z.
        let sorted = list.group == nil
            ? shown.sorted { $0.name < $1.name }
            : shown.filter { !ExerciseCatalog.moreIDs.contains($0.id) }
                + shown.filter { ExerciseCatalog.moreIDs.contains($0.id) }.sorted { $0.name < $1.name }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Button(chip.rawValue) { filter = chip }
                                .buttonStyle(ChipButtonStyle(fill: filter == chip ? Theme.volt : Theme.surface2,
                                                             foreground: filter == chip ? Theme.onVolt : Theme.text))
                                .accessibilityAddTraits(filter == chip ? .isSelected : [])
                                .accessibilityIdentifier("filter-\(chip.rawValue)")
                        }
                    }
                }
                if let gym {
                    Toggle("Only what \(gym.name) has", isOn: $onlyHere)
                        .scaledFont(14, weight: .semibold)
                        .tint(Theme.volt)
                        .accessibilityIdentifier("onlyHere")
                }
                if sorted.isEmpty {
                    Text(onlyHere && gym != nil ? "Nothing here matches. Turn off \u{201C}Only what this gym has\u{201D} to see more."
                                                 : "Nothing matches this filter.")
                        .scaledFont(14)
                        .foregroundStyle(Theme.muted)
                } else {
                    LibraryRows(exercises: sorted, gym: gym, current: current, onPick: onPick)
                }
            }
            .padding(20)
        }
        .background(Theme.surface)
        .navigationTitle(list.group?.title ?? "All exercises")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Exercise rows. Ones whose equipment isn't ticked at this gym say so; picking one ticks it here.
struct LibraryRows: View {
    let exercises: [ExerciseDef]
    let gym: Gym?
    let current: [String]
    let onPick: (ExerciseDef) -> Void
    @AppStorage("keptPairs") private var keptPairs = ""
    @Environment(\.modelContext) private var context

    var body: some View {
        let info = gym?.info
        let already = current.compactMap { ExerciseCatalog.exercise($0) }
        LazyVStack(spacing: 0) {
            ForEach(exercises) { exercise in
                let available = Planner.isAvailable(exercise, gym: info)
                Button {
                    if !available, let gym { Store.setHas(exercise.equipmentType, true, gym: gym, context: context) }
                    onPick(exercise)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .scaledFont(16, weight: .semibold)
                                .foregroundStyle(available ? Theme.text : Theme.text.opacity(0.75))
                            Text(available ? "\(exercise.muscle.title) · \(exercise.equipmentType.name)"
                                           : "\(exercise.equipmentType.name) · not ticked here yet, tap to add")
                                .scaledFont(13)
                                .foregroundStyle(Theme.muted)
                            if available, let overlap = Overlap.find(exercise, among: already, kept: Overlap.keptPairs(keptPairs)) {
                                Label(overlap.message, systemImage: "exclamationmark.2")
                                    .scaledFont(13)
                                    .foregroundStyle(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Image(systemName: available ? "plus" : "plus.circle")
                            .foregroundStyle(available ? Theme.volt : Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(available ? "add-\(exercise.id)" : "addNew-\(exercise.id)")
            }
        }
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
