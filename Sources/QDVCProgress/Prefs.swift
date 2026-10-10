import Foundation
import ProgressCore

/// The optional columns on the left of the grid (the title is always shown).
enum LeftColumn: String, CaseIterable, Identifiable {
    case code
    case title
    case target
    case collaborators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: return "ID"
        case .title: return "Project"
        case .target: return "Target"
        case .collaborators: return "Collaborators"
        }
    }

    var defaultWidth: Double {
        switch self {
        case .code: return 52
        case .title: return 220
        case .target: return 110
        case .collaborators: return 130
        }
    }

    var minWidth: Double { self == .title ? 100 : 36 }

    /// The sort the column heading chooses when clicked.
    var sortKey: SortKey {
        switch self {
        case .code: return .code
        case .title: return .title
        case .target: return .target
        case .collaborators: return .collaborators
        }
    }
}

/// Which projects the totals at the bottom add up.
enum TotalsScope: String, CaseIterable, Identifiable {
    case visible
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visible: return "Projects Shown"
        case .all: return "All Projects"
        }
    }
}

/// App preferences, in the standard defaults domain
/// (`defaults read org.qdvc.progress.mac`). The workload mapping and the
/// week labels belong to the workspace instead, so they travel with it.
enum Prefs {
    private static var defaults: UserDefaults { .standard }

    static var recentWorkspaces: [String] {
        get { defaults.stringArray(forKey: "recentWorkspaces") ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: "recentWorkspaces") }
    }

    static var lastWorkspace: String? {
        get { defaults.string(forKey: "lastWorkspace") }
        set { defaults.set(newValue, forKey: "lastWorkspace") }
    }

    static var reopenLast: Bool {
        get { defaults.object(forKey: "reopenLastWorkspace") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "reopenLastWorkspace") }
    }

    static var query: ProjectQuery {
        get {
            var q = ProjectQuery()
            if defaults.bool(forKey: "filterHasProgramme") {
                q.programme = defaults.string(forKey: "filterProgramme") ?? ""
            }
            q.status = StatusFilter(rawValue: defaults.string(forKey: "filterStatus") ?? "") ?? .active
            q.sort = SortKey(rawValue: defaults.string(forKey: "sortKey") ?? "") ?? .manual
            q.ascending = defaults.object(forKey: "sortAscending") as? Bool ?? q.sort.defaultAscending
            q.grouped = defaults.object(forKey: "groupByProgramme") as? Bool ?? true
            return q
        }
        set {
            defaults.set(newValue.programme != nil, forKey: "filterHasProgramme")
            defaults.set(newValue.programme ?? "", forKey: "filterProgramme")
            defaults.set(newValue.status.rawValue, forKey: "filterStatus")
            defaults.set(newValue.sort.rawValue, forKey: "sortKey")
            defaults.set(newValue.ascending, forKey: "sortAscending")
            defaults.set(newValue.grouped, forKey: "groupByProgramme")
        }
    }

    static var collapsedProgrammes: Set<String> {
        get { Set(defaults.stringArray(forKey: "collapsedProgrammes") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "collapsedProgrammes") }
    }

    static var hiddenColumns: Set<LeftColumn> {
        get {
            guard let raw = defaults.stringArray(forKey: "hiddenColumns") else { return [] }
            return Set(raw.compactMap(LeftColumn.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "hiddenColumns") }
    }

    static var columnWidths: [LeftColumn: Double] {
        get {
            let raw = defaults.dictionary(forKey: "columnWidths") as? [String: Double] ?? [:]
            var out: [LeftColumn: Double] = [:]
            for c in LeftColumn.allCases { out[c] = max(c.minWidth, raw[c.rawValue] ?? c.defaultWidth) }
            return out
        }
        set {
            var raw: [String: Double] = [:]
            for (k, v) in newValue { raw[k.rawValue] = v }
            defaults.set(raw, forKey: "columnWidths")
        }
    }

    static let defaultCellWidth: Double = 30
    static let cellWidthRange: ClosedRange<Double> = 22...56

    static var cellWidth: Double {
        get {
            let v = defaults.object(forKey: "cellWidth") as? Double ?? defaultCellWidth
            return min(max(v, cellWidthRange.lowerBound), cellWidthRange.upperBound)
        }
        set { defaults.set(newValue, forKey: "cellWidth") }
    }

    static var totalsScope: TotalsScope {
        get { TotalsScope(rawValue: defaults.string(forKey: "totalsScope") ?? "") ?? .visible }
        set { defaults.set(newValue.rawValue, forKey: "totalsScope") }
    }

    static var pasteMode: PasteMode {
        get { PasteMode(rawValue: defaults.string(forKey: "pasteMode") ?? "") ?? .both }
        set { defaults.set(newValue.rawValue, forKey: "pasteMode") }
    }

    static var showProgrammeSubtotals: Bool {
        get { defaults.object(forKey: "programmeSubtotals") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "programmeSubtotals") }
    }

    static var isoWeekFallback: Bool {
        get { defaults.object(forKey: "isoWeekFallback") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isoWeekFallback") }
    }

    static var inspectorShown: Bool {
        get { defaults.object(forKey: "inspectorShown") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "inspectorShown") }
    }

    static var dateOrder: DateOrder {
        get {
            if let raw = defaults.string(forKey: "dateOrder"), let order = DateOrder(rawValue: raw) { return order }
            return localeDateOrder
        }
        set { defaults.set(newValue.rawValue, forKey: "dateOrder") }
    }

    /// Day/month or month/day, from the order of the locale's short dates.
    static var localeDateOrder: DateOrder {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current) ?? "d/M/y"
        guard let dIndex = format.firstIndex(of: "d"), let mIndex = format.firstIndex(of: "M") else { return .dayMonth }
        return mIndex < dIndex ? .monthDay : .dayMonth
    }
}
