import Foundation

public struct GeneratedOccurrence: Equatable, Sendable { public let date: String; public init(date: String) { self.date = date } }

public enum RecurrenceEngine {
    public static func occurrences(for rule: RecurringRule, from start: String, through end: String, calendar: Calendar = .current) -> [GeneratedOccurrence] {
        guard let anchor = date(rule.anchorDate, calendar: calendar), let lower = date(start, calendar: calendar), let upper = date(end, calendar: calendar) else { return [] }
        let effectiveEnd = min(upper, rule.endDate.flatMap { date($0, calendar: calendar) } ?? upper)
        var result: [GeneratedOccurrence] = []
        switch rule.kind {
        case .weekly:
            var current = anchor
            let weekday = rule.weekday ?? calendar.component(.weekday, from: anchor) - 1
            while calendar.component(.weekday, from: current) - 1 != weekday { current = calendar.date(byAdding: .day, value: 1, to: current)! }
            while current <= effectiveEnd { if current >= lower { result.append(.init(date: string(current, calendar: calendar))) }; current = calendar.date(byAdding: .day, value: 7, to: current)! }
        case .biweekly:
            var current = anchor
            let interval = rule.dayOfMonth ?? 14
            while current <= effectiveEnd { if current >= lower { result.append(.init(date: string(current, calendar: calendar))) }; current = calendar.date(byAdding: .day, value: interval, to: current)! }
        case .monthlyDate:
            var current = anchor
            let day = rule.dayOfMonth ?? calendar.component(.day, from: anchor)
            while current <= effectiveEnd {
                let comps = calendar.dateComponents([.year, .month], from: current)
                let monthEnd = calendar.range(of: .day, in: .month, for: current)!.count
                let candidate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: min(day, monthEnd)))!
                if candidate >= lower && candidate <= effectiveEnd { result.append(.init(date: string(candidate, calendar: calendar))) }
                current = calendar.date(byAdding: .month, value: 1, to: current)!
            }
        case .monthlyNth:
            var current = anchor
            while current <= effectiveEnd {
                let components = calendar.dateComponents([.year, .month], from: current)
                let weekday = rule.weekday ?? calendar.component(.weekday, from: anchor) - 1
                let nth = rule.nth ?? 1
                if let candidate = nthWeekday(year: components.year!, month: components.month!, weekday: weekday, nth: nth, calendar: calendar), candidate >= lower && candidate <= effectiveEnd { result.append(.init(date: string(candidate, calendar: calendar))) }
                current = calendar.date(byAdding: .month, value: 1, to: current)!
            }
        }
        return result
    }
    private static func date(_ value: String, calendar: Calendar) -> Date? { let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: value) }
    private static func string(_ date: Date, calendar: Calendar) -> String { let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private static func nthWeekday(year: Int, month: Int, weekday: Int, nth: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)), let days = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let matches = days.compactMap { day -> Date? in let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)); return candidate.flatMap { calendar.component(.weekday, from: $0) - 1 == weekday ? $0 : nil } }
        let index = nth > 0 ? nth - 1 : matches.count + nth
        return matches.indices.contains(index) ? matches[index] : nil
    }
}
