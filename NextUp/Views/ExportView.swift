import SwiftUI
import SwiftData
import UIKit

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
}

/// Settings section: save or send your whole history as a spreadsheet file.
struct ExportSection: View {
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @State private var file: ExportFile?
    @State private var failed = false

    var body: some View {
        Section {
            Button {
                do { file = ExportFile(url: try Store.writeExport(workouts)) } catch { failed = true }
            } label: {
                Label("Export workouts (CSV)", systemImage: "square.and.arrow.up")
            }
            .disabled(workouts.isEmpty)
            .accessibilityIdentifier("exportCSV")
        } header: {
            Text("Your data")
        } footer: {
            Text("Your workouts are saved only on this iPhone. Export makes a spreadsheet of every set you have logged, which you can save to Files or iCloud Drive, AirDrop or email. Do this now and then as a backup.")
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
