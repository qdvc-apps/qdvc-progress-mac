import Foundation

/// Which projects the Status filter shows (the project-level active flag).
public enum StatusFilter: String, CaseIterable, Identifiable {
    case active
    case all
    case inactive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: return "Active Projects"
        case .all: return "All Projects"
        case .inactive: return "Inactive Projects"
        }
    }

    public func includes(_ p: Project) -> Bool {
        switch self {
        case .active: return p.isActive
        case .all: return true
        case .inactive: return !p.isActive
        }
    }
}

public enum SortKey: String, CaseIterable, Identifiable {
    /// The order of projects.yml, changed with Move Up / Move Down.
    case manual
    case title
    case code
    case target
    case collaborators
    case lastWorked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: return "Manual Order"
        case .title: return "Title"
        case .code: return "ID"
        case .target: return "Target"
        case .collaborators: return "Collaborators"
        case .lastWorked: return "Last Worked On"
        }
    }

    /// The direction a new sort starts in: most recent first for Last
    /// Worked On, A to Z otherwise.
    public var defaultAscending: Bool { self != .lastWorked }
}

/// The filter, search and sort that decide which rows the grid shows.
public struct ProjectQuery: Equatable {
    /// Nil shows every programme; "" shows only projects with none.
    public var programme: String?
    public var status: StatusFilter
    public var search: String
    public var sort: SortKey
    public var ascending: Bool
    /// Show projects under programme headings (otherwise one flat list).
    public var grouped: Bool

    public init(programme: String? = nil, status: StatusFilter = .active, search: String = "",
                sort: SortKey = .manual, ascending: Bool = true, grouped: Bool = true) {
        self.programme = programme
        self.status = status
        self.search = search
        self.sort = sort
        self.ascending = ascending
        self.grouped = grouped
    }

    public func includes(_ p: Project, in list: ProjectList) -> Bool {
        if let programme, list.group(of: p) != programme { return false }
        guard status.includes(p) else { return false }
        let terms = search.lowercased().split(whereSeparator: \.isWhitespace)
        if !terms.isEmpty {
            let haystack = p.searchText
            for t in terms where !haystack.contains(t) { return false }
        }
        return true
    }
}

/// A row of the grid.
public enum GridRow: Equatable {
    /// A programme heading ("" for No Programme), with the number of
    /// projects under it that pass the filter.
    case programme(name: String, count: Int, collapsed: Bool)
    case project(key: String)

    public var projectKey: String? {
        if case let .project(key) = self { return key }
        return nil
    }
}

public enum RowLayout {
    /// The grid's rows for `query`, and the keys of every project that
    /// passes the filter (including those in collapsed programmes), in row
    /// order.
    public static func rows(for list: ProjectList, query: ProjectQuery, collapsed: Set<String>,
                            lastWorked: [String: LocalDate]) -> (rows: [GridRow], included: [String]) {
        let order = Dictionary(uniqueKeysWithValues: list.projects.enumerated().map { ($0.element.key, $0.offset) })
        let matching = list.projects.filter { query.includes($0, in: list) }
        let sorted = sort(matching, by: query.sort, ascending: query.ascending, order: order, lastWorked: lastWorked)

        guard query.grouped else {
            return (sorted.map { .project(key: $0.key) }, sorted.map(\.key))
        }

        var rows: [GridRow] = []
        var included: [String] = []
        for name in list.programmeNames + [""] {
            let members = sorted.filter { list.group(of: $0) == name }
            guard !members.isEmpty else { continue }
            let isCollapsed = collapsed.contains(name)
            rows.append(.programme(name: name, count: members.count, collapsed: isCollapsed))
            included.append(contentsOf: members.map(\.key))
            if !isCollapsed { rows.append(contentsOf: members.map { .project(key: $0.key) }) }
        }
        return (rows, included)
    }

    static func sort(_ projects: [Project], by key: SortKey, ascending: Bool, order: [String: Int],
                     lastWorked: [String: LocalDate]) -> [Project] {
        func manual(_ a: Project, _ b: Project) -> Bool { (order[a.key] ?? 0) < (order[b.key] ?? 0) }
        func text(_ x: String, _ y: String, _ a: Project, _ b: Project) -> Bool {
            // Empty values go last whichever the direction.
            if x.isEmpty != y.isEmpty { return !x.isEmpty }
            let r = x.localizedStandardCompare(y)
            if r == .orderedSame { return manual(a, b) }
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
        switch key {
        case .manual:
            return ascending ? projects.sorted(by: manual) : Array(projects.sorted(by: manual).reversed())
        case .title:
            return projects.sorted { text($0.title, $1.title, $0, $1) }
        case .code:
            return projects.sorted { text($0.code, $1.code, $0, $1) }
        case .target:
            return projects.sorted { text($0.target, $1.target, $0, $1) }
        case .collaborators:
            return projects.sorted { text($0.collaborators, $1.collaborators, $0, $1) }
        case .lastWorked:
            return projects.sorted { a, b in
                let x = lastWorked[a.key], y = lastWorked[b.key]
                switch (x, y) {
                case let (x?, y?) where x != y: return ascending ? x < y : x > y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return manual(a, b)
                }
            }
        }
    }
}
