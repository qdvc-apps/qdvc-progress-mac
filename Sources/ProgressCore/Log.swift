import Foundation

/// One entry of the log: a project's cell on a day.
public struct LogEntry: Equatable {
    public var date: LocalDate
    public var project: String
    public var cell: Cell

    public init(date: LocalDate, project: String, cell: Cell) {
        self.date = date
        self.project = project
        self.cell = cell
    }
}

/// Every non-empty cell, by day and project key. Empty cells are never
/// stored.
public struct ProgressLog: Equatable {
    public private(set) var byDate: [LocalDate: [String: Cell]] = [:]

    public init() {}

    public init(entries: [LogEntry]) {
        for e in entries { self[e.project, e.date] = e.cell }
    }

    public subscript(project: String, date: LocalDate) -> Cell {
        get { byDate[date]?[project] ?? Cell() }
        set {
            if newValue.isEmpty {
                byDate[date]?[project] = nil
                if byDate[date]?.isEmpty == true { byDate[date] = nil }
            } else {
                byDate[date, default: [:]][project] = newValue
            }
        }
    }

    public func cells(on date: LocalDate) -> [String: Cell] {
        byDate[date] ?? [:]
    }

    public var isEmpty: Bool { byDate.isEmpty }

    public var entryCount: Int { byDate.values.reduce(0) { $0 + $1.count } }

    /// The first and last days with an entry.
    public var dateBounds: DayRange? {
        guard let lo = byDate.keys.min(), let hi = byDate.keys.max() else { return nil }
        return DayRange(from: lo, to: hi)
    }

    /// The months that have at least one entry.
    public var months: Set<MonthKey> {
        Set(byDate.keys.map(\.monthKey))
    }

    /// The month's entries, by date, then by project key (the order of the
    /// month's log file).
    public func entries(in month: MonthKey) -> [LogEntry] {
        var out: [LogEntry] = []
        for (date, cells) in byDate where date.monthKey == month {
            for (project, cell) in cells {
                out.append(LogEntry(date: date, project: project, cell: cell))
            }
        }
        return out.sorted { ($0.date, $0.project) < ($1.date, $1.project) }
    }

    /// Replaces everything in `month` with `entries` (which must all fall in
    /// that month).
    public mutating func replace(month: MonthKey, with entries: [LogEntry]) {
        for date in byDate.keys where date.monthKey == month { byDate[date] = nil }
        for e in entries where e.date.monthKey == month { self[e.project, e.date] = e.cell }
    }

    /// All entries of one project, by date.
    public func entries(for project: String) -> [LogEntry] {
        var out: [LogEntry] = []
        for (date, cells) in byDate {
            if let c = cells[project] { out.append(LogEntry(date: date, project: project, cell: c)) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Removes a project's entries; returns what was removed.
    @discardableResult
    public mutating func removeAll(for project: String) -> [LogEntry] {
        let removed = entries(for: project)
        for e in removed { self[project, e.date] = Cell() }
        return removed
    }

    /// The workload on `date`: the sum of the label values of the projects
    /// `includes` accepts.
    public func total(on date: LocalDate, settings: WorkloadSettings,
                      includes: (String) -> Bool = { _ in true }) -> Int {
        guard let cells = byDate[date] else { return 0 }
        var sum = 0
        for (project, cell) in cells where includes(project) {
            sum += settings.value(of: cell.label)
        }
        return sum
    }

    /// The sum of `total(on:)` over a run of days.
    public func total(over range: DayRange, settings: WorkloadSettings,
                      includes: (String) -> Bool = { _ in true }) -> Int {
        range.days.reduce(0) { $0 + total(on: $1, settings: settings, includes: includes) }
    }

    /// The last day each project had work or a meeting logged (not counting
    /// due dates or plans), by project key.
    public func lastWorked() -> [String: LocalDate] {
        var out: [String: LocalDate] = [:]
        for (date, cells) in byDate {
            for (project, cell) in cells {
                guard let label = cell.label, label.isSize || label == .meeting else { continue }
                if let current = out[project], current >= date { continue }
                out[project] = date
            }
        }
        return out
    }
}

/// The colour depth (0…1) of a total, given the total at which it peaks.
public func heatLevel(_ total: Int, peak: Int) -> Double {
    guard total > 0, peak > 0 else { return 0 }
    return min(1, Double(total) / Double(peak))
}
