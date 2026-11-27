import SwiftUI
import SwiftData

/// Each gym with its own equipment. Machines keep separate history per gym; free weights share one.
struct GymsView: View {
    /// Redraws every weight when pounds or kilograms is changed in Settings.
    @AppStorage(Units.key) private var weightUnit = WeightUnit.lb.rawValue
    @Environment(\.modelContext) private var context
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @Query private var workouts: [Workout]
    @AppStorage("currentGymID") private var currentGymID = ""

    @State private var selectedID: UUID?
    @State private var showAddGym = false
    @State private var showAddEquipment = false
    @State private var editing: Equipment?
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmDelete = false
    @State private var tickingGym: Gym?

    private var currentGym: Gym? { gyms.first { $0.id.uuidString == currentGymID } ?? gyms.first }
    private var selected: Gym? { gyms.first { $0.id == selectedID } ?? currentGym }

    var body: some View {
        let gym = selected
        let counts = sessionCounts()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Gyms")
                        .scaledFont(34, weight: .heavy, design: .rounded)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    CircleIconButton(systemName: "plus", label: "Add a gym", fill: Theme.surface, foreground: Theme.volt) {
                        showAddGym = true
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gyms) { item in
                            Button(item.name) {
                                // Tapping the gym already shown opens its equipment list.
                                if item.id == gym?.id { tickingGym = item } else { selectedID = item.id }
                            }
                            .accessibilityIdentifier("gymChip-\(item.name)")
                                .buttonStyle(ChipButtonStyle(fill: item.id == gym?.id ? Theme.volt : Theme.surface,
                                                             foreground: item.id == gym?.id ? Theme.onVolt : Theme.text))
                        }
                    }
                }

                if let gym {
                    gymCard(gym)
                    Button { tickingGym = gym } label: {
                        Label("Choose equipment at \(gym.name)", systemImage: "checklist")
                            .scaledFont(16, weight: .bold)
                            .foregroundStyle(Theme.onVolt)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.volt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chooseEquipment")
                    let shared = gym.sortedEquipment.filter { $0.type?.category != .machine }
                    let machines = gym.sortedEquipment.filter { $0.type?.category == .machine }
                    if !shared.isEmpty {
                        section("Free weights · one history everywhere", shared, counts: counts)
                    }
                    if !machines.isEmpty {
                        section("Machines · tracked separately here", machines, counts: counts)
                    }
                    Button("Add equipment") { showAddEquipment = true }
                        .scaledFont(15, weight: .bold)
                        .foregroundStyle(Theme.volt)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .buttonStyle(.plain)
                    Text("Suggestions only use equipment listed here. Set each one's step size to match the real jumps between weights, so \"next weight up\" is a weight you can actually load.")
                        .scaledFont(13)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Add your first gym to get suggestions that match its equipment.")
                        .foregroundStyle(Theme.muted)
                        .card()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screen()
        .sheet(isPresented: $showAddGym) {
            AddGymSheet { name, typeIDs in
                let gym = Store.makeGym(name: name, typeIDs: typeIDs, context: context)
                try? context.save()
                selectedID = gym.id
            }
        }
        .sheet(isPresented: $showAddEquipment) {
            if let gym { AddEquipmentSheet(gym: gym) }
        }
        .sheet(item: $tickingGym) { item in
            GymEquipmentSheet(gym: item)
        }
        .sheet(item: $editing) { item in
            EquipmentEditSheet(equipment: item)
        }
        .alert("Rename gym", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let name = nameDraft.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { gym?.name = name }
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(gym?.name ?? "this gym")? Workouts you logged there are kept.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete gym", role: .destructive) {
                if let gym {
                    if gym.id.uuidString == currentGymID { currentGymID = "" }
                    selectedID = nil
                    context.delete(gym)
                    try? context.save()
                }
            }
            Button("Keep it", role: .cancel) {}
        }
    }

    private func gymCard(_ gym: Gym) -> some View {
        let isCurrent = gym.id == currentGym?.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gym.name).scaledFont(17, weight: .bold)
                Text("\(isCurrent ? "You are training here" : "Not your current gym") · \(gym.items.count) pieces of equipment")
                    .scaledFont(13)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Text("CURRENT")
                    .scaledFont(12, weight: .heavy)
                    .foregroundStyle(Theme.volt)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.voltDim, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button("Train here") { currentGymID = gym.id.uuidString }
                    .buttonStyle(ChipButtonStyle(fill: Theme.volt, foreground: Theme.onVolt))
            }
            Menu {
                Button("Rename") {
                    nameDraft = gym.name
                    renaming = true
                }
                if gyms.count > 1 {
                    Button("Delete gym", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .scaledFont(16, weight: .heavy)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More options for \(gym.name)")
        }
        .card()
    }

    private func section(_ title: String, _ items: [Equipment], counts: [UUID: Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) }
                    Button { editing = item } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).scaledFont(16, weight: .semibold)
                                Text("\(item.type?.loading ?? "Equipment") · \(Fmt.lb(item.increment)) steps")
                                    .scaledFont(13)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            let count = counts[item.id] ?? 0
                            if count > 0 {
                                Text("\(count) session\(count == 1 ? "" : "s")")
                                    .scaledFont(13)
                                    .foregroundStyle(Theme.muted)
                            }
                            Image(systemName: "chevron.right")
                                .scaledFont(12, weight: .heavy)
                                .foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// How many finished sessions used each piece of equipment.
    private func sessionCounts() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for workout in workouts where workout.endedAt != nil {
            for id in Set(workout.allEntries.compactMap(\.equipmentID)) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }
}

struct AddGymSheet: View {
    let onSave: (String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var chosen = Set(EquipmentCatalog.commonIDs)
    @State private var newMachine = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("For example: Downtown gym", text: $name)
                }
                Section {
                    ForEach(EquipmentCatalog.all) { type in
                        Toggle(type.name, isOn: Binding(
                            get: { chosen.contains(type.id) },
                            set: { isOn in
                                if isOn { chosen.insert(type.id) } else { chosen.remove(type.id) }
                            }))
                    }
                    Button("Add a machine that is not listed") { newMachine = true }
                } header: {
                    Text("What does it have?")
                } footer: {
                    Text("Tick what this gym has. You can change this any time.")
                }
            }
            .navigationTitle("New gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ordered = EquipmentCatalog.all.map(\.id).filter { chosen.contains($0) }
                        onSave(name.trimmingCharacters(in: .whitespaces), ordered)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $newMachine) {
                NewMachineSheet(gym: nil) { chosen.insert($0.id) }
            }
        }
    }
}

struct AddEquipmentSheet: View {
    let gym: Gym
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var newMachine = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EquipmentCatalog.all) { type in
                        let have = gym.items.filter { $0.typeID == type.id }.count
                        Button {
                            let item = Equipment(typeID: type.id, name: have == 0 ? type.name : "\(type.name) \(have + 1)",
                                                 increment: type.step)
                            context.insert(item)
                            item.gym = gym
                            try? context.save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.name).foregroundStyle(Theme.text)
                                    Text(type.loading).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if have > 0 {
                                    Text("\(have) added").font(.footnote).foregroundStyle(.secondary)
                                }
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.volt)
                            }
                        }
                    }
                    Button("Add a machine that is not listed") { newMachine = true }
                } footer: {
                    Text("Add the same machine twice if the gym has two that feel different. Each keeps its own history.")
                }
            }
            .navigationTitle("Add to \(gym.name)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $newMachine) { NewMachineSheet(gym: gym) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct EquipmentEditSheet: View {
    @Bindable var equipment: Equipment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $equipment.name)
                }
                Section {
                    Stepper("Goes up in \(Fmt.lb(equipment.increment)) steps", value: $equipment.increment,
                            in: Units.step(1)...Units.step(50), step: Units.step(2.5))
                } footer: {
                    Text(equipment.type?.category == .machine
                         ? "This machine keeps its own history, because the same number on a different machine is not the same effort."
                         : "Free weights share one history across all your gyms. Only the step size is specific to this gym.")
                }
                Section {
                    TextField("Seat 4, back pad 2", text: $equipment.notes, axis: .vertical)
                        .accessibilityIdentifier("equipmentNotes")
                } header: {
                    Text("Your settings")
                } footer: {
                    Text("Shown on the workout screen whenever you use this at this gym.")
                }
                Section {
                    Button("Remove from this gym", role: .destructive) {
                        let store = context
                        let removed = equipment
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            store.delete(removed)
                            try? store.save()
                        }
                    }
                }
            }
            .navigationTitle(equipment.type?.name ?? "Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Tick what this gym has, from inside a workout. Swap and Add use the new list right away.
struct GymEquipmentSheet: View {
    let gym: Gym
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var newMachine = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(EquipmentCatalog.all) { type in
                        Toggle(isOn: Binding(
                            get: { gym.items.contains { $0.typeID == type.id } },
                            set: { Store.setHas(type, $0, gym: gym, context: context) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.name)
                                Text(type.loading).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.volt)
                    }
                    Button("Add a machine that is not listed") { newMachine = true }
                        .accessibilityIdentifier("newMachine")
                } footer: {
                    Text("Changes are saved for \(gym.name). Swap and Add an exercise only offer what is ticked. Rename machines or set their weight steps under Gyms.")
                }
            }
            .navigationTitle("\(gym.name) equipment")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $newMachine) { NewMachineSheet(gym: gym) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
