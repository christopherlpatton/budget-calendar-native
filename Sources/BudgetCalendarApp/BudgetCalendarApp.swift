import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
                case "Insights": InsightsScreen(service: service)
                case "Settings": SettingsScreen(database: database, service: service)
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
    @State private var categories: [Category] = []
    @State private var editor: EditorTarget?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Calendar").font(.largeTitle.bold()); Spacer(); Button("Add transaction", systemImage: "plus") { editor = EditorTarget(item: nil) }.buttonStyle(.borderedProminent) }
            if items.isEmpty { ContentUnavailableView("No calendar items", systemImage: "calendar", description: Text("Add a bill, purchase, or deposit to begin.")) }
            else { List(items) { item in Button { editor = EditorTarget(item: item) } label: { ItemRow(item: item) }.buttonStyle(.plain).contextMenu { Button(item.status == .paid ? "Mark planned" : "Mark paid") { try? service.setPaid(id: item.id!, paid: item.status != .paid); load() } } } }
        }.padding().task { load() }
            .sheet(item: $editor) { target in TransactionEditor(service: service, categories: categories, existing: target.item) { load() } }
    }
    private func load() { let calendar = Calendar.current; let now = Date(); let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!; let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!; items = (try? service.visibleItems(from: NativeDate.string(start), through: NativeDate.string(end))) ?? []; categories = (try? service.categories()) ?? [] }
}

private struct UpcomingScreen: View {
    let service: BudgetService
    @State private var items: [Item] = []
    var body: some View {
        VStack(alignment: .leading) { Text("Upcoming").font(.largeTitle.bold()); List(items) { ItemRow(item: $0) } }.padding().task { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let today = f.string(from: Date()); items = (try? service.items(from: today, through: "2099-12-31")) ?? [] }
    }
}

private struct InsightsScreen: View {
    let service: BudgetService
    @State private var summaries: [PayPeriodSummary] = []
    @State private var actual = 0
    @State private var projected = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Insights").font(.largeTitle.bold())
            HStack(spacing: 14) { InsightCard(title: "Actual balance", amount: actual, tint: .green); InsightCard(title: "Projected balance", amount: projected, tint: projected < 0 ? .red : .purple) }
            if summaries.isEmpty { ContentUnavailableView("No salary pay periods", systemImage: "calendar.badge.exclamationmark", description: Text("Mark an income source as Salary and add a deposit to see paycheck planning.")) }
            else { List(summaries, id: \.period.depositDate) { summary in HStack { VStack(alignment: .leading) { Text(summary.period.status == .current ? "This paycheck" : "Paycheck of \(summary.period.depositDate)").fontWeight(summary.period.status == .current ? .bold : .regular); Text("\(summary.period.depositDate) – \(summary.period.endDate == "2099-12-31" ? "ongoing" : NativeDate.dayBefore(summary.period.endDate))").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text(NativeCurrency.string(summary.leftAfterPlansCents)).foregroundStyle(summary.leftAfterPlansCents < 0 ? .red : .primary).fontWeight(.semibold); Text("This paycheck: \(NativeCurrency.string(summary.remainingCents)) · \(NativeCurrency.string(summary.assignedExpenseCents)) assigned").font(.caption).foregroundStyle(.secondary) } } } }
        }.padding().task { load() }
    }
    private func load() { let today = NativeDate.string(Date()); do { summaries = try service.payPeriodSummaries(today: today); let active = summaries.first(where: { $0.period.status == .current }) ?? summaries.last; let end = active?.period.endDate == "2099-12-31" ? today : active.map { NativeDate.dayBefore($0.period.endDate) } ?? today; let balances = try service.balances(today: today, through: end); actual = balances.actual; projected = balances.projected } catch { summaries = [] } }
}

private struct InsightCard: View { let title: String; let amount: Int; let tint: Color; var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(NativeCurrency.string(amount)).font(.title2.bold()).foregroundStyle(tint) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12)) } }

private struct ItemRow: View {
    let item: Item
    var body: some View { HStack { Image(systemName: item.type == .deposit ? "arrow.down.circle.fill" : "arrow.up.circle").foregroundStyle(item.type == .deposit ? .green : .pink); VStack(alignment: .leading) { Text(item.name); Text(item.date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(String(format: "$%.2f", Double(item.amountCents) / 100)).monospacedDigit(); if item.status == .paid { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } } }
}

private struct EditorTarget: Identifiable { let id = UUID(); let item: Item? }

private struct TransactionEditor: View {
    let service: BudgetService
    let categories: [Category]
    let existing: Item?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var type: ItemType
    @State private var date: Date
    @State private var categoryId: Int64?
    @State private var note: String
    @State private var paid: Bool
    @State private var error: String?

    init(service: BudgetService, categories: [Category], existing: Item?, onSave: @escaping () -> Void) {
        self.service = service; self.categories = categories; self.existing = existing; self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _amount = State(initialValue: existing.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _type = State(initialValue: existing?.type ?? .bill)
        _date = State(initialValue: existing.flatMap { NativeDate.date($0.date) } ?? Date())
        _categoryId = State(initialValue: existing?.categoryId)
        _note = State(initialValue: existing?.note ?? "")
        _paid = State(initialValue: existing?.status == .paid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add transaction" : "Edit transaction").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $type) { Text("Bill").tag(ItemType.bill); Text("Purchase").tag(ItemType.purchase); Text("Deposit").tag(ItemType.deposit) }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Category", selection: $categoryId) { Text("None").tag(Int64?.none); ForEach(categories) { category in Text(category.name).tag(category.id) } }
                Toggle("Paid / received", isOn: $paid)
                TextField("Note", text: $note, axis: .vertical)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || NativeMoney.cents(amount) == nil) }
        }.padding(24).frame(width: 460)
    }

    private func save() {
        guard let cents = NativeMoney.cents(amount), cents > 0 else { error = "Enter an amount greater than zero."; return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let item = Item(id: existing?.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), amountCents: cents, type: type, date: NativeDate.string(date), categoryId: categoryId, note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note, priority: existing?.priority ?? 0, status: paid ? .paid : .planned, paidDate: paid ? (existing?.paidDate ?? NativeDate.string(Date())) : nil, ruleId: existing?.ruleId, isOverride: existing?.isOverride ?? false, deleted: existing?.deleted ?? false, assignmentOverride: existing?.assignmentOverride ?? false, assignedDepositItemId: existing?.assignedDepositItemId, assignmentNote: existing?.assignmentNote, movedFromDepositItemId: existing?.movedFromDepositItemId, movedFromDate: existing?.movedFromDate, createdAt: existing?.createdAt ?? timestamp, updatedAt: timestamp)
        do { _ = try service.saveItem(item); onSave(); dismiss() } catch { self.error = error.localizedDescription }
    }
}

private enum NativeDate { static func string(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }; static func date(_ value: String) -> Date? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: value) }; static func dayBefore(_ value: String) -> String { guard let date = date(value) else { return value }; return string(Calendar.current.date(byAdding: .day, value: -1, to: date)!) } }
private enum NativeMoney { static func cents(_ value: String) -> Int? { let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal; guard let amount = formatter.number(from: value)?.decimalValue else { return nil }; return NSDecimalNumber(decimal: amount * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: true, raiseOnUnderflow: true, raiseOnDivideByZero: true)).intValue } }
private enum NativeCurrency { static func string(_ cents: Int) -> String { let formatter = NumberFormatter(); formatter.numberStyle = .currency; return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00" } }

private struct SettingsScreen: View {
    let database: DatabaseCoordinator
    let service: BudgetService
    @State private var message: String?
    @State private var showingResetConfirmation = false
    var body: some View {
        Form {
            Section("Data") { LabeledContent("Database", value: BudgetCalendarPaths.database.path).textSelection(.enabled); LabeledContent("Schema", value: "v\(DatabaseCoordinator.supportedSchemaVersion)"); LabeledContent("Journal", value: "SQLite WAL"); Button("Copy backup now") { backup() } }
            Section("Export") { Button("Export transactions CSV") { exportCSV() }; Button("Import transactions CSV") { importCSV() }; Text("Imports add valid rows without replacing existing items. Recurring export rows become individual calendar entries.").font(.caption).foregroundStyle(.secondary) }
            Section("Compatibility") { Text("The native app reads and writes the same database as Budget Calendar 0.1.7. Close the other app before making changes.").foregroundStyle(.secondary) }
            Section("Delete all data") { Text("This permanently removes calendar items, rules, categories, settings, adjustments, and audit history, then restores the defaults.").foregroundStyle(.red); Button("Delete all data", role: .destructive) { showingResetConfirmation = true } }
            if let message { Section { Text(message).font(.caption) } }
        }.formStyle(.grouped).padding()
            .alert("Delete all Budget Calendar data?", isPresented: $showingResetConfirmation) { Button("Delete all data", role: .destructive) { reset() }; Button("Cancel", role: .cancel) {} } message: { Text("This cannot be undone. Create a backup first if you may need this data later.") }
    }
    private func exportCSV() { do { guard let url = NativeFilePanels.save(name: "budget-transactions.csv", type: .commaSeparatedText) else { return }; let categories = Dictionary(uniqueKeysWithValues: try service.categories().compactMap { category in category.id.map { id in (id, category) } }); let content = CSVService.export(items: try service.visibleItems(from: "0001-01-01", through: "9999-12-31"), categories: categories); try Data(("\u{FEFF}" + content).write(to: url, atomically: true, encoding: .utf8); message = "Exported CSV to \(url.lastPathComponent)." } catch { message = error.localizedDescription } }
    private func importCSV() { do { guard let url = NativeFilePanels.open(type: .commaSeparatedText) else { return }; let result = try service.importTransactionsCSV(String(decoding: Data(contentsOf: url), as: UTF8.self)); message = "Imported \(result.imported) transaction\(result.imported == 1 ? "" : "s"); skipped \(result.skipped)." } catch { message = error.localizedDescription } }
    private func backup() { do { guard let url = NativeFilePanels.save(name: "budget-backup.sqlite", type: UTType(filenameExtension: "sqlite") ?? .data) else { return }; try BackupService.copy(database: database.database, to: url, source: database.path); message = "Created backup at \(url.lastPathComponent)." } catch { message = error.localizedDescription } }
    private func reset() { do { try service.resetAllData(); message = "All data was deleted and defaults were restored." } catch { message = error.localizedDescription } }
}

private enum NativeFilePanels {
    static func save(name: String, type: UTType) -> URL? { let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]; return panel.runModal() == .OK ? panel.url : nil }
    static func open(type: UTType) -> URL? { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [type]; return panel.runModal() == .OK ? panel.url : nil }
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
