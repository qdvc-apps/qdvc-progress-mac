import Foundation

/// A run of days on which a project was set aside (on hold, waiting, on
/// leave), with an optional label shown across the run in the grid. This is
/// separate from the project-level active flag.
public struct InactivePeriod: Equatable, Identifiable {
    /// In memory only, so SwiftUI can tell periods apart while editing.
    public var id: UUID
    public var range: DayRange
    public var label: String
    public var extras: [ExtraField]

    public init(id: UUID = UUID(), range: DayRange, label: String = "", extras: [ExtraField] = []) {
        self.id = id
        self.range = range
        self.label = label
        self.extras = extras
    }
}

/// A project: one row of the grid.
public struct Project: Identifiable, Equatable {
    public var id: String { key }
    /// The stable key that ties the project to its log rows. Made from the
    /// title when the project is created and never changed afterwards, so
    /// titles can be edited freely.
    public let key: String
    /// The optional project ID, in the form NNXX (e.g. 26XY). Called `id` in
    /// projects.yml; `code` here to keep it apart from `Identifiable.id`.
    public var code: String
    public var title: String
    /// The programme of work the project belongs to; empty for none.
    public var programme: String
    public var target: String
    public var collaborators: String
    /// The project-level flag. Inactive projects can be hidden with the
    /// Status filter; they keep all their history.
    public var isActive: Bool
    public var inactivePeriods: [InactivePeriod]
    public var extras: [ExtraField]

    public init(key: String, code: String = "", title: String, programme: String = "",
                target: String = "", collaborators: String = "", isActive: Bool = true,
                inactivePeriods: [InactivePeriod] = [], extras: [ExtraField] = []) {
        self.key = key
        self.code = code
        self.title = title
        self.programme = programme
        self.target = target
        self.collaborators = collaborators
        self.isActive = isActive
        self.inactivePeriods = inactivePeriods
        self.extras = extras
    }

    /// Whether `code` has the NNXX form: two digits, then two letters.
    public static func isConventionalCode(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count == 4 else { return false }
        return chars[0].isASCII && chars[0].isNumber && chars[1].isASCII && chars[1].isNumber
            && chars[2].isASCII && chars[2].isLetter && chars[3].isASCII && chars[3].isLetter
    }

    public func inactivePeriod(on date: LocalDate) -> InactivePeriod? {
        inactivePeriods.first { $0.range.contains(date) }
    }

    public func isInactive(on date: LocalDate) -> Bool {
        inactivePeriod(on: date) != nil
    }

    /// Marks `days` inactive (merging with neighbouring periods, whose label
    /// the merged period keeps) or active again (splitting periods around
    /// them).
    public mutating func setInactive(_ inactive: Bool, on days: [LocalDate]) {
        guard !days.isEmpty else { return }
        if inactive {
            var periods = inactivePeriods
            for d in Set(days).sorted() where !periods.contains(where: { $0.range.contains(d) }) {
                periods.append(InactivePeriod(range: DayRange(from: d, to: d)))
            }
            inactivePeriods = Project.merged(periods)
        } else {
            let removing = Set(days)
            var out: [InactivePeriod] = []
            for p in inactivePeriods {
                guard p.range.days.contains(where: { removing.contains($0) }) else {
                    out.append(p)
                    continue
                }
                var runs: [DayRange] = []
                var start: LocalDate?
                var previous: LocalDate?
                for d in p.range.days {
                    if removing.contains(d) {
                        if let s = start, let e = previous { runs.append(DayRange(from: s, to: e)) }
                        start = nil
                    } else if start == nil {
                        start = d
                    }
                    if !removing.contains(d) { previous = d }
                }
                if let s = start, let e = previous { runs.append(DayRange(from: s, to: e)) }
                for (i, r) in runs.enumerated() {
                    out.append(InactivePeriod(id: i == 0 ? p.id : UUID(), range: r, label: p.label,
                                              extras: p.extras))
                }
            }
            inactivePeriods = out.sorted { $0.range.from < $1.range.from }
        }
    }

    /// Sorted, with overlapping or adjoining periods joined. A joined period
    /// keeps the first non-empty label among those it was made from.
    public static func merged(_ periods: [InactivePeriod]) -> [InactivePeriod] {
        let sorted = periods.sorted { $0.range.from < $1.range.from }
        var out: [InactivePeriod] = []
        for p in sorted {
            if var last = out.last, last.range.overlapsOrTouches(p.range) {
                last.range = DayRange(from: last.range.from, to: max(last.range.to, p.range.to))
                if last.label.trimmingCharacters(in: .whitespaces).isEmpty { last.label = p.label }
                out[out.count - 1] = last
            } else {
                out.append(p)
            }
        }
        return out
    }

    /// Text the search field matches against.
    public var searchText: String {
        [code, title, programme, target, collaborators].joined(separator: "\n").lowercased()
    }
}

/// A programme of work: a named group of projects.
public struct Programme: Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var extras: [ExtraField]

    public init(name: String, extras: [ExtraField] = []) {
        self.name = name
        self.extras = extras
    }
}

/// The contents of `projects.yml`: the programmes in order, and the
/// projects in order. A project's `programme` names its group; projects
/// with an empty or unknown programme are listed under "No Programme".
public struct ProjectList: Equatable {
    public var programmes: [Programme]
    public var projects: [Project]
    public var extras: [ExtraField]

    public init(programmes: [Programme] = [], projects: [Project] = [], extras: [ExtraField] = []) {
        self.programmes = programmes
        self.projects = projects
        self.extras = extras
    }

    public static let noProgrammeTitle = "No Programme"

    public func project(_ key: String) -> Project? {
        projects.first { $0.key == key }
    }

    public func index(of key: String) -> Int? {
        projects.firstIndex { $0.key == key }
    }

    public var programmeNames: [String] { programmes.map(\.name) }

    /// The project whose ID is `code` (ignoring case and surrounding
    /// spaces), other than `excluding`. Nil for an empty code.
    public func project(withCode code: String, excluding key: String? = nil) -> Project? {
        let c = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !c.isEmpty else { return nil }
        return projects.first { $0.key != key && $0.code.trimmingCharacters(in: .whitespaces).lowercased() == c }
    }

    /// The programme a project is grouped under: its own if it exists,
    /// otherwise "" (No Programme).
    public func group(of project: Project) -> String {
        programmeNames.contains(project.programme) ? project.programme : ""
    }

    /// A new, unused key made from `title` (lower case ASCII letters, digits
    /// and hyphens, at most 40 characters), with `-2`, `-3`… added if taken.
    public func newKey(for title: String) -> String {
        let base = ProjectList.slug(title)
        let taken = Set(projects.map(\.key))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        var pendingHyphen = false
        for scalar in folded.unicodeScalars {
            let isAlnum = (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
            if isAlnum {
                if pendingHyphen && !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
            if out.count >= 40 { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "project" : out
    }
}
