import Foundation

/// The custom label of each week, keyed by the week's Monday
/// (`week-labels.csv`). Weeks without a label show their ISO week number.
public struct WeekLabels: Equatable {
    public private(set) var labels: [LocalDate: String] = [:]

    public init() {}

    public init(_ labels: [LocalDate: String]) {
        for (week, label) in labels { self[week] = label }
    }

    /// The label of the week containing `day`. Setting an empty label removes it.
    public subscript(day: LocalDate) -> String? {
        get { labels[day.monday] }
        set {
            let text = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            labels[day.monday] = text.isEmpty ? nil : WeekLabels.oneLine(text)
        }
    }

    public var isEmpty: Bool { labels.isEmpty }
    public var count: Int { labels.count }

    /// Every labelled week, earliest first.
    public var sorted: [WeekLabelEntry] {
        labels.sorted { $0.key < $1.key }.map { WeekLabelEntry(week: $0.key, label: $0.value) }
    }

    /// What the header shows for the week containing `day`: its label, or
    /// `W41` when it has none and `isoFallback` is on.
    public func display(for day: LocalDate, isoFallback: Bool) -> (text: String, isCustom: Bool) {
        if let label = self[day] { return (label, true) }
        return (isoFallback ? "W\(day.isoWeek.week)" : "", false)
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    // MARK: File

    public static let header = ["week", "label"]

    /// Reads `week-labels.csv`. Rows whose week is not a date are reported
    /// in `problems` (by line) and skipped.
    public static func parseFile(_ text: String) -> (labels: WeekLabels, problems: [String]) {
        var out = WeekLabels()
        var problems: [String] = []
        for (i, row) in CSV.parse(text).enumerated() {
            guard let first = row.first else { continue }
            if i == 0 && first.trimmingCharacters(in: .whitespaces).lowercased() == "week" { continue }
            guard let week = LocalDate(first) else {
                problems.append("line \(i + 1): \u{201C}\(first)\u{201D} is not a yyyy-mm-dd date")
                continue
            }
            out[week] = row.count > 1 ? row[1] : ""
        }
        return (out, problems)
    }

    public func renderFile() -> String {
        CSV.render([WeekLabels.header] + sorted.map { [$0.week.iso, $0.label] })
    }
}

/// A week's Monday and its label.
public struct WeekLabelEntry: Hashable {
    public let week: LocalDate
    public let label: String
}

/// Whether a date like 5/10/2026 means 5 October (day first) or 10 May.
public enum DateOrder: String, CaseIterable, Identifiable {
    case dayMonth
    case monthDay

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dayMonth: return "Day/Month (5/10 = 5 Oct)"
        case .monthDay: return "Month/Day (10/5 = 5 Oct)"
        }
    }
}

/// Reads the dates people type in spreadsheets.
public enum FlexibleDate {
    static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    static let weekdayNames = ["mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
                               "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let ignorableWords: Set<String> = ["week", "wk", "of", "w", "c", "wc", "beginning", "commencing",
                                              "starting", "from", "the"]

    /// Parses `text` as a date. Understands `2026-10-05` (also with `/` or
    /// `.`, or followed by a time), `5/10/2026` and `5/10/26` and `5/10` in
    /// `order`, `5 Oct 2026`, `Monday, 5th October`, `Oct 5, 2026`, and
    /// spreadsheet serial numbers (45935). A missing year is `defaultYear`.
    public static func parse(_ text: String, order: DateOrder, defaultYear: Int) -> (date: LocalDate, hasYear: Bool)? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        // A spreadsheet serial number (days since 1899-12-30).
        if let serial = Double(t), serial >= 20000, serial < 80000, !t.contains("/") {
            return (LocalDate(ordinal: Int(serial) - 25569), true)
        }

        // An ISO date followed by a time.
        if t.count > 10, let space = t.firstIndex(where: { $0 == " " || $0 == "T" }),
           t.distance(from: t.startIndex, to: space) == 10 {
            t = String(t[..<space])
        }

        // Tokens: runs of digits, runs of letters; everything else separates.
        var tokens: [String] = []
        var current = ""
        var currentIsDigit = false
        for ch in t.lowercased() {
            let isDigit = ch.isASCII && ch.isNumber
            let isLetter = ch.isLetter
            if isDigit || isLetter {
                if !current.isEmpty && isDigit != currentIsDigit {
                    tokens.append(current)
                    current = ""
                }
                current.append(ch)
                currentIsDigit = isDigit
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var numbers: [String] = []
        var month: Int?
        var lastWasNumber = false
        for token in tokens {
            if let first = token.first, first.isNumber {
                numbers.append(token)
                lastWasNumber = true
                continue
            }
            // Ordinal suffixes: the "th" of "5th".
            if lastWasNumber && ["st", "nd", "rd", "th"].contains(token) {
                lastWasNumber = false
                continue
            }
            lastWasNumber = false
            if token.count >= 3, let m = monthNames.firstIndex(where: { token.hasPrefix($0) }),
               monthNames[m].count <= token.count, isMonthWord(token, index: m) {
                guard month == nil else { return nil }
                month = m + 1
            } else if weekdayNames.contains(token) || ignorableWords.contains(token) {
                continue
            } else {
                return nil
            }
        }

        func year(_ s: String) -> Int? {
            guard let v = Int(s) else { return nil }
            if s.count == 4 { return v }
            if s.count == 2 { return 2000 + v }
            return nil
        }

        if let month {
            // 5 Oct 2026, Oct 5 2026, 5 Oct.
            guard (1...2).contains(numbers.count) else { return nil }
            var day: Int?
            var y: Int?
            for n in numbers {
                if n.count == 4 || (day != nil && y == nil) {
                    guard let v = year(n) else { return nil }
                    y = v
                } else {
                    guard day == nil, let v = Int(n) else { return nil }
                    day = v
                }
            }
            guard let d = day, let date = LocalDate(year: y ?? defaultYear, month: month, day: d) else { return nil }
            return (date, y != nil)
        }

        guard (2...3).contains(numbers.count) else { return nil }
        if numbers[0].count == 4 {
            guard numbers.count == 3, let y = Int(numbers[0]), let m = Int(numbers[1]), let d = Int(numbers[2]),
                  let date = LocalDate(year: y, month: m, day: d) else { return nil }
            return (date, true)
        }
        guard let a = Int(numbers[0]), let b = Int(numbers[1]), numbers[0].count <= 2, numbers[1].count <= 2
        else { return nil }
        let (d, m) = order == .dayMonth ? (a, b) : (b, a)
        var y: Int?
        if numbers.count == 3 {
            guard let v = year(numbers[2]) else { return nil }
            y = v
        }
        guard let date = LocalDate(year: y ?? defaultYear, month: m, day: d) else { return nil }
        return (date, y != nil)
    }

    /// "oct", "october" and "sept" are months; "octopus" is not.
    static func isMonthWord(_ token: String, index: Int) -> Bool {
        let full = ["january", "february", "march", "april", "may", "june", "july", "august",
                    "september", "october", "november", "december"][index]
        return full.hasPrefix(token) || token == "sept"
    }
}

/// Turns rows pasted from a spreadsheet into week labels: each row needs a
/// date (any day of the week) in one column and the label in another.
public enum WeekLabelImport {
    public enum Outcome: Equatable {
        case label(week: LocalDate, text: String)
        /// A row left out, with the reason.
        case skipped(String)
    }

    public struct Row: Identifiable, Equatable {
        public var id: Int { line }
        public let line: Int
        public let source: String
        public let outcome: Outcome
    }

    /// One row per non-blank line. Columns are split on tabs (what
    /// spreadsheets put on the clipboard), or as CSV when there are no tabs.
    public static func parse(_ text: String, order: DateOrder, referenceYear: Int) -> [Row] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let usesTabs = text.contains("\t")
        var rows: [Row] = []
        var seen: [LocalDate: Int] = [:]
        var previous: LocalDate?
        var year = referenceYear

        for (i, line) in lines.enumerated() {
            let lineNumber = i + 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let cells: [String] = usesTabs
                ? line.components(separatedBy: "\t")
                : (CSV.parse(line).first ?? [line])
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            var match: (index: Int, date: LocalDate)?
            for (j, cell) in trimmed.enumerated() where !cell.isEmpty {
                if let parsed = FlexibleDate.parse(cell, order: order, defaultYear: year) {
                    var date = parsed.date
                    if !parsed.hasYear, let p = previous, date.days(to: p) > 183,
                       let next = LocalDate(year: date.year + 1, month: date.month, day: date.day) {
                        // 3 Jan after 20 Dec: the next year.
                        date = next
                    }
                    if parsed.hasYear || date.year != year { year = date.year }
                    match = (j, date)
                    break
                }
            }
            guard let found = match else {
                rows.append(Row(line: lineNumber, source: line,
                                outcome: .skipped(rows.isEmpty ? "No date (a heading row?)" : "No date found")))
                continue
            }
            previous = found.date
            let others = trimmed.enumerated().filter { $0.offset != found.index && !$0.element.isEmpty }
            let after = others.first { $0.offset > found.index }
            guard let labelCell = after ?? others.first else {
                rows.append(Row(line: lineNumber, source: line, outcome: .skipped("No label")))
                continue
            }
            let week = found.date.monday
            if let earlier = seen[week] {
                rows.append(Row(line: lineNumber, source: line,
                                outcome: .skipped("Same week as line \(earlier)")))
                continue
            }
            seen[week] = lineNumber
            rows.append(Row(line: lineNumber, source: line,
                            outcome: .label(week: week, text: WeekLabels.oneLine(labelCell.element))))
        }
        return rows
    }

    /// The labels the rows set.
    public static func labels(from rows: [Row]) -> [LocalDate: String] {
        var out: [LocalDate: String] = [:]
        for row in rows {
            if case let .label(week, text) = row.outcome { out[week] = text }
        }
        return out
    }
}
