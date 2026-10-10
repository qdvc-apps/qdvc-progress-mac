import AppKit
import SwiftUI
import ProgressCore

/// A project's cell on a day.
struct CellRef: Hashable {
    let project: String
    let date: LocalDate
}

/// The selected cells: the rectangle between the anchor (where the
/// selection started) and the focus (where it ends; the cell the inspector
/// shows and the arrow keys move).
struct GridSelection: Equatable {
    var anchor: CellRef
    var focus: CellRef
}

/// A request for the grid to scroll a day into view.
struct ScrollTarget: Equatable {
    let id = UUID()
    let date: LocalDate
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case day
    case project

    var id: String { rawValue }
    var title: String { self == .day ? "Day" : "Project" }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// New Programme (nil) or Rename Programme.
struct ProgrammeNameRequest: Identifiable {
    let id = UUID()
    let original: String?
    /// For New Programme from the New Project sheet: nothing else to do.
    var assignTo: String?
}

enum ActiveSheet: Identifiable {
    case newProject(programme: String)
    case programmeName(ProgrammeNameRequest)
    case weekLabels
    case weekLabel(LocalDate)
    case goToDate

    var id: String {
        switch self {
        case .newProject: return "newProject"
        case .programmeName(let r): return "programme-\(r.id)"
        case .weekLabels: return "weekLabels"
        case .weekLabel(let d): return "week-\(d.iso)"
        case .goToDate: return "goToDate"
        }
    }
}

enum PendingDeletion: Identifiable {
    case project(String)
    case programme(String)

    var id: String {
        switch self {
        case .project(let k): return "project-\(k)"
        case .programme(let n): return "programme-\(n)"
        }
    }
}

/// All app state and actions. Every change is written to the workspace
/// straight away, except typing (notes, project fields), which is written
/// after a short pause, and whenever the app is left or quits.
@Observable
@MainActor
final class AppModel {
    // MARK: Workspace contents

    private(set) var workspace: Workspace?
    private(set) var settings = WorkloadSettings()
    var projectList = ProjectList()
    var weekLabels = WeekLabels()
    var log = ProgressLog()
    private(set) var issues: [LoadIssue] = []
    /// The last error writing a file, shown as a banner until dismissed.
    var saveError: String?
    private(set) var recentWorkspaces: [String] = Prefs.recentWorkspaces

    var reopenLast: Bool = Prefs.reopenLast {
        didSet { Prefs.reopenLast = reopenLast }
    }

    // MARK: View state

    var query: ProjectQuery = Prefs.query {
        didSet {
            guard query != oldValue else { return }
            Prefs.query = query
            relayout()
        }
    }
    var collapsedProgrammes: Set<String> = Prefs.collapsedProgrammes {
        didSet { Prefs.collapsedProgrammes = collapsedProgrammes; relayout() }
    }
    var hiddenColumns: Set<LeftColumn> = Prefs.hiddenColumns {
        didSet { Prefs.hiddenColumns = hiddenColumns; bump() }
    }
    var columnWidths: [LeftColumn: Double] = Prefs.columnWidths {
        didSet { Prefs.columnWidths = columnWidths; bump() }
    }
    var cellWidth: Double = Prefs.cellWidth {
        didSet { Prefs.cellWidth = cellWidth; bump() }
    }
    var totalsScope: TotalsScope = Prefs.totalsScope {
        didSet { Prefs.totalsScope = totalsScope; bump() }
    }
    var pasteMode: PasteMode = Prefs.pasteMode {
        didSet { Prefs.pasteMode = pasteMode }
    }
    var showProgrammeSubtotals: Bool = Prefs.showProgrammeSubtotals {
        didSet { Prefs.showProgrammeSubtotals = showProgrammeSubtotals; bump() }
    }
    var isoWeekFallback: Bool = Prefs.isoWeekFallback {
        didSet { Prefs.isoWeekFallback = isoWeekFallback; bump() }
    }
    var inspectorShown: Bool = Prefs.inspectorShown {
        didSet { Prefs.inspectorShown = inspectorShown }
    }
    var inspectorTab: InspectorTab = .day

    var searchText: String {
        get { query.search }
        set { query.search = newValue }
    }

    // MARK: Layout (derived)

    /// Changes whenever anything the grid draws changes; the grid redraws
    /// when it sees a new value.
    private(set) var revision = 0
    private(set) var rows: [GridRow] = []
    /// Projects that pass the filter, in row order (including those in
    /// collapsed programmes).
    private(set) var includedKeys: [String] = []
    @ObservationIgnored private(set) var includedSet: Set<String> = []
    @ObservationIgnored private var rowOfProject: [String: Int] = [:]
    @ObservationIgnored private(set) var groupOfProject: [String: String] = [:]
    var lastWorked: [String: LocalDate] = [:]

    /// The first day of the grid (a Monday) and how many days it shows.
    private(set) var rangeStart: LocalDate
    private(set) var dayCount: Int
    private(set) var today = LocalDate.today()
    var scrollTarget: ScrollTarget?

    // MARK: Selection

    var selection: GridSelection? {
        didSet {
            guard selection != oldValue else { return }
            if selection?.focus != oldValue?.focus { endEditingSessions() }
            bump()
        }
    }

    // MARK: Sheets, alerts, focus

    var activeSheet: ActiveSheet?
    var alert: AlertInfo?
    var pendingDeletion: PendingDeletion?
    /// Set to put the keyboard focus in the inspector's note field; the
    /// inspector clears it when it has done so.
    var noteFocusPending = false
    /// Incremented to put the keyboard focus back in the grid.
    var gridFocusRequest = 0

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var pendingMonths: Set<MonthKey> = []
    @ObservationIgnored var pendingProjects = false
    @ObservationIgnored var saveTask: Task<Void, Never>?
    /// The cell whose note is being typed, and its value before typing began
    /// (one undo step per editing session).
    @ObservationIgnored var noteSession: CellRef?
    /// The project field being typed in ("key/field"), likewise.
    @ObservationIgnored var projectSession: String?

    init() {
        let today = LocalDate.today()
        rangeStart = today.adding(days: -56).monday
        dayCount = 7 * 26
    }

    // MARK: Workspace

    var windowTitle: String {
        workspace?.root.lastPathComponent ?? "QDVC Progress"
    }

    func startUp() {
        guard workspace == nil else { return }
        if reopenLast, let last = Prefs.lastWorkspace, directoryExists(URL(fileURLWithPath: last)) {
            open(URL(fileURLWithPath: last, isDirectory: true))
        }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a progress workspace, or an empty folder to start one."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        let root = url.standardizedFileURL
        guard directoryExists(root) else {
            alert = AlertInfo(title: "Folder Not Found", message: "\(root.path) no longer exists.")
            recentWorkspaces.removeAll { $0 == root.path }
            Prefs.recentWorkspaces = recentWorkspaces
            return
        }
        if !Workspace.looksLikeWorkspace(root) {
            let confirm = NSAlert()
            confirm.messageText = "Start a progress workspace here?"
            confirm.informativeText = "\(root.lastPathComponent) has no progress.yml or projects.yml yet. QDVC Progress will create them, and keep your log in a log folder beside them, as plain text files you can commit to Git."
            confirm.addButton(withTitle: "Create")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        flushSaves()
        let ws = Workspace(root: root)
        do {
            try ws.ensureLayout()
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Open Workspace", message: error.localizedDescription)
            return
        }
        workspace = ws
        undoManager?.removeAllActions()
        selection = nil
        load()
        resetRange()
        selectInitialCell()
        scrollTarget = ScrollTarget(date: today)
        recentWorkspaces.removeAll { $0 == root.path }
        recentWorkspaces.insert(root.path, at: 0)
        Prefs.recentWorkspaces = recentWorkspaces
        recentWorkspaces = Prefs.recentWorkspaces
        Prefs.lastWorkspace = root.path
    }

    func closeWorkspace() {
        flushSaves()
        workspace = nil
        settings = WorkloadSettings()
        projectList = ProjectList()
        weekLabels = WeekLabels()
        log = ProgressLog()
        issues = []
        selection = nil
        undoManager?.removeAllActions()
        Prefs.lastWorkspace = nil
        relayout()
    }

    func clearRecents() {
        recentWorkspaces = []
        Prefs.recentWorkspaces = []
    }

    func revealWorkspace() {
        guard let ws = workspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ws.root])
    }

    func revealIssue(_ issue: LoadIssue) {
        guard let ws = workspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ws.url(for: issue.relativePath)])
    }

    /// Re-reads every file (after editing them elsewhere, or `git pull`).
    func refresh() {
        guard workspace != nil else { return }
        flushSaves()
        load()
        undoManager?.removeAllActions()
    }

    func appBecameActive() {
        dayChanged()
        guard let ws = workspace, ws.hasExternalChanges() else { return }
        refresh()
    }

    func appWillResignActive() {
        flushSaves()
    }

    func dayChanged() {
        let now = LocalDate.today()
        guard now != today else { return }
        today = now
        bump()
    }

    private func load() {
        guard let ws = workspace else { return }
        let c = ws.load()
        settings = c.settings
        projectList = c.projects
        weekLabels = c.weekLabels
        log = c.log
        issues = c.issues
        saveError = nil
        if let s = selection, projectList.project(s.focus.project) == nil { selection = nil }
        extendRangeToCoverLog()
        relayout()
    }

    // MARK: Date range

    func date(at dayIndex: Int) -> LocalDate { rangeStart.adding(days: dayIndex) }
    func dayIndex(of date: LocalDate) -> Int { rangeStart.days(to: date) }
    var rangeEnd: LocalDate { rangeStart.adding(days: dayCount - 1) }

    /// Eight weeks back to six months ahead of today, widened to the log.
    private func resetRange() {
        var start = today.adding(days: -56).monday
        var end = today.adding(days: 182)
        if let bounds = log.dateBounds {
            start = min(start, bounds.from.monday)
            end = max(end, bounds.to)
        }
        rangeStart = start
        dayCount = start.days(to: end.monday) + 7
        bump()
    }

    private func extendRangeToCoverLog() {
        guard let bounds = log.dateBounds else { return }
        if bounds.from < rangeStart { extendEarlier(toInclude: bounds.from) }
        if bounds.to > rangeEnd { extendLater(toInclude: bounds.to) }
    }

    func extendEarlier(weeks: Int = 12) {
        rangeStart = rangeStart.adding(days: -7 * weeks)
        dayCount += 7 * weeks
        bump()
    }

    func extendLater(weeks: Int = 12) {
        dayCount += 7 * weeks
        bump()
    }

    func extendEarlier(toInclude day: LocalDate) {
        guard day < rangeStart else { return }
        let weeks = (day.monday.days(to: rangeStart)) / 7 + 4
        extendEarlier(weeks: weeks)
    }

    func extendLater(toInclude day: LocalDate) {
        guard day > rangeEnd else { return }
        let weeks = (rangeEnd.days(to: day)) / 7 + 4
        extendLater(weeks: weeks)
    }

    func goToToday() {
        dayChanged()
        scrollTarget = ScrollTarget(date: today)
        if let s = selection {
            select(CellRef(project: s.focus.project, date: today))
        } else {
            selectInitialCell()
        }
        gridFocusRequest += 1
    }

    func goTo(_ day: LocalDate) {
        extendEarlier(toInclude: day)
        extendLater(toInclude: day)
        scrollTarget = ScrollTarget(date: day)
        if let s = selection { select(CellRef(project: s.focus.project, date: day)) }
        gridFocusRequest += 1
    }

    /// Scrolls by whole weeks (⌘[ and ⌘]), moving the selection with it.
    func shiftWeeks(_ n: Int) {
        let base = selection?.focus.date ?? today
        let target = base.adding(days: 7 * n)
        goTo(target)
    }

    // MARK: Layout

    func bump() { revision &+= 1 }

    /// Recomputes the rows after a change to the projects or the query.
    func relayout() {
        lastWorked = log.lastWorked()
        let r = RowLayout.rows(for: projectList, query: query, collapsed: collapsedProgrammes, lastWorked: lastWorked)
        rows = r.rows
        includedKeys = r.included
        includedSet = Set(r.included)
        var map: [String: Int] = [:]
        for (i, row) in rows.enumerated() {
            if let key = row.projectKey { map[key] = i }
        }
        rowOfProject = map
        var groups: [String: String] = [:]
        for p in projectList.projects { groups[p.key] = projectList.group(of: p) }
        groupOfProject = groups
        bump()
    }

    func row(of project: String) -> Int? { rowOfProject[project] }

    func project(_ key: String) -> Project? { projectList.project(key) }

    var visibleColumns: [LeftColumn] {
        LeftColumn.allCases.filter { $0 == .title || !hiddenColumns.contains($0) }
    }

    func width(of column: LeftColumn) -> Double {
        columnWidths[column] ?? column.defaultWidth
    }

    func isColumnShown(_ c: LeftColumn) -> Bool { !hiddenColumns.contains(c) }

    func toggleColumn(_ c: LeftColumn) {
        guard c != .title else { return }
        if hiddenColumns.contains(c) { hiddenColumns.remove(c) } else { hiddenColumns.insert(c) }
    }

    func zoom(by step: Double) {
        let next = min(max(cellWidth + step, Prefs.cellWidthRange.lowerBound), Prefs.cellWidthRange.upperBound)
        if next != cellWidth { cellWidth = next }
    }

    func toggleProgramme(_ name: String) {
        if collapsedProgrammes.contains(name) { collapsedProgrammes.remove(name) } else { collapsedProgrammes.insert(name) }
    }

    func setAllProgrammes(collapsed: Bool) {
        collapsedProgrammes = collapsed ? Set(projectList.programmeNames + [""]) : []
    }

    func setSort(_ key: SortKey) {
        if query.sort == key {
            query.ascending.toggle()
        } else {
            var q = query
            q.sort = key
            q.ascending = key.defaultAscending
            query = q
        }
    }

    // MARK: Totals

    /// Whether a project counts in the totals row.
    func countsInTotals(_ key: String) -> Bool {
        totalsScope == .all || includedSet.contains(key)
    }

    func dayTotal(_ date: LocalDate) -> Int {
        log.total(on: date, settings: settings, includes: { self.countsInTotals($0) })
    }

    func programmeTotal(_ programme: String, on date: LocalDate) -> Int {
        log.total(on: date, settings: settings) { key in
            self.includedSet.contains(key) && self.groupOfProject[key] == programme
        }
    }

    func weekLabel(for day: LocalDate) -> (text: String, isCustom: Bool) {
        weekLabels.display(for: day, isoFallback: isoWeekFallback)
    }

    // MARK: Saving

    func reportSaveError(_ error: Error) {
        saveError = String(describing: error)
    }

    func saveMonthsNow(_ months: Set<MonthKey>) {
        guard let ws = workspace else { return }
        for m in months.sorted() {
            pendingMonths.remove(m)
            do { try ws.saveMonth(m, entries: log.entries(in: m)) } catch { reportSaveError(error) }
        }
    }

    func saveProjectsNow() {
        guard let ws = workspace else { return }
        pendingProjects = false
        do { try ws.saveProjects(projectList) } catch { reportSaveError(error) }
    }

    func saveWeekLabelsNow() {
        guard let ws = workspace else { return }
        do { try ws.saveWeekLabels(weekLabels) } catch { reportSaveError(error) }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    /// Writes whatever typing is still waiting to be written.
    func flushSaves() {
        saveTask?.cancel()
        saveTask = nil
        if !pendingMonths.isEmpty { saveMonthsNow(pendingMonths) }
        if pendingProjects { saveProjectsNow() }
    }

    func endEditingSessions() {
        noteSession = nil
        projectSession = nil
        flushSaves()
    }

    // MARK: Settings

    func updateSettings(_ change: (inout WorkloadSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        bump()
        guard let ws = workspace else { return }
        do { try ws.saveSettings(settings) } catch { reportSaveError(error) }
    }
}
