import Foundation

public struct DepositPeriod: Equatable, Sendable {
    public let depositDate: String; public let endDate: String; public let depositAmountCents: Int
    public let status: Status
    public enum Status: Sendable { case past, current, future }
}

public enum PlanningEngine {
    public static func deriveSalaryPeriods(_ deposits: [Item], salaryCategoryIDs: Set<Int64>, today: String) -> [DepositPeriod] {
        let salary = deposits.filter { !$0.deleted && $0.type == .deposit && $0.categoryId.map(salaryCategoryIDs.contains) == true }.sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: salary, by: \.date).map { ($0.key, $0.value.reduce(0) { $0 + $1.amountCents }) }.sorted { $0.0 < $1.0 }
        return grouped.enumerated().map { index, entry in
            let end = index + 1 < grouped.count ? grouped[index + 1].0 : "2099-12-31"
            let status: DepositPeriod.Status = today < entry.0 ? .future : today >= end ? .past : .current
            return DepositPeriod(depositDate: entry.0, endDate: end, depositAmountCents: entry.1, status: status)
        }
    }

    public static func coveringPeriod(date: String, periods: [DepositPeriod]) -> DepositPeriod? {
        periods.filter { $0.depositDate <= date }.max { $0.depositDate < $1.depositDate }
    }

    public static func actualBalance(items: [Item], startingBalanceCents: Int, adjustments: [BalanceAdjustment], asOf date: String) -> Int {
        var balance = startingBalanceCents
        for item in items where !item.deleted && item.date <= date {
            if item.status == .paid { balance += item.type == .deposit ? item.amountCents : -item.amountCents }
        }
        balance += adjustments.filter { $0.date <= date }.reduce(0) { $0 + $1.amountCents }
        return balance
    }

    public static func projectedBalance(items: [Item], startingBalanceCents: Int, adjustments: [BalanceAdjustment], today: String, through date: String) -> Int {
        var balance = actualBalance(items: items, startingBalanceCents: startingBalanceCents, adjustments: adjustments, asOf: today)
        for item in items where !item.deleted && item.date > today && item.date <= date {
            balance += item.type == .deposit ? item.amountCents : (item.status == .planned ? -item.amountCents : 0)
        }
        return balance
    }
}
