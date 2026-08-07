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
    @State private var daySheet: CalendarDayTarget?
    @State private var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    private let columns = Array(repeating: GridItem(.flexible(minimum: 84), spacing: 8), count: 7)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Calendar").font(.largeTitle.bold()); Spacer(); Button("Add transaction", systemImage: "plus") { editor = EditorTarget(item: nil, draftDate: Date()) }.buttonStyle(.borderedProminent) }
            HStack { Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }; Text(monthTitle).font(.title2.bold()).frame(minWidth: 180); Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }; Spacer(); Button("Today") { displayedMonth = monthStart(Date()); load() } }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekSymbols, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                ForEach(calendarDays, id: \.self) { day in CalendarDayCell(day: day, month: displayedMonth, items: items.filter { $0.date == NativeDate.string(day) }) { daySheet = CalendarDayTarget(date: day) } }
            }
        }.padding().task { load() }
            .sheet(item: $editor) { target in TransactionEditor(service: service, categories: categories, existing: target.item, initialDate: target.draftDate) { load() } }
            .sheet(item: $daySheet) { target in CalendarDaySheet(service: service, categories: categories, date: target.date) { load() } }
    }
    private var monthTitle: String { displayedMonth.formatted(.dateTime.month(.wide).year()) }
    private var weekSymbols: [String] { let symbols = Calendar.current.shortWeekdaySymbols; let first = Calendar.current.firstWeekday - 1; return Array(symbols[first...]) + Array(symbols[..<first]) }
    private var calendarDays: [Date] { let calendar = Calendar.current; let start = monthStart(displayedMonth); let leading = calendar.component(.weekday, from: start) - calendar.firstWeekday; let normalizedLeading = leading < 0 ? leading + 7 : leading; let first = calendar.date(byAdding: .day, value: -normalizedLeading, to: start)!; let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!; let ending = calendar.component(.weekday, from: monthEnd) - calendar.firstWeekday; let normalizedEnding = ending < 0 ? ending + 7 : ending; let trailing = 6 - normalizedEnding; return (0..<(normalizedLeading + calendar.component(.day, from: monthEnd) + trailing)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) } }
    private func monthStart(_ date: Date) -> Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))! }
    private func moveMonth(_ amount: Int) { displayedMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth)!; load() }
    private func load() { let calendar = Calendar.current; let start = monthStart(displayedMonth); let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!; let materializeStart = calendar.date(byAdding: .year, value: -1, to: start)!; let materializeEnd = calendar.date(byAdding: .year, value: 1, to: end)!; for id in ((try? service.rules()) ?? []).compactMap(\.id) { _ = try? service.materialize(ruleId: id, from: NativeDate.string(materializeStart), through: NativeDate.string(materializeEnd)) }; items = (try? service.visibleItems(from: NativeDate.string(start), through: NativeDate.string(end))) ?? []; categories = (try? service.categories()) ?? [] }
}

private struct CalendarDayTarget: Identifiable { let date: Date; var id: String { NativeDate.string(date) } }

private struct CalendarDayCell: View {
    let day: Date; let month: Date; let items: [Item]; let open: () -> Void
    var body: some View { Button(action: open) { VStack(alignment: .leading, spacing: 4) { HStack { Text(day.formatted(.dateTime.day())).fontWeight(Calendar.current.isDateInToday(day) ? .bold : .regular).foregroundStyle(isInMonth ? .primary : .tertiary); Spacer(); if !items.isEmpty { Text("\(items.count)").font(.caption2).foregroundStyle(.secondary) } }; ForEach(items.prefix(2)) { item in Text("\(item.type == .deposit ? "+" : "−") \(item.name)").font(.caption2).lineLimit(1).foregroundStyle(item.type == .deposit ? .green : .primary) }; if items.count > 2 { Text("+ \(items.count - 2) more").font(.caption2).foregroundStyle(.secondary) }; Spacer(minLength: 0) }.padding(7).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading).background(Calendar.current.isDateInToday(day) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(isInMonth ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(!isInMonth) }
    private var isInMonth: Bool { Calendar.current.isDate(day, equalTo: month, toGranularity: .month) }
}

private struct CalendarDaySheet: View {
    let service: BudgetService; let categories: [Category]; let date: Date; let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []; @State private var editor: EditorTarget?
    var body: some View { VStack(alignment: .leading, spacing: 16) { HStack { VStack(alignment: .leading) { Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.title2.bold()); Text("Transactions for this day").foregroundStyle(.secondary) }; Spacer(); Button("Add", systemImage: "plus") { editor = EditorTarget(item: nil, draftDate: date) }.buttonStyle(.borderedProminent); Button("Done") { dismiss() } }; if items.isEmpty { ContentUnavailableView("Nothing scheduled", systemImage: "calendar", description: Text("Add a transaction for this day.")) } else { List(items) { item in Button { editor = EditorTarget(item: item) } label: { ItemRow(item: item) }.buttonStyle(.plain).contextMenu { Button(item.status == .paid ? "Mark planned" : "Mark paid") { try? service.setPaid(id: item.id!, paid: item.status != .paid); load(); onChanged() } } } } }.padding(24).frame(minWidth: 460, minHeight: 360).task { load() }.sheet(item: $editor) { target in TransactionEditor(service: service, categories: categories, existing: target.item, initialDate: target.draftDate) { load(); onChanged() } } }
    private func load() { let value = NativeDate.string(date); items = (try? service.visibleItems(from: value, through: value)) ?? [] }
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
    @State private var detailTarget: PayPeriodDetailTarget?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Insights").font(.largeTitle.bold())
            HStack(spacing: 14) { InsightCard(title: "Actual balance", amount: actual, tint: .green); InsightCard(title: "Projected balance", amount: projected, tint: projected < 0 ? .red : .purple) }
            if summaries.isEmpty { ContentUnavailableView("No salary pay periods", systemImage: "calendar.badge.exclamationmark", description: Text("Mark an income source as Salary and add a deposit to see paycheck planning.")) }
            else { List(summaries, id: \.period.depositDate) { summary in Button { detailTarget = PayPeriodDetailTarget(depositDate: summary.period.depositDate) } label: { HStack { VStack(alignment: .leading) { Text(summary.period.status == .current ? "This paycheck" : "Paycheck of \(summary.period.depositDate)").fontWeight(summary.period.status == .current ? .bold : .regular); Text("\(summary.period.depositDate) – \(summary.period.endDate == "2099-12-31" ? "ongoing" : NativeDate.dayBefore(summary.period.endDate))").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text(NativeCurrency.string(summary.leftAfterPlansCents)).foregroundStyle(summary.leftAfterPlansCents < 0 ? .red : .primary).fontWeight(.semibold); Text("This paycheck: \(NativeCurrency.string(summary.remainingCents)) · \(NativeCurrency.string(summary.assignedExpenseCents)) assigned").font(.caption).foregroundStyle(.secondary) }; Image(systemName: "chevron.right").foregroundStyle(.tertiary) } }.buttonStyle(.plain) } }
        }.padding().task { load() }
            .sheet(item: $detailTarget) { target in PayPeriodDetailScreen(service: service, depositDate: target.depositDate) { load() } }
    }
    private func load() { let today = NativeDate.string(Date()); do { summaries = try service.payPeriodSummaries(today: today); let active = summaries.first(where: { $0.period.status == .current }) ?? summaries.last; let end = active?.period.endDate == "2099-12-31" ? today : active.map { NativeDate.dayBefore($0.period.endDate) } ?? today; let balances = try service.balances(today: today, through: end); actual = balances.actual; projected = balances.projected } catch { summaries = [] } }
}

private struct PayPeriodDetailTarget: Identifiable { let depositDate: String; var id: String { depositDate } }

private struct PayPeriodDetailScreen: View {
    let service: BudgetService; let depositDate: String; let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detail: PayPeriodDetail?
    @State private var editingItem: Item?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading) { Text("Paycheck details").font(.title2.bold()); Text(periodLabel).foregroundStyle(.secondary) }; Spacer(); Button("Done") { dismiss() } }
            if let detail {
                HStack(spacing: 12) { InsightCard(title: "Paycheck", amount: detail.summary.period.depositAmountCents, tint: .green); InsightCard(title: "Assigned", amount: detail.summary.assignedExpenseCents, tint: .pink); InsightCard(title: "Available after plans", amount: detail.summary.leftAfterPlansCents, tint: detail.summary.leftAfterPlansCents < 0 ? .red : .purple) }
                List {
                    Section("Salary deposits") { ForEach(detail.salaryDeposits) { ItemRow(item: $0) } }
                    if !detail.supplementalIncome.isEmpty { Section("Other income") { ForEach(detail.supplementalIncome) { ItemRow(item: $0) } } }
                    Section("Bills and purchases") {
                        if detail.assignedExpenses.isEmpty { Text("No bills or purchases are assigned to this paycheck.").foregroundStyle(.secondary) }
                        ForEach(detail.assignedExpenses) { item in Button { editingItem = item } label: { HStack { ItemRow(item: item); Image(systemName: item.assignmentOverride ? "arrow.left.arrow.right.circle" : "calendar").foregroundStyle(.secondary) } }.buttonStyle(.plain) }
                    }
                    if !detail.movedAwayExpenses.isEmpty { Section("Moved or unassigned") { ForEach(detail.movedAwayExpenses) { item in Button { editingItem = item } label: { HStack { ItemRow(item: item); Text(item.assignedDepositItemId == nil ? "Unassigned" : "Moved").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain) } } }
                }
            } else if let error { ContentUnavailableView("Unable to load paycheck", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView("Loading paycheck…") }
        }.padding(24).frame(minWidth: 620, minHeight: 500).task { load() }
            .sheet(item: $editingItem) { item in PaycheckAssignmentEditor(service: service, item: item) { load(); onChanged() } }
    }
    private var periodLabel: String { guard let period = detail?.summary.period else { return depositDate }; return period.endDate == "2099-12-31" ? "From \(period.depositDate) onward" : "\(period.depositDate) – \(NativeDate.dayBefore(period.endDate))" }
    private func load() { do { detail = try service.payPeriodDetail(depositDate: depositDate, today: NativeDate.string(Date())); error = nil } catch { self.error = error.localizedDescription } }
}

private struct InsightCard: View { let title: String; let amount: Int; let tint: Color; var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(NativeCurrency.string(amount)).font(.title2.bold()).foregroundStyle(tint) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12)) } }

private struct ItemRow: View {
    let item: Item
    var body: some View { HStack { Image(systemName: item.type == .deposit ? "arrow.down.circle.fill" : "arrow.up.circle").foregroundStyle(item.type == .deposit ? .green : .pink); VStack(alignment: .leading) { Text(item.name); Text(item.date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(String(format: "$%.2f", Double(item.amountCents) / 100)).monospacedDigit(); if item.status == .paid { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } } }
}

private struct EditorTarget: Identifiable { let id = UUID(); let item: Item?; let draftDate: Date?; init(item: Item?, draftDate: Date? = nil) { self.item = item; self.draftDate = draftDate } }
private enum ScheduleChoice: String, CaseIterable, Identifiable { case none, weekly, biweekly, monthly, monthlyNth; var id: String { rawValue }; var label: String { switch self { case .none: "Does not repeat"; case .weekly: "Every week"; case .biweekly: "Every 2 weeks"; case .monthly: "Every month on this date"; case .monthlyNth: "Every month on this weekday" } } }
private enum ScopeChoice: String, CaseIterable, Identifiable { case onlyThis, thisAndFuture, all; var id: String { rawValue }; var label: String { switch self { case .onlyThis: "Only this occurrence"; case .thisAndFuture: "This and future occurrences"; case .all: "Every occurrence" } } }

private struct TransactionEditor: View {
    let service: BudgetService
    let categories: [Category]
    let existing: Item?
    let initialDate: Date?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var type: ItemType
    @State private var date: Date
    @State private var categoryId: Int64?
    @State private var note: String
    @State private var paid: Bool
    @State private var schedule: ScheduleChoice
    @State private var scope: ScopeChoice = .onlyThis
    @State private var showingDeleteConfirmation = false
    @State private var showingAssignmentEditor = false
    @State private var error: String?

    init(service: BudgetService, categories: [Category], existing: Item?, initialDate: Date? = nil, onSave: @escaping () -> Void) {
        self.service = service; self.categories = categories; self.existing = existing; self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _amount = State(initialValue: existing.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _type = State(initialValue: existing?.type ?? .bill)
        self.initialDate = initialDate
        _date = State(initialValue: existing.flatMap { NativeDate.date($0.date) } ?? initialDate ?? Date())
        _categoryId = State(initialValue: existing?.categoryId)
        _note = State(initialValue: existing?.note ?? "")
        _paid = State(initialValue: existing?.status == .paid)
        _schedule = State(initialValue: .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add transaction" : "Edit transaction").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $type) { Text("Bill").tag(ItemType.bill); Text("Purchase").tag(ItemType.purchase); Text("Deposit").tag(ItemType.deposit) }
                DatePicker("Date", selection: $date, displayedComponents: .date).disabled(isRecurring && scope != .onlyThis)
                Picker("Category", selection: $categoryId) { Text("None").tag(Int64?.none); ForEach(categories) { category in Text(category.name).tag(category.id) } }
                Toggle("Paid / received", isOn: $paid)
                if existing == nil { Picker("Repeat", selection: $schedule) { ForEach(ScheduleChoice.allCases) { Text($0.label).tag($0) } } }
                else if isRecurring {
                    Picker("Apply changes", selection: $scope) { ForEach(ScopeChoice.allCases) { Text($0.label).tag($0) } }
                    if scope != .onlyThis { Text("The repeating date pattern stays unchanged when updating a series.").font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Note", text: $note, axis: .vertical)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                if existing != nil { Button("Delete", role: .destructive) { showingDeleteConfirmation = true } }
                if let existing, existing.type != .deposit { Button("Assign paycheck") { showingAssignmentEditor = true } }
                Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || NativeMoney.cents(amount) == nil)
            }
        }.padding(24).frame(width: 460)
            .alert(deleteTitle, isPresented: $showingDeleteConfirmation) { Button("Delete", role: .destructive) { delete() }; Button("Cancel", role: .cancel) {} } message: { Text(deleteMessage) }
            .sheet(isPresented: $showingAssignmentEditor) { if let existing { PaycheckAssignmentEditor(service: service, item: existing) { onSave() } } }
    }

    private var isRecurring: Bool { existing?.ruleId != nil }
    private var occurrenceScope: OccurrenceScope { switch scope { case .onlyThis: .onlyThis; case .thisAndFuture: .thisAndFuture; case .all: .all } }
    private var deleteTitle: String { isRecurring ? "Delete \(scope.label.lowercased())?" : "Delete transaction?" }
    private var deleteMessage: String { isRecurring ? "This affects \(scope.label.lowercased())." : "This cannot be undone." }

    private func save() {
        guard let cents = NativeMoney.cents(amount), cents > 0 else { error = "Enter an amount greater than zero."; return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let item = Item(id: existing?.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), amountCents: cents, type: type, date: NativeDate.string(date), categoryId: categoryId, note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note, priority: existing?.priority ?? 0, status: paid ? .paid : .planned, paidDate: paid ? (existing?.paidDate ?? NativeDate.string(Date())) : nil, ruleId: existing?.ruleId, isOverride: existing?.isOverride ?? false, deleted: existing?.deleted ?? false, assignmentOverride: existing?.assignmentOverride ?? false, assignedDepositItemId: existing?.assignedDepositItemId, assignmentNote: existing?.assignmentNote, movedFromDepositItemId: existing?.movedFromDepositItemId, movedFromDate: existing?.movedFromDate, createdAt: existing?.createdAt ?? timestamp, updatedAt: timestamp)
        do {
            if let existing, existing.ruleId != nil {
                _ = try service.editOccurrence(id: existing.id!, scope: occurrenceScope, changes: ItemChanges(name: item.name, amountCents: item.amountCents, type: item.type, date: scope == .onlyThis ? item.date : nil, categoryId: item.categoryId, setCategoryId: true, note: item.note, setNote: true, priority: item.priority), paid: scope == .thisAndFuture ? item.status == .paid : nil, paidDate: item.paidDate)
                if scope != .thisAndFuture { try service.setPaid(id: existing.id!, paid: item.status == .paid, paidDate: item.paidDate) }
            } else if schedule == .none { _ = try service.saveItem(item) }
            else {
                let calendar = Calendar.current
                let kind: RecurrenceKind = schedule == .weekly ? .weekly : schedule == .biweekly ? .biweekly : schedule == .monthly ? .monthlyDate : .monthlyNth
                let weekday = calendar.component(.weekday, from: date) - 1
                let day = calendar.component(.day, from: date)
                let days = calendar.range(of: .day, in: .month, for: date)!.count
                let nth = day + 7 > days ? -1 : ((day - 1) / 7) + 1
                let rule = RecurringRule(kind: kind, anchorDate: item.date, weekday: (schedule == .weekly || schedule == .biweekly || schedule == .monthlyNth) ? weekday : nil, dayOfMonth: schedule == .monthly ? day : nil, nth: schedule == .monthlyNth ? nth : nil)
                _ = try service.createRecurringItem(item, rule: rule, materializeThrough: NativeDate.addingYears(2, to: date))
            }
            onSave(); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() {
        guard let existing, let id = existing.id else { return }
        do { _ = try service.deleteOccurrence(id: id, scope: isRecurring ? occurrenceScope : .all); onSave(); dismiss() }
        catch { error = error.localizedDescription }
    }
}

private struct PaycheckAssignmentEditor: View {
    let service: BudgetService; let item: Item; let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deposits: [Item] = []; @State private var selectedDepositID: Int64?; @State private var targetDate = Date(); @State private var preserveExistingDateOnInitialSelection = true; @State private var unassign = false; @State private var note = ""; @State private var error: String?
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Assign paycheck").font(.title2.bold()); Text(item.name).foregroundStyle(.secondary); Form { Toggle("Leave unassigned", isOn: $unassign); if !unassign { Picker("Paycheck", selection: $selectedDepositID) { Text("Choose a salary deposit").tag(Int64?.none); ForEach(deposits) { deposit in Text("\(deposit.date) · \(NativeCurrency.string(deposit.amountCents))").tag(deposit.id) } }.onChange(of: selectedDepositID) { _ in if preserveExistingDateOnInitialSelection { preserveExistingDateOnInitialSelection = false; setInitialTargetDate() } else { resetTargetDate() } }; DatePicker("New date in this pay period", selection: $targetDate, in: permittedDates, displayedComponents: .date); Text(payPeriodHint).font(.caption).foregroundStyle(.secondary) }; TextField("Reason", text: $note, axis: .vertical) }; if let error { Text(error).font(.caption).foregroundStyle(.red) }; HStack { Spacer(); Button("Cancel") { dismiss() }; Button(unassign ? "Unassign" : "Move") { save() }.buttonStyle(.borderedProminent).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!unassign && selectedDepositID == nil)) } }.padding(24).frame(width: 430).task { load() } }
    private var selectedDeposit: Item? { deposits.first { $0.id == selectedDepositID } }
    private var nextDeposit: Item? { guard let selectedDeposit else { return nil }; return deposits.first { $0.date > selectedDeposit.date } }
    private var permittedDates: ClosedRange<Date> { let start = selectedDeposit.flatMap { NativeDate.date($0.date) } ?? Date.distantPast; let end = nextDeposit.flatMap { NativeDate.date(NativeDate.dayBefore($0.date)) } ?? Date.distantFuture; return start...end }
    private var payPeriodHint: String { guard let selectedDeposit else { return "Choose a salary deposit to set a valid date range." }; return nextDeposit.map { "Date must be from \(selectedDeposit.date) through \(NativeDate.dayBefore($0.date))." } ?? "Date must be on or after \(selectedDeposit.date)." }
    private func load() { do { deposits = try service.salaryDepositItems(); selectedDepositID = item.assignedDepositItemId; if selectedDepositID == nil { selectedDepositID = deposits.last(where: { $0.date <= item.date })?.id }; setInitialTargetDate() } catch { self.error = error.localizedDescription } }
    private func setInitialTargetDate() { if let existingDate = NativeDate.date(item.date), permittedDates.contains(existingDate) { targetDate = existingDate } else { resetTargetDate() } }
    private func resetTargetDate() { if let selectedDeposit, let date = NativeDate.date(selectedDeposit.date) { targetDate = date } }
    private func save() { do { if unassign { try service.unassignFromPaycheck(itemID: item.id!, note: note) } else if let selectedDepositID { try service.assignToPaycheck(itemID: item.id!, depositItemID: selectedDepositID, note: note, targetDate: NativeDate.string(targetDate)) }; onSave(); dismiss() } catch { self.error = error.localizedDescription } }
}

private enum NativeDate { static func string(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }; static func date(_ value: String) -> Date? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: value) }; static func dayBefore(_ value: String) -> String { guard let date = date(value) else { return value }; return string(Calendar.current.date(byAdding: .day, value: -1, to: date)!) }; static func addingYears(_ years: Int, to date: Date) -> String { string(Calendar.current.date(byAdding: .year, value: years, to: date)!) } }
private enum NativeMoney { static func cents(_ value: String) -> Int? { let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal; guard let amount = formatter.number(from: value)?.decimalValue else { return nil }; return NSDecimalNumber(decimal: amount * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: true, raiseOnUnderflow: true, raiseOnDivideByZero: true)).intValue }; static func string(cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) } }
private enum NativeCurrency { static func string(_ cents: Int) -> String { let formatter = NumberFormatter(); formatter.numberStyle = .currency; return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00" } }

private struct SettingsScreen: View {
    let database: DatabaseCoordinator
    let service: BudgetService
    @State private var message: String?
    @State private var showingResetConfirmation = false
    @State private var categories: [Category] = []
    @State private var categoryEditor: CategoryEditorTarget?
    @State private var categoryToDelete: Category?
    @State private var includeOtherIncome = true
    @State private var adjustments: [BalanceAdjustment] = []
    @State private var startingBalanceCents = 0
    @State private var showingAdjustmentEditor = false
    @State private var adjustmentToDelete: BalanceAdjustment?
    var body: some View {
        Form {
            Section("Data") { LabeledContent("Database", value: BudgetCalendarPaths.database.path).textSelection(.enabled); LabeledContent("Schema", value: "v\(DatabaseCoordinator.supportedSchemaVersion)"); LabeledContent("Journal", value: "SQLite WAL"); Button("Copy backup now") { backup() } }
            Section("Balance") {
                LabeledContent("Starting balance", value: NativeCurrency.string(startingBalanceCents))
                Text("Balance after adjustments: \(NativeCurrency.string(startingBalanceCents + adjustments.reduce(0) { $0 + $1.amountCents }))").font(.caption).foregroundStyle(.secondary)
                Button("Adjust balance", systemImage: "plusminus") { showingAdjustmentEditor = true }
                ForEach(adjustments.reversed()) { adjustment in HStack { VStack(alignment: .leading) { Text("\(adjustment.amountCents >= 0 ? "+" : "")\(NativeCurrency.string(adjustment.amountCents))").foregroundStyle(adjustment.amountCents >= 0 ? .green : .red); Text("\(adjustment.date) · \(adjustment.note ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Remove", role: .destructive) { adjustmentToDelete = adjustment } } }
            }
            Section("Income sources") {
                Text("Salary sources set paycheck boundaries. Other income can add to the available balance without changing those dates.").font(.caption).foregroundStyle(.secondary)
                ForEach(categories.filter { $0.kind == "deposit" }) { category in CategoryRow(category: category, showIncomeRole: true, canDelete: !category.isBuiltin) { categoryEditor = CategoryEditorTarget(category: category) } onDelete: { categoryToDelete = category } }
                Button("Add income source", systemImage: "plus") { categoryEditor = CategoryEditorTarget(category: nil, isIncomeSource: true) }
                Toggle("Include Other Income in available balance", isOn: Binding(get: { includeOtherIncome }, set: { setOtherIncome($0) }))
            }
            Section("Expense categories") {
                Text("Removing a category keeps its transactions and makes them Uncategorized.").font(.caption).foregroundStyle(.secondary)
                ForEach(categories.filter { $0.kind != "deposit" }) { category in CategoryRow(category: category, showIncomeRole: false, canDelete: true) { categoryEditor = CategoryEditorTarget(category: category) } onDelete: { categoryToDelete = category } }
                Button("Add expense category", systemImage: "plus") { categoryEditor = CategoryEditorTarget(category: nil, isIncomeSource: false) }
            }
            Section("Export") { Button("Export transactions CSV") { exportCSV() }; Button("Import transactions CSV") { importCSV() }; Text("Imports add valid rows without replacing existing items. Recurring export rows become individual calendar entries.").font(.caption).foregroundStyle(.secondary) }
            Section("Compatibility") { Text("The native app reads and writes the same database as Budget Calendar 0.1.7. Close the other app before making changes.").foregroundStyle(.secondary) }
            Section("Delete all data") { Text("This permanently removes calendar items, rules, categories, settings, adjustments, and audit history, then restores the defaults.").foregroundStyle(.red); Button("Delete all data", role: .destructive) { showingResetConfirmation = true } }
            if let message { Section { Text(message).font(.caption) } }
        }.formStyle(.grouped).padding().task { loadSettings() }
            .sheet(item: $categoryEditor) { target in CategoryEditor(service: service, target: target) { loadSettings() } }
            .sheet(isPresented: $showingAdjustmentEditor) { AdjustmentEditor(service: service) { loadSettings() } }
            .alert("Delete all Budget Calendar data?", isPresented: $showingResetConfirmation) { Button("Delete all data", role: .destructive) { reset() }; Button("Cancel", role: .cancel) {} } message: { Text("This cannot be undone. Create a backup first if you may need this data later.") }
            .alert("Remove category?", isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } })) { Button("Remove", role: .destructive) { deleteCategory() }; Button("Cancel", role: .cancel) { categoryToDelete = nil } } message: { Text("Transactions in \(categoryToDelete?.name ?? "this category") will become Uncategorized.") }
            .alert("Delete balance adjustment?", isPresented: Binding(get: { adjustmentToDelete != nil }, set: { if !$0 { adjustmentToDelete = nil } })) { Button("Delete", role: .destructive) { deleteAdjustment() }; Button("Cancel", role: .cancel) { adjustmentToDelete = nil } } message: { Text("This will recalculate the balance.") }
    }
    private func loadSettings() { do { categories = try service.categories(); adjustments = try service.adjustments(); includeOtherIncome = try service.setting("include_other_income_in_pay_periods") != "false"; startingBalanceCents = Int(try service.setting("starting_balance_cents") ?? "0") ?? 0 } catch { message = error.localizedDescription } }
    private func setOtherIncome(_ value: Bool) { includeOtherIncome = value; do { try service.setSetting("include_other_income_in_pay_periods", value: value ? "true" : "false") } catch { message = error.localizedDescription } }
    private func deleteAdjustment() { guard let adjustment = adjustmentToDelete, let id = adjustment.id else { return }; do { try service.deleteAdjustment(id: id); adjustmentToDelete = nil; loadSettings() } catch { message = error.localizedDescription } }
    private func deleteCategory() { guard let category = categoryToDelete, let id = category.id else { return }; do { try service.deleteCategory(id: id); categoryToDelete = nil; loadSettings(); message = "Removed \(category.name)." } catch { message = error.localizedDescription } }
    private func exportCSV() {
        do {
            guard let url = NativeFilePanels.save(name: "budget-transactions.csv", type: .commaSeparatedText) else { return }
            let categories = Dictionary(uniqueKeysWithValues: try service.categories().compactMap { category in category.id.map { id in (id, category) } })
            let content = CSVService.export(items: try service.visibleItems(from: "0001-01-01", through: "9999-12-31"), categories: categories)
            try Data(("\u{FEFF}" + content).utf8).write(to: url, options: .atomic)
            message = "Exported CSV to \(url.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }
    private func importCSV() { do { guard let url = NativeFilePanels.open(type: .commaSeparatedText) else { return }; let result = try service.importTransactionsCSV(String(decoding: Data(contentsOf: url), as: UTF8.self)); message = "Imported \(result.imported) transaction\(result.imported == 1 ? "" : "s"); skipped \(result.skipped)." } catch { message = error.localizedDescription } }
    private func backup() { do { guard let url = NativeFilePanels.save(name: "budget-backup.sqlite", type: UTType(filenameExtension: "sqlite") ?? .data) else { return }; try BackupService.copy(database: database.database, to: url, source: database.path); message = "Created backup at \(url.lastPathComponent)." } catch { message = error.localizedDescription } }
    private func reset() { do { try service.resetAllData(); loadSettings(); message = "All data was deleted and defaults were restored." } catch { message = error.localizedDescription } }
}

private struct CategoryEditorTarget: Identifiable { let id = UUID(); let category: Category?; let isIncomeSource: Bool; init(category: Category?, isIncomeSource: Bool? = nil) { self.category = category; self.isIncomeSource = isIncomeSource ?? category?.kind == "deposit" } }

private struct CategoryRow: View {
    let category: Category; let showIncomeRole: Bool; let canDelete: Bool; let onEdit: () -> Void; let onDelete: () -> Void
    var body: some View { HStack { Circle().fill(Color(hex: category.color)).frame(width: 10, height: 10); VStack(alignment: .leading) { Text(category.name); Text(showIncomeRole ? (category.incomeType == "salary" ? "Salary — starts pay periods" : "Other income") : (category.kind == "both" ? "Bills & spending" : category.kind)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Edit", action: onEdit); if canDelete { Button("Remove", role: .destructive, action: onDelete) } } }
}

private struct CategoryEditor: View {
    let service: BudgetService; let target: CategoryEditorTarget; let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var color: String; @State private var incomeType: String; @State private var error: String?
    init(service: BudgetService, target: CategoryEditorTarget, onSave: @escaping () -> Void) { self.service = service; self.target = target; self.onSave = onSave; _name = State(initialValue: target.category?.name ?? ""); _color = State(initialValue: target.category?.color ?? (target.isIncomeSource ? "#3aa97c" : "#8b83a3")); _incomeType = State(initialValue: target.category?.incomeType ?? "other") }
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text(target.category == nil ? (target.isIncomeSource ? "Add income source" : "Add expense category") : "Edit \(target.isIncomeSource ? "income source" : "expense category")").font(.title2.bold()); Form { TextField("Name", text: $name); TextField("Color", text: $color); if target.isIncomeSource { Picker("Role", selection: $incomeType) { Text("Salary").tag("salary"); Text("Other income").tag("other") } } }; if let error { Text(error).font(.caption).foregroundStyle(.red) }; HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(24).frame(width: 400) }
    private func save() { do { let existing = target.category; let category = Category(id: existing?.id, name: name, color: color, kind: target.isIncomeSource ? "deposit" : existing?.kind ?? "both", isBuiltin: existing?.isBuiltin ?? false, sortOrder: existing?.sortOrder ?? 0, incomeType: target.isIncomeSource ? incomeType : nil); _ = try service.saveCategory(category); onSave(); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct AdjustmentEditor: View {
    let service: BudgetService; let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""; @State private var date = Date(); @State private var note = ""; @State private var error: String?
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Adjust balance").font(.title2.bold()); Text("Use a positive amount to add funds or a negative amount to subtract them.").font(.caption).foregroundStyle(.secondary); Form { TextField("Amount", text: $amount); DatePicker("Date", selection: $date, displayedComponents: .date); TextField("Note", text: $note) }; if let error { Text(error).font(.caption).foregroundStyle(.red) }; HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent) } }.padding(24).frame(width: 400) }
    private func save() { guard let cents = NativeMoney.cents(amount), cents != 0 else { error = "Enter a non-zero amount."; return }; do { _ = try service.createAdjustment(amountCents: cents, date: NativeDate.string(date), note: note); onSave(); dismiss() } catch { self.error = error.localizedDescription } }
}

private extension Color { init(hex: String) { let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x8b83a3; self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255) } }

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
