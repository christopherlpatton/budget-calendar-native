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
    private var service: BudgetService { BudgetService(database: database.database) }
    @State private var selection = "Calendar"
    var body: some View {
        NavigationSplitView {
            List(["Calendar", "Upcoming", "Insights", "Settings", "Documentation"], id: \.self, selection: $selection) { Text($0) }
                .navigationTitle("Budget Calendar")
        } detail: {
            Group {
                switch selection {
                case "Calendar": CalendarScreen(service: service)
                case "Upcoming": UpcomingScreen(service: service)
                case "Settings": SettingsScreen(database: database)
                default: ContentUnavailableView(selection, systemImage: icon, description: Text("This native screen is connected to the shared SQLite database."))
                }
            }.frame(minWidth: 720, minHeight: 480)
        }
    }
    private var icon: String { selection == "Calendar" ? "calendar" : "chart.bar" }
}

private struct CalendarScreen: View {
    let service: BudgetService
    @State private var items: [Item] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar").font(.largeTitle.bold())
            if items.isEmpty { ContentUnavailableView("No calendar items", systemImage: "calendar", description: Text("Add a bill, purchase, or deposit to begin.")) }
            else { List(items) { item in ItemRow(item: item) } }
        }.padding().task { load() }
    }
    private func load() { let calendar = Calendar.current; let now = Date(); let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!; let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!; let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; items = (try? service.items(from: f.string(from: start), through: f.string(from: end))) ?? [] }
}

private struct UpcomingScreen: View {
    let service: BudgetService
    @State private var items: [Item] = []
    var body: some View {
        VStack(alignment: .leading) { Text("Upcoming").font(.largeTitle.bold()); List(items) { ItemRow(item: $0) } }.padding().task { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let today = f.string(from: Date()); items = (try? service.items(from: today, through: "2099-12-31")) ?? [] }
    }
}

private struct ItemRow: View {
    let item: Item
    var body: some View { HStack { Image(systemName: item.type == .deposit ? "arrow.down.circle.fill" : "arrow.up.circle").foregroundStyle(item.type == .deposit ? .green : .pink); VStack(alignment: .leading) { Text(item.name); Text(item.date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(String(format: "$%.2f", Double(item.amountCents) / 100)).monospacedDigit(); if item.status == .paid { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } } }
}

private struct SettingsScreen: View {
    let database: DatabaseCoordinator
    var body: some View { Form { Section("Data") { LabeledContent("Database", value: BudgetCalendarPaths.database.path).textSelection(.enabled); LabeledContent("Schema", value: "v\(DatabaseCoordinator.supportedSchemaVersion)"); LabeledContent("Journal", value: "SQLite WAL") }; Section("Compatibility") { Text("The native app reads and writes the same database as Budget Calendar 0.1.7. Close the other app before making changes.").foregroundStyle(.secondary) } }.formStyle(.grouped).padding() }
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
