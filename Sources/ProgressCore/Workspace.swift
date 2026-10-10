import Foundation

/// A file that could not be read cleanly.
public struct LoadIssue: Identifiable, Equatable {
    public var id: String { relativePath }
    public let relativePath: String
    public let messages: [String]
    /// The file is left alone: changes that belong in it are kept in memory
    /// but not written until the file is fixed and the workspace refreshed.
    public let isProtected: Bool
}

public enum WorkspaceError: Error, CustomStringConvertible {
    case protected(String)

    public var description: String {
        switch self {
        case .protected(let path):
            return "\(path) could not be read when the workspace was opened, so it is not being overwritten. Fix the file and choose View \u{203A} Refresh."
        }
    }
}

/// Everything read from a workspace.
public struct WorkspaceContents {
    public var settings = WorkloadSettings()
    public var projects = ProjectList()
    public var weekLabels = WeekLabels()
    public var log = ProgressLog()
    public var issues: [LoadIssue] = []

    public init() {}
}

/// A workspace folder (docs/FILE_FORMAT.md §1). Every write is atomic and
/// immediate; the files are meant to be committed to Git.
public final class Workspace {
    public let root: URL
    public static let settingsFile = "progress.yml"
    public static let projectsFile = "projects.yml"
    public static let weekLabelsFile = "week-labels.csv"
    public static let logFolder = "log"

    private struct Stamp: Equatable {
        let modified: Date?
        let size: Int?
    }

    private var stamps: [String: Stamp] = [:]
    public private(set) var protectedFiles: Set<String> = []
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Whether the folder holds a `progress.yml` or `projects.yml`.
    public static func looksLikeWorkspace(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent(settingsFile).path)
            || fm.fileExists(atPath: url.appendingPathComponent(projectsFile).path)
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Creates `progress.yml`, `projects.yml` and `log/` where missing.
    public func ensureLayout() throws {
        try fm.createDirectory(at: url(for: Workspace.logFolder), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url(for: Workspace.settingsFile).path) {
            try write(SettingsFile.render(WorkloadSettings()), to: Workspace.settingsFile)
        }
        if !fm.fileExists(atPath: url(for: Workspace.projectsFile).path) {
            try write(ProjectsFile.render(ProjectList()), to: Workspace.projectsFile)
        }
    }

    // MARK: Reading

    /// Every `log/yyyy/yyyy-mm.csv`, by month.
    public func logFiles() -> [(month: MonthKey, path: String)] {
        let base = url(for: Workspace.logFolder)
        guard let years = try? fm.contentsOfDirectory(atPath: base.path) else { return [] }
        var out: [(MonthKey, String)] = []
        for year in years.sorted() where year.count == 4 && Int(year) != nil {
            guard let files = try? fm.contentsOfDirectory(atPath: base.appendingPathComponent(year).path) else { continue }
            for file in files.sorted() where file.lowercased().hasSuffix(".csv") {
                let stem = String(file.dropLast(4))
                guard let month = MonthKey(stem), String(month.year) == year else { continue }
                out.append((month, "\(Workspace.logFolder)/\(year)/\(file)"))
            }
        }
        return out.map { (month: $0.0, path: $0.1) }
    }

    private func stamp(_ relativePath: String) -> Stamp {
        let attrs = try? fm.attributesOfItem(atPath: url(for: relativePath).path)
        return Stamp(modified: attrs?[.modificationDate] as? Date,
                     size: (attrs?[.size] as? NSNumber)?.intValue)
    }

    private func readText(_ relativePath: String) throws -> String? {
        let u = url(for: relativePath)
        guard fm.fileExists(atPath: u.path) else { return nil }
        let data = try Data(contentsOf: u)
        guard let text = String(data: data, encoding: .utf8) else { throw FileError.notUTF8 }
        return text
    }

    /// Reads the whole workspace. A file that cannot be read at all is
    /// reported and protected from being overwritten; a file read with
    /// repairs (projects.yml) is reported but may be rewritten.
    public func load() -> WorkspaceContents {
        var c = WorkspaceContents()
        stamps = [:]
        protectedFiles = []

        func note(_ path: String, _ messages: [String], protect: Bool) {
            guard !messages.isEmpty else { return }
            c.issues.append(LoadIssue(relativePath: path, messages: messages, isProtected: protect))
            if protect { protectedFiles.insert(path) }
        }

        for path in [Workspace.settingsFile, Workspace.projectsFile, Workspace.weekLabelsFile] {
            stamps[path] = stamp(path)
        }

        do {
            if let text = try readText(Workspace.settingsFile) { c.settings = try SettingsFile.parse(text) }
        } catch {
            note(Workspace.settingsFile, [String(describing: error)], protect: true)
        }

        do {
            if let text = try readText(Workspace.projectsFile) {
                let parsed = try ProjectsFile.parse(text)
                c.projects = parsed.list
                note(Workspace.projectsFile, parsed.problems, protect: false)
            }
        } catch {
            note(Workspace.projectsFile, [String(describing: error)], protect: true)
        }

        do {
            if let text = try readText(Workspace.weekLabelsFile) {
                let parsed = WeekLabels.parseFile(text)
                c.weekLabels = parsed.labels
                note(Workspace.weekLabelsFile, parsed.problems, protect: true)
            }
        } catch {
            note(Workspace.weekLabelsFile, [String(describing: error)], protect: true)
        }

        var entries: [LogEntry] = []
        for (month, path) in logFiles() {
            stamps[path] = stamp(path)
            do {
                guard let text = try readText(path) else { continue }
                let parsed = LogFile.parse(text, month: month)
                entries.append(contentsOf: parsed.entries)
                note(path, parsed.problems, protect: true)
            } catch {
                note(path, [String(describing: error)], protect: true)
            }
        }
        c.log = ProgressLog(entries: entries)
        return c
    }

    /// Whether any file was changed, added or removed since the last load
    /// or write (by another app, `git pull`, …).
    public func hasExternalChanges() -> Bool {
        var current: [String: Stamp] = [:]
        for path in [Workspace.settingsFile, Workspace.projectsFile, Workspace.weekLabelsFile] {
            current[path] = stamp(path)
        }
        for (_, path) in logFiles() { current[path] = stamp(path) }
        // Log files we deleted (an emptied month) have a nil stamp on both sides.
        let known = stamps.filter { $0.value.modified != nil || $0.value.size != nil }
        let now = current.filter { $0.value.modified != nil || $0.value.size != nil }
        return known != now
    }

    // MARK: Writing

    private func write(_ text: String, to relativePath: String) throws {
        if protectedFiles.contains(relativePath) { throw WorkspaceError.protected(relativePath) }
        let target = url(for: relativePath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
        stamps[relativePath] = stamp(relativePath)
    }

    public func saveSettings(_ s: WorkloadSettings) throws {
        try write(SettingsFile.render(s), to: Workspace.settingsFile)
    }

    public func saveProjects(_ list: ProjectList) throws {
        try write(ProjectsFile.render(list), to: Workspace.projectsFile)
    }

    public func saveWeekLabels(_ labels: WeekLabels) throws {
        if labels.isEmpty && !fm.fileExists(atPath: url(for: Workspace.weekLabelsFile).path) { return }
        try write(labels.renderFile(), to: Workspace.weekLabelsFile)
    }

    /// Writes one month's log file, or removes it (and an emptied year
    /// folder) when the month has no entries.
    public func saveMonth(_ month: MonthKey, entries: [LogEntry]) throws {
        let path = LogFile.relativePath(for: month)
        if entries.isEmpty {
            if protectedFiles.contains(path) { throw WorkspaceError.protected(path) }
            let u = url(for: path)
            if fm.fileExists(atPath: u.path) {
                try fm.removeItem(at: u)
                let folder = u.deletingLastPathComponent()
                if let items = try? fm.contentsOfDirectory(atPath: folder.path), items.allSatisfy({ $0 == ".DS_Store" }) {
                    try? fm.removeItem(at: folder)
                }
            }
            stamps[path] = nil
            return
        }
        try write(LogFile.render(entries), to: path)
    }

    public func isProtected(_ month: MonthKey) -> Bool {
        protectedFiles.contains(LogFile.relativePath(for: month))
    }
}
