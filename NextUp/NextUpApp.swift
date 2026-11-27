import SwiftUI
import SwiftData

@main
struct NextUpApp: App {
    /// Set when the saved workouts could not be opened at launch.
    static var databaseProblem: String?
    private let container: ModelContainer
    @StateObject private var health: HealthService
    @StateObject private var rest = RestTimer.shared

    init() {
        // "-demoData" fills the app with six weeks of sample history kept in memory only.
        // It is used for screenshots and UI tests and never touches real data.
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        let schema = Schema([Gym.self, Equipment.self, Workout.self, ExerciseEntry.self, SetEntry.self, ExercisePrefs.self,
                             CustomEquipment.self, CustomExercise.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never crash on launch. The saved file is left exactly as it is (nothing is deleted),
            // the app opens with a temporary empty database, and a message explains what happened.
            NextUpApp.databaseProblem = "\(error)"
            let temporary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [temporary])
            } catch {
                fatalError("Could not open even a temporary workout database: \(error)")
            }
        }
        Store.seedIfNeeded(ModelContext(container), demo: demo)
        // The Lock Screen card stays while a workout is in progress (even if the app was closed), else it is cleared.
        let open = try? ModelContext(container).fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil })).first
        RestTimer.shared.resume(workoutTitle: open?.title, started: open?.startedAt)
        // Your routine (the days and their exercises) is read before anything plans a workout.
        _ = RoutineStore.shared
        // Exercises and machines you made yourself join the built-in lists.
        Store.loadCustom(ModelContext(container))
        let health = HealthService()
        _health = StateObject(wrappedValue: health)
        // Apple Watch: also runs when the Watch wakes the app in the background.
        WatchLink.shared.activate(container: container, health: health)
        // A countdown started, lengthened or skipped on the phone shows on the Watch too.
        RestTimer.shared.onChange = { WatchLink.shared.push() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .environmentObject(rest)
                .preferredColorScheme(.dark)
                .tint(Theme.volt)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var health: HealthService
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var session: Workout?
    @State private var didResume = false
    @State private var showDatabaseProblem = NextUpApp.databaseProblem != nil

    var body: some View {
        TabView {
            TodayView(onStart: { session = $0 })
                .tabItem { Label("Today", systemImage: "dumbbell.fill") }
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            GymsView()
                .tabItem { Label("Gyms", systemImage: "mappin.and.ellipse") }
        }
        .fullScreenCover(item: $session) { workout in
            WorkoutFlowView(workout: workout) { session = nil }
        }
        .onAppear {
            // Pick an unfinished workout back up if the app was closed mid-session.
            guard !didResume else { return }
            didResume = true
            session = workouts.first { $0.endedAt == nil }
        }
        .onChange(of: workouts.first { $0.endedAt == nil }?.id) { _, id in
            // A finished workout reopened from the calendar: bring up its workout screen.
            if session == nil, let id { session = workouts.first { $0.id == id } }
        }
        .alert("Your saved workouts could not be opened", isPresented: $showDatabaseProblem) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted. The app is running on a temporary blank copy, so anything you log now will not be kept. Close the app fully and open it again. If this keeps happening, update the app, and contact support before deleting it.")
        }
        .onReceive(WatchLink.shared.$closeWorkoutID) { id in
            // The Watch discarded the workout on screen: close it before it is deleted.
            if let id, session?.id == id { session = nil }
        }
        .onChange(of: watchSignature, initial: true) { _, _ in WatchLink.shared.push() }
        .task { await health.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await health.refresh() }
                WatchLink.shared.push()
            }
        }
    }

    /// Changes whenever something the Watch shows has changed.
    private var watchSignature: String {
        guard let latest = workouts.first else { return "none" }
        let sets = latest.entries.flatMap(\.sets)
        let weights = sets.reduce(0) { $0 + $1.weight + Double($1.reps) }
        return "\(workouts.count)-\(latest.id)-\(latest.endedAt?.timeIntervalSince1970 ?? 0)-\(latest.entries.count)"
            + "-\(sets.count)-\(latest.completedSets.count)-\(weights)-\(RestSetting.current)"
    }
}
