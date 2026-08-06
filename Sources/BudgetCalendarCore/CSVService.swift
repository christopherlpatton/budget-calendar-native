import Foundation

public enum CSVService {
    public static func export(items: [Item], categories: [Int64: Category] = [:]) -> String {
        let header = ["Type", "Name", "Amount", "Date", "Category", "Note", "Priority", "Status", "Paid Date"].map(escape).joined(separator: ",")
        let rows = items.filter { !$0.deleted }.map { item in
            [item.type.rawValue, item.name, String(format: "%.2f", Double(item.amountCents) / 100), item.date,
             item.categoryId.flatMap { categories[$0]?.name } ?? "", item.note ?? "", String(item.priority), item.status.rawValue, item.paidDate ?? ""].map(escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func parse(_ content: String) throws -> [[String: String]] {
        let rows = try parseRows(content)
        guard let header = rows.first else { return [] }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard normalized.contains("type"), normalized.contains("name"), normalized.contains("amount"), normalized.contains("date") else { throw CSVError.invalidHeader }
        return rows.dropFirst().filter { $0.contains(where: { !$0.isEmpty }) }.map { row in
            Dictionary(uniqueKeysWithValues: normalized.enumerated().map { ($0.element, $0.offset < row.count ? row[$0.offset] : "") })
        }
    }

    public enum CSVError: Error { case invalidHeader, unfinishedQuote }
    private static func escape(_ value: String) -> String { value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value }
    private static func parseRows(_ content: String) throws -> [[String]] {
        var rows: [[String]] = [[]], field = "", quoted = false, index = content.startIndex
        while index < content.endIndex {
            let c = content[index]; let next = content.index(after: index)
            if c == "\"" {
                if quoted && next < content.endIndex && content[next] == "\"" { field.append("\""); index = content.index(after: next); continue }
                quoted.toggle()
            } else if c == "," && !quoted { rows[rows.count - 1].append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted { rows[rows.count - 1].append(field); field = ""; if c == "\r" && next < content.endIndex && content[next] == "\n" { index = next }; rows.append([]) }
            else { field.append(c) }
            index = index == content.index(before: content.endIndex) ? content.endIndex : next
        }
        if quoted { throw CSVError.unfinishedQuote }
        if !field.isEmpty || rows.last?.isEmpty == false { rows[rows.count - 1].append(field) }
        if rows.last?.isEmpty == true { rows.removeLast() }
        return rows
    }
}
