import SwiftUI
import SwiftData

@main
struct BeanFocusApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([JournalEntry.self, DailyMetrics.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
