import SwiftUI
import SwiftData

/// Fix a workout after the fact: change the weight or reps of a set, or remove a set logged by mistake.
/// When it closes, personal records are worked out again across all workouts.
struct EditWorkoutSheet: View {
    let workout: Workout

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing: UUID?
    @State private var changed = false
    @State private var typingWeight: SetEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Edit workout")
                            .font(Theme.rounded(26))
                            .accessibilityAddTraits(.isHeader)
                        Text("Tap a set to change it.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Done") { close() }
                        .buttonStyle(ChipButtonStyle(foreground: Theme.volt))
                        .accessibilityIdentifier("editDone")
                }

                ForEach(workout.sortedEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name).font(.system(size: 16, weight: .bold))
                        ForEach(entry.completedSets) { set in
                            if editing == set.id {
                                editor(set, entry: entry)
                            } else {
                                row(set)
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .screen()
        .animation(.easeOut(duration: 0.2), value: editing)
        .modifier(TypeWeightAlert(typing: $typingWeight, onChange: { changed = true }))
        .interactiveDismissDisabled(changed)
    }

    private func label(_ set: SetEntry) -> String {
        set.weight > 0 ? "\(Fmt.weight(set.weight)) lb × \(set.reps)" : "\(set.reps) reps"
    }

    private func row(_ set: SetEntry) -> some View {
        Button { editing = set.id } label: {
            HStack(spacing: 14) {
                Text("\(set.index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, alignment: .leading)
                Text(label(set))
                    .font(Theme.rounded(19, .bold))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(set.index + 1): \(label(set))")
        .accessibilityHint("Double tap to edit this set")
        .accessibilityIdentifier("editSetRow")
    }

    private func editor(_ set: SetEntry, entry: ExerciseEntry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                stepper(value: set.weight <= 0 ? "BW" : Fmt.weight(set.weight), unit: set.weight <= 0 ? "body weight" : "lb",
                        lessLabel: "Lower weight", moreLabel: "Raise weight",
                        less: { set.weight = max(0, set.weight - entry.increment) },
                        more: { set.weight += entry.increment },
                        type: TypeWeightAlert.label(set.weight),
                        onType: { typingWeight = set })
                stepper(value: "\(set.reps)", unit: "reps", lessLabel: "One fewer rep", moreLabel: "One more rep",
                        less: { set.reps = max(1, set.reps - 1) },
                        more: { set.reps += 1 })
            }
            HStack(spacing: 8) {
                if workout.completedSets.count > 1 {
                    Button("Remove set", role: .destructive) { remove(set, from: entry) }
                        .buttonStyle(ChipButtonStyle(foreground: Color(hex: 0xFF6961)))
                        .accessibilityIdentifier("removeSet")
                }
                Spacer()
                Button("OK") { editing = nil }
                    .buttonStyle(ChipButtonStyle(foreground: Theme.volt))
                    .accessibilityIdentifier("editSetOK")
            }
        }
        .padding(10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.volt, lineWidth: 2))
    }

    private func stepper(value: String, unit: String, lessLabel: String, moreLabel: String,
                         less: @escaping () -> Void, more: @escaping () -> Void,
                         type typeLabel: String? = nil, onType: (() -> Void)? = nil) -> some View {
        HStack(spacing: 0) {
            CircleIconButton(systemName: "minus", label: lessLabel, fill: Theme.line, repeats: true) {
                less()
                changed = true
                Haptics.tap()
            }
            TypeableValue(label: typeLabel, onType: onType) {
                VStack(spacing: 0) {
                    Text(value)
                        .font(Theme.rounded(26))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            CircleIconButton(systemName: "plus", label: moreLabel, fill: Theme.line, repeats: true) {
                more()
                changed = true
                Haptics.tap()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func remove(_ set: SetEntry, from entry: ExerciseEntry) {
        editing = nil
        changed = true
        Store.remove(set, from: entry, context: context)
    }

    private func close() {
        if changed { Store.recountRecords(context: context) }
        dismiss()
    }
}
