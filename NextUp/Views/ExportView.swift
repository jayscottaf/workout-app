import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

extension Store {
    /// Every logged set of every workout, ready for `Export.csv`.
    static func exportSets(_ workouts: [Workout]) -> [ExportSet] {
        workouts.flatMap { workout in
            workout.sortedEntries.flatMap { entry in
                entry.completedSets.enumerated().map { offset, set in
                    let def = entry.exercise
                    return ExportSet(date: set.completedAt ?? workout.startedAt, workout: workout.title, gym: workout.gymName,
                                     exercise: entry.name, muscle: def?.muscle.title ?? "", compound: def?.compound ?? false,
                                     equipment: entry.equipmentName.isEmpty ? (def?.equipmentType.name ?? "") : entry.equipmentName,
                                     setNumber: offset + 1, weight: set.weight, reps: set.reps, pr: set.prKind)
                }
            }
        }
    }

    /// Writes the CSV to a temporary file and returns where it is.
    static func writeExport(_ workouts: [Workout], now: Date = Date()) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Export.fileName(on: now))
        try Export.csv(exportSets(workouts)).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    struct ImportResult {
        var source: Import.Source
        var workouts = 0
        var sets = 0
        var skipped = 0
        var newExercises: [String] = []
    }

    /// Saves workouts read from Strong or Hevy as finished workouts. Ones already here (same start
    /// time, within a minute) are skipped, so importing the same file twice adds nothing.
    /// Machine exercises are tied to that machine at your first gym, which gets it ticked if needed.
    static func importWorkouts(_ imported: [ImportedWorkout], source: Import.Source, context: ModelContext) -> ImportResult {
        var result = ImportResult(source: source)
        let existing = ((try? context.fetch(FetchDescriptor<Workout>())) ?? []).map(\.startedAt)
        let gym = ((try? context.fetch(FetchDescriptor<Gym>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).first
        var matches: [String: ExerciseDef] = [:]

        func exercise(for name: String) -> ExerciseDef? {
            if let known = matches[name] { return known }
            let def: ExerciseDef?
            switch Import.match(name) {
            case .builtIn(let id):
                def = ExerciseCatalog.exercise(id)
            case .custom(let title, let muscle, let equipmentID):
                if let mine = ExerciseCatalog.custom.first(where: { $0.name.lowercased() == title.lowercased() }) {
                    def = mine
                } else {
                    def = createExercise(name: title, muscle: muscle, equipmentID: equipmentID, compound: false,
                                         repLow: 8, repHigh: 12, gym: nil, context: context)
                    result.newExercises.append(title)
                }
            }
            matches[name] = def
            return def
        }

        func machine(for def: ExerciseDef) -> Equipment? {
            guard def.equipmentType.category == .machine, let gym else { return nil }
            if let have = gym.items.first(where: { $0.typeID == def.equipment }) { return have }
            setHas(def.equipmentType, true, gym: gym, context: context)
            return gym.items.first { $0.typeID == def.equipment }
        }

        for item in imported {
            if existing.contains(where: { abs($0.timeIntervalSince(item.start)) < 60 }) { result.skipped += 1; continue }
            let workout = Workout(day: nil, isQuick: false, gymID: gym?.id, gymName: gym?.name ?? "", startedAt: item.start)
            workout.dayTitle = item.title
            workout.endedAt = item.end
            context.insert(workout)
            let step = item.end.timeIntervalSince(item.start) / Double(max(1, item.exercises.reduce(0) { $0 + $1.sets.count }))
            var clock = item.start
            for (order, imported) in item.exercises.enumerated() {
                guard let def = exercise(for: imported.name) else { continue }
                let entry = ExerciseEntry(exerciseID: def.id, order: order)
                context.insert(entry)
                entry.workout = workout
                let equipment = machine(for: def)
                entry.equipmentID = equipment?.id
                entry.equipmentName = equipment?.name ?? def.equipmentType.name
                entry.historyKey = HistoryKey.make(exerciseID: def.id, equipment: equipment?.info)
                entry.repLow = def.repLow
                entry.repHigh = def.repHigh
                entry.increment = equipment?.increment ?? def.equipmentType.step
                entry.restSeconds = def.restSeconds
                entry.explanation = "Imported from \(source.rawValue)."
                for (index, done) in imported.sets.enumerated() {
                    let set = SetEntry(index: index, target: SetTarget(weight: done.weight, reps: done.reps, lastWeight: nil, lastReps: nil))
                    context.insert(set)
                    set.entry = entry
                    clock = clock.addingTimeInterval(step)
                    set.completedAt = min(clock, item.end)
                    result.sets += 1
                }
            }
            result.workouts += 1
        }
        try? context.save()
        recountRecords(context: context)
        return result
    }
}

/// Settings section: save or send your whole history as a spreadsheet file.
struct ExportSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @State private var file: ExportFile?
    @State private var failed = false
    @State private var picking = false
    @State private var importMessage: String?

    var body: some View {
        Section {
            Button {
                do { file = ExportFile(url: try Store.writeExport(workouts)) } catch { failed = true }
            } label: {
                Label("Export workouts (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(workouts.isEmpty)
            .accessibilityIdentifier("exportCSV")
            Button {
                picking = true
            } label: {
                Label("Import from Strong or Hevy", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("importCSV")
        } header: {
            Text("Your data")
        } footer: {
            Text("Export makes a spreadsheet of every set you have logged, which you can save to Files, AirDrop or email. To bring your history over, export a CSV file from Strong or Hevy (both have an export option in their settings) and pick it here.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { picked in
            importMessage = readImport(picked)
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .sheet(item: $file) { file in
            ShareSheet(items: [file.url]).ignoresSafeArea()
        }
        .alert("Could not make the file", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was changed. Please try again.")
        }
    }
}

extension ExportSection {
    /// Reads the picked file and saves its workouts. Returns what to tell you.
    private func readImport(_ picked: Result<URL, Error>) -> String {
        guard case .success(let url) = picked else { return "The file could not be opened." }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return "The file could not be read."
        }
        do {
            let (source, imported) = try Import.read(text)
            let result = Store.importWorkouts(imported, source: source, context: context)
            var lines = ["Added \(result.workouts) workout\(result.workouts == 1 ? "" : "s") (\(result.sets) sets) from \(source.rawValue)."]
            if result.skipped > 0 { lines.append("\(result.skipped) were already here and were skipped.") }
            if !result.newExercises.isEmpty {
                lines.append("New exercises made for names that did not match: \(result.newExercises.prefix(8).joined(separator: ", "))\(result.newExercises.count > 8 ? ", and more" : ""). You can change or merge them under Your exercises and machines.")
            }
            if source == .strong {
                lines.append("Strong does not say which unit it used, so weights were read as \(Units.spoken).")
            }
            return lines.joined(separator: "\n\n")
        } catch Import.Problem.empty {
            return "No sets with reps were found in that file."
        } catch {
            return "That doesn't look like a Strong or Hevy export. Export a CSV from either app and pick it here."
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The standard iOS share sheet (Save to Files, AirDrop, Mail, ...).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
