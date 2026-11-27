import SwiftUI
import SwiftData

/// Shown once, the first time the app opens with no workouts: the few choices that shape
/// every suggestion, so a new lifter does not have to find them in Settings.
struct WelcomeView: View {
    static let seenKey = "didSeeWelcome"

    @Environment(\.modelContext) private var context
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @AppStorage(seenKey) private var seen = false
    @AppStorage("weeklyGoal") private var weeklyGoal = 3
    @AppStorage(Units.key) private var unitRaw = WeightUnit.lb.rawValue
    @State private var gymName = ""
    @ObservedObject private var routine = RoutineStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Next Up")
                            .scaledFont(28, weight: .heavy, design: .rounded)
                        Text("Log a set with one tap. The app works out today's weights from what you did last time, and tells you when to go up.")
                            .scaledFont(15)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Weights in", selection: Binding(
                        get: { WeightUnit(rawValue: unitRaw) ?? .lb },
                        set: { unit in
                            Store.switchUnit(to: unit, context: context)
                            unitRaw = unit.rawValue
                        })) {
                        Text("Pounds (lb)").tag(WeightUnit.lb)
                        Text("Kilograms (kg)").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("welcomeUnit")
                } header: {
                    Text("Weights")
                }

                Section {
                    ForEach(Presets.all) { preset in
                        Button {
                            routine.use(preset)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: routine.preset?.id == preset.id ? "checkmark.circle.fill" : "circle")
                                    .scaledFont(20)
                                    .foregroundStyle(routine.preset?.id == preset.id ? Theme.volt : Theme.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).scaledFont(16, weight: .semibold)
                                    Text(preset.summary).scaledFont(13).foregroundStyle(Theme.muted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(routine.preset?.id == preset.id ? .isSelected : [])
                    }
                } header: {
                    Text("Your routine")
                } footer: {
                    Text("Change the days and exercises any time in Settings.")
                }

                Section {
                    Stepper("\(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s") a week", value: $weeklyGoal, in: 1...7)
                } header: {
                    Text("Your goal")
                } footer: {
                    Text("Your streak counts weeks where you reach this.")
                }

                Section {
                    TextField("Gym name", text: $gymName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("welcomeGymName")
                } header: {
                    Text("Where you train")
                } footer: {
                    Text("It starts with the equipment most gyms have. Tick what yours has, or add more gyms, under Gyms.")
                }

                Section {
                    Button("Start") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("welcomeStart")
                } footer: {
                    Text("Your workouts are kept only on this iPhone and your Apple Watch. You can export a backup any time in Settings.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .interactiveDismissDisabled()
            .onAppear { gymName = gyms.first?.name ?? "My gym" }
        }
    }

    private func finish() {
        let name = gymName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gym = gyms.first, !name.isEmpty, name != gym.name {
            gym.name = name
            try? context.save()
        }
        seen = true
    }
}
