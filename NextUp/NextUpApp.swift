import SwiftUI
import SwiftData

@main
struct NextUpApp: App {
    private let container: ModelContainer
    @StateObject private var health = HealthService()
    @StateObject private var rest = RestTimer()

    init() {
        // "-demoData" fills the app with six weeks of sample history kept in memory only.
        // It is used for screenshots and UI tests and never touches real data.
        let demo = ProcessInfo.processInfo.arguments.contains("-demoData")
        let schema = Schema([Gym.self, Equipment.self, Workout.self, ExerciseEntry.self, SetEntry.self, ExercisePrefs.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the workout database: \(error)")
        }
        Store.seedIfNeeded(ModelContext(container), demo: demo)
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
        .task { await health.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await health.refresh() } }
        }
    }
}
