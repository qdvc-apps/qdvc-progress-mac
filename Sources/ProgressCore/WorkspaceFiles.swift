import Foundation
import Yams

/// Reads and writes `projects.yml` (docs/FILE_FORMAT.md §3).
public enum ProjectsFile {
    static let projectKeys = ["key", "id", "title", "programme", "target", "collaborators", "active",
                              "inactive_periods"]
    static let periodKeys = ["from", "to", "label"]

    /// The list, and a description of every entry that had to be repaired
    /// or skipped.
    public static func parse(_ text: String) throws -> (list: ProjectList, problems: [String]) {
        var list = ProjectList()
        var problems: [String] = []
        var projectNodes: [Node] = []
        for (k, v) in try YamlIO.mappingPairs(text) {
            switch k {
            case "programmes":
                for item in YamlIO.sequence(v) {
                    if let name = YamlIO.string(item) {
                        addProgramme(Programme(name: YamlIO.oneLine(name)), to: &list)
                    } else if let pairs = try? YamlIO.pairs(item) {
                        var name = ""
                        var extras: [ExtraField] = []
                        for (pk, pv) in pairs {
                            if pk == "name" { name = YamlIO.string(pv).map(YamlIO.oneLine) ?? "" }
                            else { extras.append(ExtraField(key: pk, value: pv)) }
                        }
                        if name.isEmpty { problems.append("A programme has no name and was skipped.") }
                        else { addProgramme(Programme(name: name, extras: extras), to: &list) }
                    }
                }
            case "projects":
                projectNodes = YamlIO.sequence(v)
            default:
                list.extras.append(ExtraField(key: k, value: v))
            }
        }

        for (i, node) in projectNodes.enumerated() {
            guard let pairs = try? YamlIO.pairs(node) else {
                problems.append("Project \(i + 1) is not a mapping and was skipped.")
                continue
            }
            var values: [String: Node] = [:]
            var extras: [ExtraField] = []
            for (k, v) in pairs {
                if projectKeys.contains(k) {
                    if values[k] == nil { values[k] = v }
                } else {
                    extras.append(ExtraField(key: k, value: v))
                }
            }
            var title = values["title"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? ""
            var key = values["key"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? ""
            if title.isEmpty && key.isEmpty {
                problems.append("Project \(i + 1) has neither a key nor a title and was skipped.")
                continue
            }
            if title.isEmpty { title = key }
            if key.isEmpty {
                key = list.newKey(for: title)
                problems.append("\u{201C}\(title)\u{201D} had no key; it was given \u{201C}\(key)\u{201D}.")
            } else if list.project(key) != nil {
                let fresh = list.newKey(for: key)
                problems.append("The key \u{201C}\(key)\u{201D} is used twice; the second project was given \u{201C}\(fresh)\u{201D}.")
                key = fresh
            }

            var periods: [InactivePeriod] = []
            for (j, pn) in (values["inactive_periods"].map(YamlIO.sequence) ?? []).enumerated() {
                guard let pp = try? YamlIO.pairs(pn) else { continue }
                var from: LocalDate?
                var to: LocalDate?
                var label = ""
                var pextras: [ExtraField] = []
                for (k, v) in pp {
                    switch k {
                    case "from": from = YamlIO.string(v).flatMap { LocalDate($0) }
                    case "to": to = YamlIO.string(v).flatMap { LocalDate($0) }
                    case "label": label = YamlIO.string(v).map(YamlIO.oneLine) ?? ""
                    default: pextras.append(ExtraField(key: k, value: v))
                    }
                }
                guard let f = from else {
                    problems.append("Inactive period \(j + 1) of \u{201C}\(title)\u{201D} has no valid from date and was skipped.")
                    continue
                }
                periods.append(InactivePeriod(range: DayRange(from: f, to: to ?? f), label: label, extras: pextras))
            }

            let programme = values["programme"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? ""
            if !programme.isEmpty { addProgramme(Programme(name: programme), to: &list) }

            list.projects.append(Project(
                key: key,
                code: values["id"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? "",
                title: title,
                programme: programme,
                target: values["target"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? "",
                collaborators: values["collaborators"].flatMap(YamlIO.string).map(YamlIO.oneLine) ?? "",
                isActive: values["active"].flatMap(YamlIO.bool) ?? true,
                inactivePeriods: Project.merged(periods),
                extras: extras))
        }
        return (list, problems)
    }

    private static func addProgramme(_ p: Programme, to list: inout ProjectList) {
        guard !p.name.isEmpty, !list.programmeNames.contains(p.name) else { return }
        list.programmes.append(p)
    }

    /// `programmes` (in order), then `projects` (in order), then unknown
    /// keys. Within a project: key, id, title, programme, target,
    /// collaborators, active (only when false), inactive_periods, then
    /// unknown keys. Empty fields are left out.
    public static func render(_ list: ProjectList) -> String {
        var pairs: [(Node, Node)] = []
        let programmes: [Node] = list.programmes.map { p in
            var pp: [(Node, Node)] = [(YamlIO.key("name"), YamlIO.str(YamlIO.oneLine(p.name)))]
            for e in p.extras { pp.append((YamlIO.key(e.key), e.value)) }
            return Node(pp)
        }
        pairs.append((YamlIO.key("programmes"), Node(programmes)))
        pairs.append((YamlIO.key("projects"), Node(list.projects.map(renderProject))))
        for e in list.extras { pairs.append((YamlIO.key(e.key), e.value)) }
        return YamlIO.emit(Node(pairs))
    }

    static func renderProject(_ p: Project) -> Node {
        var pairs: [(Node, Node)] = [(YamlIO.key("key"), YamlIO.str(p.key))]
        func add(_ k: String, _ v: String) {
            let t = YamlIO.oneLine(v)
            if !t.isEmpty { pairs.append((YamlIO.key(k), YamlIO.str(t))) }
        }
        add("id", p.code)
        add("title", p.title)
        add("programme", p.programme)
        add("target", p.target)
        add("collaborators", p.collaborators)
        if !p.isActive { pairs.append((YamlIO.key("active"), YamlIO.boolean(false))) }
        if !p.inactivePeriods.isEmpty {
            let periods: [Node] = p.inactivePeriods.map { period in
                var pp: [(Node, Node)] = [
                    (YamlIO.key("from"), YamlIO.date(period.range.from)),
                    (YamlIO.key("to"), YamlIO.date(period.range.to)),
                ]
                let label = YamlIO.oneLine(period.label)
                if !label.isEmpty { pp.append((YamlIO.key("label"), YamlIO.str(label))) }
                for e in period.extras { pp.append((YamlIO.key(e.key), e.value)) }
                return Node(pp)
            }
            pairs.append((YamlIO.key("inactive_periods"), Node(periods)))
        }
        for e in p.extras { pairs.append((YamlIO.key(e.key), e.value)) }
        return Node(pairs)
    }
}

/// Reads and writes `progress.yml`, the workspace settings
/// (docs/FILE_FORMAT.md §2).
public enum SettingsFile {
    public static let formatVersion = 1
    static let knownKeys = ["format", "sizes", "meeting_size", "due_value", "planned_value", "day_peak"]

    public static func parse(_ text: String) throws -> WorkloadSettings {
        var s = WorkloadSettings()
        var extras: [ExtraField] = []
        for (k, v) in try YamlIO.mappingPairs(text) {
            switch k {
            case "format":
                break
            case "sizes":
                var values = s.sizeValues
                for (sk, sv) in (try? YamlIO.pairs(v)) ?? [] {
                    if let label = CellLabel(lenient: sk), let i = label.sizeIndex, let n = YamlIO.int(sv) {
                        values[i] = n
                    }
                }
                s.sizeValues = values
            case "meeting_size":
                if let t = YamlIO.string(v), let label = CellLabel(lenient: t), label.isSize { s.meetingSize = label }
            case "due_value":
                if let n = YamlIO.int(v) { s.dueValue = n }
            case "planned_value":
                if let n = YamlIO.int(v) { s.plannedValue = n }
            case "day_peak":
                if let n = YamlIO.int(v), n > 0 { s.dayPeak = n }
            default:
                extras.append(ExtraField(key: k, value: v))
            }
        }
        s.extras = extras
        return s
    }

    public static func render(_ s: WorkloadSettings) -> String {
        var sizes: [(Node, Node)] = []
        for (i, label) in CellLabel.sizes.enumerated() {
            sizes.append((YamlIO.key(label.text), YamlIO.number(s.sizeValues[i])))
        }
        var pairs: [(Node, Node)] = [
            (YamlIO.key("format"), YamlIO.number(formatVersion)),
            (YamlIO.key("sizes"), Node(sizes)),
            (YamlIO.key("meeting_size"), YamlIO.str(s.meetingSize.text)),
            (YamlIO.key("due_value"), YamlIO.number(s.dueValue)),
            (YamlIO.key("planned_value"), YamlIO.number(s.plannedValue)),
            (YamlIO.key("day_peak"), YamlIO.number(s.dayPeak)),
        ]
        for e in s.extras { pairs.append((YamlIO.key(e.key), e.value)) }
        return YamlIO.emit(Node(pairs))
    }
}

/// Reads and writes the monthly log files, `log/yyyy/yyyy-mm.csv`
/// (docs/FILE_FORMAT.md §4).
public enum LogFile {
    public static let header = ["date", "project", "label", "note"]

    /// The entries of one month's file. `problems` describes rows that
    /// could not be read; a file with problems is never rewritten.
    public static func parse(_ text: String, month: MonthKey? = nil) -> (entries: [LogEntry], problems: [String]) {
        var rows = CSV.parse(text)
        var columns = (date: 0, project: 1, label: 2, note: 3)
        if let first = rows.first, first.first?.trimmingCharacters(in: .whitespaces).lowercased() == "date" {
            let names = first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            columns = (names.firstIndex(of: "date") ?? 0,
                       names.firstIndex(of: "project") ?? 1,
                       names.firstIndex(of: "label") ?? 2,
                       names.firstIndex(of: "note") ?? 3)
            rows.removeFirst()
        }
        var entries: [LogEntry] = []
        var problems: [String] = []
        for (i, row) in rows.enumerated() {
            let line = i + 2
            func cell(_ c: Int) -> String { c < row.count ? row[c] : "" }
            let dateText = cell(columns.date).trimmingCharacters(in: .whitespaces)
            guard let date = LocalDate(dateText) else {
                problems.append("line \(line): \u{201C}\(dateText)\u{201D} is not a yyyy-mm-dd date")
                continue
            }
            if let month, date.monthKey != month {
                problems.append("line \(line): \(date.iso) is not in \(month)")
                continue
            }
            let project = cell(columns.project).trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else {
                problems.append("line \(line): no project")
                continue
            }
            let labelText = cell(columns.label).trimmingCharacters(in: .whitespaces)
            var label: CellLabel?
            if !labelText.isEmpty {
                guard let l = CellLabel(lenient: labelText) else {
                    problems.append("line \(line): \u{201C}\(labelText)\u{201D} is not a label (XS, S, M, L, XL, mtg, (!), (P))")
                    continue
                }
                label = l
            }
            let entry = LogEntry(date: date, project: project, cell: Cell(label: label, note: cell(columns.note)))
            if !entry.cell.isEmpty { entries.append(entry) }
        }
        return (entries, problems)
    }

    public static func render(_ entries: [LogEntry]) -> String {
        let sorted = entries.filter { !$0.cell.isEmpty }.sorted { ($0.date, $0.project) < ($1.date, $1.project) }
        return CSV.render([header] + sorted.map {
            [$0.date.iso, $0.project, $0.cell.label?.text ?? "", trimTrailing($0.cell.note)]
        })
    }

    static func trimTrailing(_ s: String) -> String {
        var out = s
        while let last = out.last, last.isNewline || last == " " || last == "\t" { out.removeLast() }
        return out
    }

    /// `log/2026/2026-10.csv`.
    public static func relativePath(for month: MonthKey) -> String {
        "log/\(String(format: "%04d", month.year))/\(month.description).csv"
    }
}
