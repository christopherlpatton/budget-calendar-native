import SwiftUI
import BudgetCalendarCore

@main
struct BudgetCalendarApp: App {
    @State private var database: DatabaseCoordinator?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup("Budget Calendar") {
            Group {
                if let database {
                    MainWindow(database: database)
                } else if let startupError {
                    StartupErrorView(message: startupError)
                } else {
                    ProgressView("Opening Budget Calendar…")
                }
            }
            .task { openDatabase() }
        }
        .windowResizability(.contentSize)
    }

    private func openDatabase() {
        guard database == nil, startupError == nil else { return }
        do { database = try DatabaseCoordinator() }
        catch { startupError = error.localizedDescription }
    }
}

private struct MainWindow: View {
    let database: DatabaseCoordinator
    @State private var selection = "Calendar"
    var body: some View {
        NavigationSplitView {
            List(["Calendar", "Upcoming", "Insights", "Settings", "Documentation"], id: \.self, selection: $selection) { Text($0) }
                .navigationTitle("Budget Calendar")
        } detail: {
            VStack(spacing: 12) {
                ContentUnavailableView(selection, systemImage: icon, description: Text("The native SwiftUI shell is connected to the shared SQLite database."))
                Text(BudgetCalendarPaths.database.path).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    private var icon: String { selection == "Calendar" ? "calendar" : "chart.bar" }
}

private struct StartupErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("Budget Calendar could not open").font(.title2.bold())
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 520)
            Text("Close the Electron app, make a backup of budget.sqlite, and try again.").foregroundStyle(.secondary)
        }.padding(40)
    }
}
