import AppKit
import ProgressCore

/// Changing projects, programmes and week labels.
extension AppModel {
    // MARK: Projects

    /// Changes the project list, writes projects.yml (after a pause when
    /// `debounce`), and registers one undo step named `actionName`.
    func updateProjects(actionName: String?, debounce: Bool = false, _ change: (inout ProjectList) -> Void) {
        var list = projectList
        change(&list)
        guard list != projectList else { return }
        replaceProjects(list, actionName: actionName, debounce: debounce)
    }

    /// Replaces the list (and, for Delete Project and its undo, some cells
    /// with it), as one undo step.
    func replaceProjects(_ list: ProjectList, cells: [CellRef: Cell] = [:], actionName: String?,
                         debounce: Bool = false) {
        let previous = projectList
        var previousCells: [CellRef: Cell] = [:]
        for ref in cells.keys { previousCells[ref] = log[ref.project, ref.date] }
        projectList = list
        if !cells.isEmpty { applyCells(cells, actionName: nil) }
        if debounce {
            pendingProjects = true
            scheduleSave()
        } else {
            saveProjectsNow()
        }
        if let name = actionName, let um = undoManager {
            um.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    model.projectSession = nil
                    model.replaceProjects(previous, cells: previousCells, actionName: name)
                }
            }
            um.setActionName(name)
        }
        relayout()
    }

    /// Typing in one of a project's fields in the inspector. One undo step
    /// per field per visit; written after a pause.
    func editProject(_ key: String, field: String, _ change: (inout Project) -> Void) {
        guard let i = projectList.index(of: key) else { return }
        var p = projectList.projects[i]
        change(&p)
        guard p != projectList.projects[i] else { return }
        let session = "\(key)/\(field)"
        let name = projectSession == session ? nil : "Edit Project"
        projectSession = session
        updateProjects(actionName: name, debounce: true) { $0.projects[i] = p }
    }

    func setProjectActive(_ key: String, _ active: Bool) {
        updateProjects(actionName: active ? "Mark Project Active" : "Mark Project Inactive") { list in
            guard let i = list.index(of: key) else { return }
            list.projects[i].isActive = active
        }
    }

    func setProgramme(_ programme: String, for key: String) {
        updateProjects(actionName: "Move to Programme") { list in
            guard let i = list.index(of: key) else { return }
            list.projects[i].programme = programme
        }
    }

    /// Adds a project and selects it on today (or the focused day).
    func addProject(title: String, code: String, programme: String, target: String, collaborators: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, projectList.project(withCode: code) == nil else { return }
        let key = projectList.newKey(for: t)
        let p = Project(key: key, code: code.trimmingCharacters(in: .whitespaces), title: t,
                        programme: programme, target: target.trimmingCharacters(in: .whitespaces),
                        collaborators: collaborators.trimmingCharacters(in: .whitespaces))
        updateProjects(actionName: "New Project") { list in
            // After the last project of the same programme, so the file
            // keeps programmes together.
            if let last = list.projects.lastIndex(where: { list.group(of: $0) == programme }) {
                list.projects.insert(p, at: last + 1)
            } else {
                list.projects.append(p)
            }
        }
        // Make sure the new project is shown.
        if !query.status.includes(p) || (query.programme != nil && query.programme != programme) || !query.search.isEmpty {
            var q = query
            q.status = .active
            q.programme = nil
            q.search = ""
            query = q
        }
        collapsedProgrammes.remove(programme)
        select(CellRef(project: key, date: selection?.focus.date ?? today))
        inspectorTab = .project
    }

    func requestDeleteProject(_ key: String?) {
        guard let key = key ?? focusRef?.project else { return }
        pendingDeletion = .project(key)
    }

    func confirmDelete() {
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil
        switch pending {
        case .project(let key):
            var list = projectList
            list.projects.removeAll { $0.key == key }
            var cells: [CellRef: Cell] = [:]
            for e in log.entries(for: key) { cells[CellRef(project: key, date: e.date)] = Cell() }
            if selection?.focus.project == key || selection?.anchor.project == key { selection = nil }
            replaceProjects(list, cells: cells, actionName: "Delete Project")
        case .programme(let name):
            updateProjects(actionName: "Delete Programme") { list in
                list.programmes.removeAll { $0.name == name }
                for i in list.projects.indices where list.projects[i].programme == name {
                    list.projects[i].programme = ""
                }
            }
        }
    }

    func entryCount(for key: String) -> Int {
        log.entries(for: key).count
    }

    /// Moves the project up or down in the manual order, among the projects
    /// of its own programme when grouped.
    func moveProject(_ key: String?, by offset: Int) {
        guard let key = key ?? focusRef?.project, let target = moveTarget(key, by: offset) else { return }
        updateProjects(actionName: offset < 0 ? "Move Up" : "Move Down") { list in
            guard let from = list.index(of: key) else { return }
            let p = list.projects.remove(at: from)
            list.projects.insert(p, at: target)
        }
        if query.sort != .manual {
            var q = query
            q.sort = .manual
            q.ascending = true
            query = q
        }
    }

    func canMoveProject(_ key: String?, by offset: Int) -> Bool {
        guard let key = key ?? focusRef?.project else { return false }
        return moveTarget(key, by: offset) != nil
    }

    /// The index the project moves to: past the neighbouring project in the
    /// same programme (when grouped) that the filter shows.
    private func moveTarget(_ key: String, by offset: Int) -> Int? {
        let list = projectList
        guard let i = list.index(of: key), let p = list.project(key) else { return nil }
        let group = list.group(of: p)
        let pausedToday = p.isInactive(on: today)
        var j = i + offset
        while j >= 0 && j < list.projects.count {
            let q = list.projects[j]
            // With inactive-today projects clustered last, move within the cluster.
            let sameCluster = !query.inactiveTodayLast || q.isInactive(on: today) == pausedToday
            if (!query.grouped || list.group(of: q) == group) && sameCluster && query.includes(q, in: list) { return j }
            j += offset
        }
        return nil
    }

    // MARK: Inactive periods

    func setPeriodLabel(_ key: String, period id: UUID, label: String) {
        editProject(key, field: "period-\(id)") { p in
            guard let i = p.inactivePeriods.firstIndex(where: { $0.id == id }) else { return }
            p.inactivePeriods[i].label = label
        }
    }

    func setPeriodRange(_ key: String, period id: UUID, from: LocalDate, to: LocalDate) {
        updateProjects(actionName: "Change Inactive Period") { list in
            guard let pi = list.index(of: key),
                  let i = list.projects[pi].inactivePeriods.firstIndex(where: { $0.id == id }) else { return }
            list.projects[pi].inactivePeriods[i].range = DayRange(from: from, to: to)
            list.projects[pi].inactivePeriods = Project.merged(list.projects[pi].inactivePeriods)
        }
    }

    func addPeriod(_ key: String, from: LocalDate) {
        updateProjects(actionName: "Add Inactive Period") { list in
            guard let pi = list.index(of: key) else { return }
            list.projects[pi].inactivePeriods.append(InactivePeriod(range: DayRange(from: from, to: from.adding(days: 6))))
            list.projects[pi].inactivePeriods = Project.merged(list.projects[pi].inactivePeriods)
        }
    }

    func removePeriod(_ key: String, period id: UUID) {
        updateProjects(actionName: "Remove Inactive Period") { list in
            guard let pi = list.index(of: key) else { return }
            list.projects[pi].inactivePeriods.removeAll { $0.id == id }
        }
    }

    // MARK: Programmes

    func newProgramme(assignTo key: String? = nil) {
        activeSheet = .programmeName(ProgrammeNameRequest(original: nil, assignTo: key))
    }

    func renameProgramme(_ name: String) {
        guard !name.isEmpty else { return }
        activeSheet = .programmeName(ProgrammeNameRequest(original: name))
    }

    /// Why `name` cannot be used, or nil if it can.
    func programmeNameProblem(_ name: String, renaming original: String?) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Enter a name." }
        if n == ProjectList.noProgrammeTitle { return "\u{201C}\(n)\u{201D} is reserved." }
        if n != original && projectList.programmeNames.contains(n) { return "There is already a programme called \u{201C}\(n)\u{201D}." }
        return nil
    }

    func commitProgrammeName(_ request: ProgrammeNameRequest, name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard programmeNameProblem(n, renaming: request.original) == nil else { return }
        if let original = request.original {
            guard n != original else { return }
            updateProjects(actionName: "Rename Programme") { list in
                if let i = list.programmes.firstIndex(where: { $0.name == original }) { list.programmes[i].name = n }
                for i in list.projects.indices where list.projects[i].programme == original {
                    list.projects[i].programme = n
                }
            }
            if collapsedProgrammes.contains(original) {
                collapsedProgrammes.remove(original)
                collapsedProgrammes.insert(n)
            }
            if query.programme == original { query.programme = n }
        } else {
            updateProjects(actionName: "New Programme") { list in
                list.programmes.append(Programme(name: n))
                if let key = request.assignTo, let i = list.index(of: key) { list.projects[i].programme = n }
            }
        }
    }

    func requestDeleteProgramme(_ name: String) {
        guard !name.isEmpty else { return }
        pendingDeletion = .programme(name)
    }

    func moveProgramme(_ name: String, by offset: Int) {
        guard let i = projectList.programmes.firstIndex(where: { $0.name == name }) else { return }
        let j = i + offset
        guard j >= 0, j < projectList.programmes.count else { return }
        updateProjects(actionName: offset < 0 ? "Move Programme Up" : "Move Programme Down") { list in
            list.programmes.swapAt(i, j)
        }
    }

    func canMoveProgramme(_ name: String, by offset: Int) -> Bool {
        guard let i = projectList.programmes.firstIndex(where: { $0.name == name }) else { return false }
        return (0..<projectList.programmes.count).contains(i + offset)
    }

    func projectCount(in programme: String) -> Int {
        projectList.projects.filter { projectList.group(of: $0) == programme }.count
    }

    // MARK: Week labels

    func replaceWeekLabels(_ labels: WeekLabels, actionName: String) {
        guard labels != weekLabels else { return }
        let previous = weekLabels
        weekLabels = labels
        saveWeekLabelsNow()
        if let um = undoManager {
            um.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    model.replaceWeekLabels(previous, actionName: actionName)
                }
            }
            um.setActionName(actionName)
        }
        bump()
    }

    func setWeekLabel(_ text: String, for week: LocalDate) {
        var labels = weekLabels
        labels[week] = text
        replaceWeekLabels(labels, actionName: "Edit Week Label")
    }

    /// Applies labels pasted from a spreadsheet, either on top of the
    /// existing ones or instead of them.
    func importWeekLabels(_ imported: [LocalDate: String], replacingAll: Bool) {
        var labels = replacingAll ? WeekLabels() : weekLabels
        for (week, text) in imported { labels[week] = text }
        replaceWeekLabels(labels, actionName: "Import Week Labels")
    }
}
