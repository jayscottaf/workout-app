import SwiftUI
import SwiftData

/// Make your own exercise. It then behaves like a built-in one: suggestions, records, swaps and the Watch.
struct CreateExerciseSheet: View {
    /// The gym you are at, if any. Whatever the exercise uses is ticked there so it can be picked straight away.
    let gym: Gym?
    let onCreate: (ExerciseDef) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var machines: [CustomEquipment]
    @State private var name = ""
    @State private var muscle: Muscle = .triceps
    @State private var equipmentID = "cable"
    @State private var compound = false
    @State private var repLow = 10
    @State private var repHigh = 15
    @State private var newMachine = false

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool { ExerciseCatalog.all.contains { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. One-arm cable pulldown", text: $name)
                        .accessibilityIdentifier("exerciseName")
                    Picker("Main muscle", selection: $muscle) {
                        ForEach(Muscle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } footer: {
                    if nameTaken { Text("There is already an exercise with this name.") }
                }

                Section {
                    Picker("Uses", selection: $equipmentID) {
                        Text(EquipmentCatalog.bodyweight.name).tag(EquipmentCatalog.bodyweightID)
                        ForEach(EquipmentCatalog.all) { Text($0.name).tag($0.id) }
                    }
                    .id(machines.count)
                    Button("Add a machine that is not listed") { newMachine = true }
                        .accessibilityIdentifier("newMachine")
                } footer: {
                    Text("The app only offers this exercise at gyms that have what it uses.")
                }

                Section {
                    Toggle("Big lift (several muscles)", isOn: $compound).tint(Theme.volt)
                    Stepper("At least \(repLow) reps", value: $repLow, in: 1...29)
                    Stepper("Up to \(repHigh) reps", value: $repHigh, in: 2...30)
                } footer: {
                    Text("Big lifts like presses, rows and squats get a longer rest. Reach the top number on every set and the app suggests the next weight up.")
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(cleanName.isEmpty || nameTaken)
                        .accessibilityIdentifier("saveExercise")
                }
            }
            .onChange(of: repLow) { _, low in if repHigh <= low { repHigh = low + 1 } }
            .onChange(of: repHigh) { _, high in if repLow >= high { repLow = high - 1 } }
            .onChange(of: compound) { _, big in (repLow, repHigh) = big ? (8, 12) : (10, 15) }
            .sheet(isPresented: $newMachine) {
                NewMachineSheet(gym: gym) { equipmentID = $0.id }
            }
        }
    }

    private func save() {
        let exercise = Store.createExercise(name: cleanName, muscle: muscle, equipmentID: equipmentID, compound: compound,
                                            repLow: repLow, repHigh: repHigh, gym: gym, context: context)
        // The screen that opened this one closes it.
        onCreate(exercise)
    }
}

/// Add a kind of machine that is not on the built-in list (a Matrix or Life Fitness machine, for example).
struct NewMachineSheet: View {
    let gym: Gym?
    var onCreate: (EquipmentType) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kind: CustomEquipment.Kind = .stack
    @State private var increment: Double = Units.step(5)

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool { EquipmentCatalog.all.contains { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Matrix glute machine", text: $name)
                        .accessibilityIdentifier("machineName")
                    Picker("Weights", selection: $kind) {
                        ForEach(CustomEquipment.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Weight goes up by", selection: $increment) {
                        ForEach(Units.stepChoices(), id: \.self) { Text(Fmt.lb($0)).tag($0) }
                    }
                } footer: {
                    if nameTaken {
                        Text("There is already a machine with this name.")
                    } else if let gym {
                        Text("It is added to \(gym.name). Tick it at your other gyms under Gyms.")
                    } else {
                        Text("Tick it at each gym that has one under Gyms.")
                    }
                }
            }
            .navigationTitle("New machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let type = Store.createMachine(name: cleanName, kind: kind, increment: increment,
                                                       gym: gym, context: context)
                        dismiss()
                        onCreate(type)
                    }
                    .disabled(cleanName.isEmpty || nameTaken)
                    .accessibilityIdentifier("saveMachine")
                }
            }
        }
    }
}

/// Settings: the exercises and machines you made yourself.
struct CustomList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomExercise.createdAt) private var exercises: [CustomExercise]
    @Query(sort: \CustomEquipment.createdAt) private var machines: [CustomEquipment]
    @State private var creating = false
    @State private var newMachine = false
    @State private var replacing: (CustomExercise, ExerciseDef)?

    var body: some View {
        List {
            Section {
                ForEach(exercises.filter { !$0.retired }) { exercise in
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            Text("\(exercise.def.muscle.title) · \(exercise.def.equipmentType.name)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Store.builtInMatches(for: exercise)) { match in
                            Button("Switch to built-in: \(match.name)") { replacing = (exercise, match) }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("useBuiltIn-\(match.id)")
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { Store.retire(exercise, context: context) }
                    }
                }
                Button("Create an exercise") { creating = true }
            } header: {
                Text("Your exercises")
            } footer: {
                Text("Swipe left to remove one. Workouts you already logged with it are kept. Switching to a built-in exercise moves your logged sets over to it.")
            }

            Section {
                ForEach(machines.filter { !$0.retired }) { machine in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(machine.name)
                        Text(machine.type.loading).font(.footnote).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { Store.retire(machine, context: context) }
                    }
                }
                Button("Add a machine") { newMachine = true }
            } header: {
                Text("Your machines")
            } footer: {
                Text("Tick these at each gym that has one under Gyms.")
            }
        }
        .navigationTitle("Your exercises")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { CreateExerciseSheet(gym: nil) { _ in creating = false } }
        .confirmationDialog("Use the built-in \(replacing?.1.name ?? "exercise")?",
                            isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
                            titleVisibility: .visible) {
            Button("Use built-in") {
                if let (exercise, match) = replacing { Store.replace(exercise, with: match, context: context) }
                replacing = nil
            }
            Button("Cancel", role: .cancel) { replacing = nil }
        } message: {
            Text("Sets you logged on yours move over to it. Your own version is removed.")
        }
        .sheet(isPresented: $newMachine) { NewMachineSheet(gym: nil) }
    }
}
