import AppKit
import ProgressCore

/// Selecting cells and changing them: labels, notes, inactive days, copy
/// and paste.
extension AppModel {
    // MARK: Selection

    /// The project rows the selection spans (top to bottom) and its days.
    var selectionBounds: (rows: ClosedRange<Int>, days: ClosedRange<Int>)? {
        guard let s = selection, let r1 = row(of: s.anchor.project), let r2 = row(of: s.focus.project) else {
            return nil
        }
        let d1 = dayIndex(of: s.anchor.date), d2 = dayIndex(of: s.focus.date)
        return (min(r1, r2)...max(r1, r2), min(d1, d2)...max(d1, d2))
    }

    /// Every selected cell, row by row.
    var selectedRefs: [CellRef] {
        guard let b = selectionBounds else { return [] }
        var out: [CellRef] = []
        for r in b.rows {
            guard let key = rows[r].projectKey else { continue }
            for d in b.days { out.append(CellRef(project: key, date: date(at: d))) }
        }
        return out
    }

    /// The selected project rows' keys, top to bottom.
    var selectedProjectKeys: [String] {
        guard let b = selectionBounds else { return [] }
        return b.rows.compactMap { rows[$0].projectKey }
    }

    var focusRef: CellRef? {
        guard let s = selection, row(of: s.focus.project) != nil else { return nil }
        return s.focus
    }

    var focusedProject: Project? {
        focusRef.flatMap { project($0.project) }
    }

    var hasSelection: Bool { focusRef != nil }

    func select(_ ref: CellRef, extend: Bool = false) {
        if extend, let s = selection, row(of: s.anchor.project) != nil {
            selection = GridSelection(anchor: s.anchor, focus: ref)
        } else {
            selection = GridSelection(anchor: ref, focus: ref)
        }
    }

    func selectInitialCell() {
        guard let key = rows.lazy.compactMap(\.projectKey).first else { return }
        select(CellRef(project: key, date: today))
    }

    /// All the shown projects on the days of the current selection (or on
    /// `date`), as when a column heading is clicked.
    func selectColumn(_ date: LocalDate, extend: Bool) {
        let keys = rows.compactMap(\.projectKey)
        guard let first = keys.first, let last = keys.last else { return }
        if extend, let s = selection {
            selection = GridSelection(anchor: CellRef(project: first, date: s.anchor.date),
                                      focus: CellRef(project: last, date: date))
        } else {
            selection = GridSelection(anchor: CellRef(project: first, date: date),
                                      focus: CellRef(project: last, date: date))
        }
    }

    func selectAll() {
        let keys = rows.compactMap(\.projectKey)
        guard let first = keys.first, let last = keys.last else { return }
        selection = GridSelection(anchor: CellRef(project: first, date: rangeStart),
                                  focus: CellRef(project: last, date: rangeEnd))
    }

    func collapseSelection() {
        guard let s = selection else { return }
        selection = GridSelection(anchor: s.focus, focus: s.focus)
    }

    /// Moves the focus by rows (skipping programme headings) and days.
    func moveSelection(rows dRows: Int, days dDays: Int, extend: Bool) {
        guard let focus = focusRef else {
            selectInitialCell()
            return
        }
        let keys = rows.compactMap(\.projectKey)
        guard let i = keys.firstIndex(of: focus.project) else { return }
        let j = min(max(i + dRows, 0), keys.count - 1)
        var day = focus.date.adding(days: dDays)
        if day < rangeStart { extendEarlier(toInclude: day) }
        if day > rangeEnd { extendLater(toInclude: day) }
        day = max(rangeStart, min(day, rangeEnd))
        select(CellRef(project: keys[j], date: day), extend: extend)
    }

    // MARK: Changing cells

    func cell(_ ref: CellRef) -> Cell { log[ref.project, ref.date] }

    /// Writes `changes`, saves the months they touch, and registers one
    /// undo step named `actionName` (none if nil).
    func applyCells(_ changes: [CellRef: Cell], actionName: String?, saveNow: Bool = true) {
        guard !changes.isEmpty else { return }
        var previous: [CellRef: Cell] = [:]
        var months = Set<MonthKey>()
        for (ref, cell) in changes {
            previous[ref] = log[ref.project, ref.date]
            log[ref.project, ref.date] = cell
            months.insert(ref.date.monthKey)
        }
        if saveNow {
            saveMonthsNow(months)
        } else {
            pendingMonths.formUnion(months)
            scheduleSave()
        }
        if let name = actionName, let um = undoManager {
            um.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    model.noteSession = nil
                    model.applyCells(previous, actionName: name)
                }
            }
            um.setActionName(name)
        }
        lastWorked = log.lastWorked()
        bump()
    }

    var focusCell: Cell? { focusRef.map { cell($0) } }

    /// The label shared by every selected cell, or nil if they differ.
    var commonSelectedLabel: CellLabel?? {
        let labels = selectedRefs.map { cell($0).label }
        guard let first = labels.first else { return nil }
        return labels.allSatisfy { $0 == first } ? .some(first) : nil
    }

    func setLabel(_ label: CellLabel?) {
        let refs = selectedRefs
        guard !refs.isEmpty else { return }
        var changes: [CellRef: Cell] = [:]
        for ref in refs {
            var c = cell(ref)
            c.label = label
            changes[ref] = c
        }
        applyCells(changes, actionName: label.map { "Set \($0.title)" } ?? "Clear Label")
    }

    func clearNotes() {
        var changes: [CellRef: Cell] = [:]
        for ref in selectedRefs where cell(ref).hasNote {
            var c = cell(ref)
            c.note = ""
            changes[ref] = c
        }
        applyCells(changes, actionName: "Clear Note")
    }

    func clearCells() {
        var changes: [CellRef: Cell] = [:]
        for ref in selectedRefs where !cell(ref).isEmpty { changes[ref] = Cell() }
        applyCells(changes, actionName: "Clear")
    }

    /// Typing in the inspector's note field. One undo step per cell per
    /// visit; written after a pause.
    func setNote(_ text: String, for ref: CellRef) {
        var c = cell(ref)
        guard c.note != text else { return }
        c.note = text
        if noteSession == ref {
            applyCells([ref: c], actionName: nil, saveNow: false)
        } else {
            noteSession = ref
            applyCells([ref: c], actionName: "Edit Note", saveNow: false)
        }
    }

    // MARK: Inactive days

    /// Whether every selected cell is on an inactive day.
    var selectionIsInactive: Bool {
        let refs = selectedRefs
        guard !refs.isEmpty else { return false }
        return refs.allSatisfy { project($0.project)?.isInactive(on: $0.date) == true }
    }

    func setSelectionInactive(_ inactive: Bool) {
        var byProject: [String: [LocalDate]] = [:]
        for ref in selectedRefs { byProject[ref.project, default: []].append(ref.date) }
        guard !byProject.isEmpty else { return }
        updateProjects(actionName: inactive ? "Mark Inactive" : "Mark Active") { list in
            for (key, days) in byProject {
                guard let i = list.index(of: key) else { continue }
                list.projects[i].setInactive(inactive, on: days)
            }
        }
    }

    func toggleSelectionInactive() {
        setSelectionInactive(!selectionIsInactive)
    }

    // MARK: Copy and paste

    /// The selection as a clip (the rectangle's rows of project cells).
    private var selectionClip: CellClip? {
        guard let b = selectionBounds else { return nil }
        var out: [[Cell]] = []
        for r in b.rows {
            guard let key = rows[r].projectKey else { continue }
            out.append(b.days.map { cell(CellRef(project: key, date: date(at: $0))) })
        }
        return out.isEmpty ? nil : CellClip(rows: out)
    }

    func copySelection() {
        guard let clip = selectionClip else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(clip.json(), forType: NSPasteboard.PasteboardType(CellClip.pasteboardType))
        pb.setString(clip.tsv, forType: .string)
    }

    func cutSelection() {
        copySelection()
        var changes: [CellRef: Cell] = [:]
        for ref in selectedRefs {
            let c = pasteMode.apply(Cell(), onto: cell(ref))
            if c != cell(ref) { changes[ref] = c }
        }
        applyCells(changes, actionName: "Cut")
    }

    var canPaste: Bool {
        guard hasSelection else { return false }
        let pb = NSPasteboard.general
        return pb.availableType(from: [NSPasteboard.PasteboardType(CellClip.pasteboardType), .string]) != nil
    }

    /// Pastes the clipboard at the selection. A single copied cell fills the
    /// whole selection; a block is pasted from the selection's top-left
    /// corner. `mode` (default: the inspector's setting) decides whether
    /// labels, notes or both are written.
    func paste(mode: PasteMode? = nil) {
        let mode = mode ?? pasteMode
        let pb = NSPasteboard.general
        var parsed: CellClip?
        if let data = pb.data(forType: NSPasteboard.PasteboardType(CellClip.pasteboardType)) {
            parsed = CellClip(json: data)
        }
        if parsed == nil, let text = pb.string(forType: .string) { parsed = CellClip(text: text) }
        guard let clip = parsed, let b = selectionBounds else { return }

        var changes: [CellRef: Cell] = [:]
        let projectRows = b.rows.filter { rows[$0].projectKey != nil }
        if clip.isSingleCell {
            let source = clip.cell(row: 0, column: 0)
            for ref in selectedRefs { changes[ref] = mode.apply(source, onto: cell(ref)) }
        } else {
            // From the top-left selected cell, over as many shown project
            // rows and days as the clip has.
            let allKeys = rows.compactMap(\.projectKey)
            guard let firstRow = projectRows.first, let firstKey = rows[firstRow].projectKey,
                  let start = allKeys.firstIndex(of: firstKey) else { return }
            for r in 0..<clip.height {
                guard start + r < allKeys.count else { break }
                let key = allKeys[start + r]
                for c in 0..<clip.width {
                    let day = date(at: b.days.lowerBound + c)
                    if day > rangeEnd { extendLater(toInclude: day) }
                    let ref = CellRef(project: key, date: day)
                    changes[ref] = mode.apply(clip.cell(row: r, column: c), onto: cell(ref))
                }
            }
            if let lastKey = allKeys.dropFirst(start).prefix(clip.height).last {
                let lastDay = date(at: b.days.lowerBound + clip.width - 1)
                selection = GridSelection(anchor: CellRef(project: firstKey, date: date(at: b.days.lowerBound)),
                                          focus: CellRef(project: lastKey, date: lastDay))
            }
        }
        changes = changes.filter { $0.value != cell($0.key) }
        applyCells(changes, actionName: "Paste")
    }
}
