import Foundation
import HealthKit
import WatchKit

/// Records the workout on the Watch: live heart rate and calories, saved to Apple Health at the end.
/// While it runs, watchOS keeps the app on screen when you raise your wrist.
@MainActor
final class WorkoutTracker: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published var heartRate: Double?
    @Published var averageHeartRate: Double?
    @Published var calories: Double?

    /// The phone's workout this recording belongs to, once known.
    var workoutID: UUID?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false

    @discardableResult
    func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        } catch {
            return false
        }
    }

    /// Returns true when recording is running.
    @discardableResult
    func start(at date: Date) async -> Bool {
        guard !isRunning, !isStarting else { return isRunning }
        isStarting = true
        defer { isStarting = false }
        guard await authorize() else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            self.session = session
            self.builder = builder
            workoutID = nil
            heartRate = nil
            averageHeartRate = nil
            calories = nil
            isRunning = true
            return true
        } catch {
            return false
        }
    }

    /// Stop recording. Returns true when the workout was saved to Apple Health.
    @discardableResult
    func end(at date: Date, save: Bool) async -> Bool {
        guard let session, let builder else { return false }
        self.session = nil
        self.builder = nil
        isRunning = false
        workoutID = nil
        session.end()
        do {
            try await builder.endCollection(at: max(date, builder.startDate ?? date))
            if save {
                _ = try await builder.finishWorkout()
                return true
            }
            builder.discardWorkout()
            return false
        } catch {
            builder.discardWorkout()
            return false
        }
    }
}

extension WorkoutTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let beats = HKUnit.count().unitDivided(by: .minute())
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))
        let latest = heart?.mostRecentQuantity()?.doubleValue(for: beats)
        let average = heart?.averageQuantity()?.doubleValue(for: beats)
        let burned = energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            guard self.isRunning else { return }
            if let latest { self.heartRate = latest }
            if let average { self.averageHeartRate = average }
            if let burned { self.calories = burned }
        }
    }
}

/// The rest countdown between sets. It taps your wrist when rest is over.
@MainActor
final class RestClock: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var total: TimeInterval = 0
    private var timer: Timer?

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, endDate?.timeIntervalSince(date) ?? 0)
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        endDate = Date().addingTimeInterval(total)
        schedule()
    }

    func add(seconds: Int) {
        guard let endDate else { return }
        self.endDate = endDate.addingTimeInterval(TimeInterval(seconds))
        total += TimeInterval(seconds)
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }

    private func schedule() {
        timer?.invalidate()
        guard let endDate else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(0.1, endDate.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                WKInterfaceDevice.current().play(.notification)
                self.stop()
            }
        }
    }
}
