import Foundation
import HealthKit

/// A run or walk read from Apple Health.
struct CardioItem: Identifiable {
    let id: UUID
    let date: Date
    let isRun: Bool
    let minutes: Double
    let miles: Double?

    var title: String {
        let kind = isRun ? "Run" : "Walk"
        if let miles, miles > 0 { return "\(kind) · \(String(format: "%.1f", miles)) mi" }
        return kind
    }

    var durationText: String {
        let total = Int(minutes * 60)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Apple Health: reads runs, walks and body weight; writes lifting sessions back.
@MainActor
final class HealthService: ObservableObject {
    @Published var cardio: [CardioItem] = []
    @Published var bodyWeight: Double?
    @Published var bodyWeightDate: Date?
    @Published var connected: Bool
    @Published var lastError: String?

    private let store = HKHealthStore()
    private static let connectedKey = "healthConnected"

    init() {
        connected = UserDefaults.standard.bool(forKey: Self.connectedKey)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows Apple's permission sheet (only the first time), then loads data.
    func connect() async {
        guard isAvailable else {
            lastError = "Apple Health is not available on this device."
            return
        }
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.distanceWalkingRunning),
        ]
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            connected = true
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            lastError = nil
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        guard connected, isAvailable else { return }
        if let items = try? await fetchCardio() { cardio = items }
        if let sample = try? await fetchLatestWeight() {
            bodyWeight = sample.quantity.doubleValue(for: .pound())
            bodyWeightDate = sample.endDate
        }
    }

    /// Save a finished lifting session to Apple Health as a strength training workout.
    /// A session this app already saved with the same start time (finished, then reopened) is replaced.
    func saveLifting(start: Date, end: Date) async -> Bool {
        guard connected, isAvailable, end > start else { return false }
        await removeSavedLifting(startingAt: start)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func removeSavedLifting(startingAt start: Date) async {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-1), end: start.addingTimeInterval(1),
                                        options: .strictStartDate),
        ])
        guard let earlier = try? await run(type: HKObjectType.workoutType(), predicate: predicate, limit: 10),
              !earlier.isEmpty else { return }
        try? await store.delete(earlier)
    }

    // MARK: queries

    private func fetchCardio() async throws -> [CardioItem] {
        let start = Calendar.current.date(byAdding: .day, value: -120, to: Date())
        let kinds = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForWorkouts(with: .walking),
        ])
        let dates = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [kinds, dates])
        let samples = try await run(type: HKObjectType.workoutType(), predicate: predicate, limit: 200)
        let distance = HKQuantityType(.distanceWalkingRunning)
        return samples.compactMap { $0 as? HKWorkout }.map { workout in
            CardioItem(id: workout.uuid,
                       date: workout.startDate,
                       isRun: workout.workoutActivityType == .running,
                       minutes: workout.duration / 60,
                       miles: workout.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .mile()))
        }
    }

    private func fetchLatestWeight() async throws -> HKQuantitySample? {
        let samples = try await run(type: HKQuantityType(.bodyMass), predicate: nil, limit: 1)
        return samples.first as? HKQuantitySample
    }

    private func run(type: HKSampleType, predicate: NSPredicate?, limit: Int) async throws -> [HKSample] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let store = self.store
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
