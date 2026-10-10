import AppKit
import ProgressCore

/// The scrolling body of the grid: one cell per project per day. It takes
/// the keyboard focus, so labels can be typed (1–5, m, !, p), arrow keys
/// move, and Copy / Paste / Delete / Select All work from the Edit menu.
@MainActor
final class GridBodyView: NSView, NSMenuItemValidation {
    weak var container: GridContainerView?
    private var model: AppModel? { container?.model }
    private var metrics: GridMetrics { container?.metrics ?? GridMetrics() }

    private var isDragging = false
    private var hoverRef: CellRef?
    /// The tooltip for the hovered cell, kept alive while it is shown (the
    /// view does not retain tooltip owners).
    private var hoverTip: NSString?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let um = window?.undoManager { model?.undoManager = um }
    }

    private var isActive: Bool {
        window?.firstResponder === self && window?.isKeyWindow == true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let m = metrics
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let days = m.days(from: dirtyRect.minX, to: dirtyRect.maxX)
        let rows = m.rows(from: dirtyRect.minY, to: dirtyRect.maxY)
        let top = dirtyRect.minY, height = dirtyRect.height

        // Weekend and today columns.
        let weekendTint = NSColor.labelColor.withAlphaComponent(0.045)
        for d in days {
            let date = model.date(at: d)
            let x = m.dayX(d)
            if date == model.today {
                GridStyle.todayYellow.withAlphaComponent(0.16).setFill()
                NSRect(x: x, y: top, width: m.cellWidth, height: height).fill()
            } else if date.isWeekend {
                weekendTint.setFill()
                NSRect(x: x, y: top, width: m.cellWidth, height: height).fill()
            }
        }

        for r in rows {
            switch model.rows[r] {
            case let .programme(name, _, _):
                drawProgrammeRow(r, name: name, days: days, model: model, m: m)
            case let .project(key):
                if let p = model.project(key) { drawProjectRow(r, project: p, days: days, model: model, m: m) }
            }
        }

        drawGridLines(days: days, rows: rows, dirtyRect: dirtyRect, model: model, m: m)
        drawSelection(model: model, m: m)
    }

    private func drawProgrammeRow(_ r: Int, name: String, days: Range<Int>, model: AppModel, m: GridMetrics) {
        let rowRect = m.rowRect(r, width: m.contentWidth)
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
        NSRect(x: m.dayX(days.lowerBound), y: rowRect.minY,
               width: m.dayX(days.upperBound) - m.dayX(days.lowerBound), height: rowRect.height).fill()
        guard model.showProgrammeSubtotals else { return }
        for d in days {
            let total = model.programmeTotal(name, on: model.date(at: d))
            guard total > 0 else { continue }
            GridStyle.drawCentered("\(total)", in: m.cellRect(row: r, day: d), font: GridStyle.smallFont,
                                   color: .secondaryLabelColor)
        }
    }

    private func drawProjectRow(_ r: Int, project p: Project, days: Range<Int>, model: AppModel, m: GridMetrics) {
        guard !days.isEmpty else { return }
        let firstDay = model.date(at: days.lowerBound), lastDay = model.date(at: days.upperBound - 1)
        let rowRect = m.rowRect(r, width: m.contentWidth)

        // Inactive periods: hatched, with the label across them.
        for period in p.inactivePeriods where period.range.to >= firstDay && period.range.from <= lastDay {
            let from = max(period.range.from, firstDay), to = min(period.range.to, lastDay)
            let x0 = m.dayX(model.dayIndex(of: from)), x1 = m.dayX(model.dayIndex(of: to) + 1)
            let span = NSRect(x: x0, y: rowRect.minY, width: x1 - x0, height: rowRect.height)
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            span.fill()
            GridStyle.hatch(span, color: NSColor.secondaryLabelColor.withAlphaComponent(0.28))
            let label = period.label.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            // One label per fortnight of the period, centred in it, so a
            // long period shows its label wherever it is scrolled to. The
            // positions depend only on the period, so every redraw agrees.
            let chunkDays = 14
            let total = period.range.dayCount
            let chunks = max(1, Int((Double(total) / Double(chunkDays)).rounded()))
            let periodStart = model.dayIndex(of: period.range.from)
            for c in 0..<chunks {
                let c0 = periodStart + c * total / chunks
                let c1 = periodStart + (c + 1) * total / chunks
                let cx0 = m.dayX(c0), cx1 = m.dayX(c1)
                guard cx1 > span.minX, cx0 < span.maxX else { continue }
                let width = min(GridStyle.textWidth(label, font: GridStyle.italicFont) + 12, cx1 - cx0 - 4)
                guard width > 14 else { continue }
                let pill = NSRect(x: (cx0 + cx1 - width) / 2, y: rowRect.minY + 3, width: width,
                                  height: rowRect.height - 6)
                NSColor.textBackgroundColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
                GridStyle.drawLine(label, in: pill.insetBy(dx: 6, dy: 0), font: GridStyle.italicFont,
                                   color: .secondaryLabelColor, alignment: .center)
            }
        }

        let dim = !p.isActive
        for d in days {
            let date = model.date(at: d)
            let cell = model.log[p.key, date]
            guard !cell.isEmpty else { continue }
            let rect = m.cellRect(row: r, day: d)
            if let label = cell.label { drawLabel(label, in: rect, dimmed: dim) }
            if cell.hasNote { drawNoteMarker(in: rect) }
        }
    }

    private func drawLabel(_ label: CellLabel, in rect: NSRect, dimmed: Bool) {
        let chip = rect.insetBy(dx: 1.5, dy: 2)
        let path = NSBezierPath(roundedRect: chip, xRadius: 3, yRadius: 3)
        if let fill = GridStyle.fill(for: label) {
            (dimmed ? fill.withAlphaComponent(0.45) : fill).setFill()
            path.fill()
        } else if label == .planned {
            let stroke = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            stroke.lineWidth = 1
            stroke.setLineDash([3, 2], count: 2, phase: 0)
            GridStyle.plannedStroke.setStroke()
            stroke.stroke()
        }
        let color = GridStyle.text(for: label)
        let font = metrics.cellWidth < 27 && label.text.count > 2
            ? NSFont.systemFont(ofSize: 9, weight: .semibold) : GridStyle.labelFont
        GridStyle.drawCentered(label.text, in: chip, font: font, color: dimmed ? color.withAlphaComponent(0.6) : color)
    }

    private func drawNoteMarker(in rect: NSRect) {
        let s: CGFloat = 7
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.maxX - s, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + s))
        path.close()
        GridStyle.noteMarker.setFill()
        path.fill()
    }

    private func drawGridLines(days: Range<Int>, rows: Range<Int>, dirtyRect: NSRect, model: AppModel, m: GridMetrics) {
        let minor = NSColor.separatorColor.withAlphaComponent(0.35)
        let major = NSColor.separatorColor
        let bottom = min(dirtyRect.maxY, m.contentHeight)
        for d in days {
            let x = m.dayX(d)
            (model.date(at: d).isoWeekday == 1 ? major : minor).setFill()
            NSRect(x: x, y: dirtyRect.minY, width: model.date(at: d).isoWeekday == 1 ? 1 : 0.5,
                   height: max(0, bottom - dirtyRect.minY)).fill()
        }
        for r in rows {
            let y = m.rowTops[r + 1]
            if case .programme = model.rows[r] { major.setFill() } else { minor.setFill() }
            NSRect(x: dirtyRect.minX, y: y - 0.5, width: dirtyRect.width, height: 0.5).fill()
        }
    }

    private func drawSelection(model: AppModel, m: GridMetrics) {
        guard let b = model.selectionBounds else { return }
        let accent = isActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        let x0 = m.dayX(b.days.lowerBound), x1 = m.dayX(b.days.upperBound + 1)
        let y0 = m.rowTops[b.rows.lowerBound], y1 = m.rowTops[b.rows.upperBound + 1]
        let rect = NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        let single = b.days.count == 1 && b.rows.count == 1
        if !single {
            accent.withAlphaComponent(0.14).setFill()
            rect.fill()
        }
        let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        accent.setStroke()
        border.stroke()
        if !single, let f = model.focusRef, let fr = model.row(of: f.project) {
            let fRect = m.cellRect(row: fr, day: model.dayIndex(of: f.date)).insetBy(dx: 2.5, dy: 2.5)
            let p = NSBezierPath(rect: fRect)
            p.lineWidth = 1
            accent.setStroke()
            p.stroke()
        }
    }

    // MARK: Mouse

    private func cellRef(at point: NSPoint) -> CellRef? {
        guard let model, let r = metrics.row(at: point.y), let d = metrics.day(at: point.x),
              r < model.rows.count, let key = model.rows[r].projectKey else { return nil }
        return CellRef(project: key, date: model.date(at: d))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let ref = cellRef(at: p) else {
            // A programme heading: open or close it.
            if let r = metrics.row(at: p.y), r < model.rows.count, case let .programme(name, _, _) = model.rows[r] {
                model.toggleProgramme(name)
            }
            return
        }
        if event.clickCount == 2 {
            model.select(ref)
            editNote()
            return
        }
        model.select(ref, extend: event.modifierFlags.contains(.shift))
        container?.reloadIfNeeded()
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let model else { return }
        _ = autoscroll(with: event)
        let p = convert(event.locationInWindow, from: nil)
        let clamped = NSPoint(x: min(max(p.x, 0), metrics.contentWidth - 1), y: min(max(p.y, 0), metrics.contentHeight - 1))
        if let ref = cellRef(at: clamped), ref != model.selection?.focus {
            model.select(ref, extend: true)
            container?.reloadIfNeeded()
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    // MARK: Tooltips

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hovered = cellRef(at: p)
        guard hovered != hoverRef else { return }
        hoverRef = hovered
        removeAllToolTips()
        hoverTip = nil
        guard let ref = hovered, let model, let row = model.row(of: ref.project) else { return }
        let cell = model.cell(ref)
        let project = model.project(ref.project)
        var lines: [String] = []
        if let period = project?.inactivePeriod(on: ref.date) {
            let label = period.label.isEmpty ? "Inactive" : "Inactive: \(period.label)"
            lines.append("\(label) (\(GridStyle.range(period.range)))")
        }
        if cell.hasNote { lines.append(cell.note) }
        guard !lines.isEmpty else { return }
        let title = "\(project?.title ?? ref.project) \u{00B7} \(GridStyle.longDay(ref.date))"
            + (cell.label.map { " \u{00B7} \($0.text)" } ?? "")
        let tip = ([title] + lines).joined(separator: "\n") as NSString
        hoverTip = tip
        _ = addToolTip(metrics.cellRect(row: row, day: model.dayIndex(of: ref.date)), owner: tip, userData: nil)
    }

    override func mouseExited(with event: NSEvent) {
        hoverRef = nil
        removeAllToolTips()
        hoverTip = nil
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let model else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        if event.keyCode == 53 {   // Escape
            model.collapseSelection()
            return
        }
        if let special = event.specialKey {
            switch special {
            case .leftArrow: move(rows: 0, days: option ? -7 : -1, extend: shift)
            case .rightArrow: move(rows: 0, days: option ? 7 : 1, extend: shift)
            case .upArrow: move(rows: -1, days: 0, extend: shift)
            case .downArrow: move(rows: 1, days: 0, extend: shift)
            case .tab: move(rows: 0, days: 1, extend: false)
            case .backTab: move(rows: 0, days: -1, extend: false)
            case .pageUp: move(rows: -visibleRowCount, days: 0, extend: shift)
            case .pageDown: move(rows: visibleRowCount, days: 0, extend: shift)
            case .carriageReturn, .enter, .newline: editNote()
            case .delete, .deleteForward, .backspace: model.setLabel(nil)
            default: super.keyDown(with: event)
            }
            return
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }
        if let label = CellLabel.allCases.first(where: { $0.key == ch }) {
            model.setLabel(label)
        } else if ch == "0" {
            model.setLabel(nil)
        } else if ch == "i" {
            model.toggleSelectionInactive()
        } else if ch == " " {
            model.inspectorShown.toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    private var visibleRowCount: Int {
        max(1, Int(visibleRect.height / GridMetrics.rowHeight) - 1)
    }

    private func move(rows: Int, days: Int, extend: Bool) {
        model?.moveSelection(rows: rows, days: days, extend: extend)
        container?.reloadIfNeeded()
        container?.revealFocus()
    }

    /// Opens the inspector on the Day tab with the note field focused.
    func editNote() {
        guard let model, model.hasSelection else { return }
        model.collapseSelection()
        model.inspectorShown = true
        model.inspectorTab = .day
        model.noteFocusPending = true
    }

    // MARK: Edit menu

    @objc func copy(_ sender: Any?) { model?.copySelection() }
    @objc func cut(_ sender: Any?) { model?.cutSelection() }
    @objc func paste(_ sender: Any?) { model?.paste() }
    @objc func delete(_ sender: Any?) { model?.setLabel(nil) }
    @objc override func selectAll(_ sender: Any?) { model?.selectAll() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let model else { return false }
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return model.hasSelection
        case #selector(paste(_:)):
            return model.canPaste
        case #selector(selectAll(_:)):
            return !model.rows.isEmpty
        default:
            return true
        }
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        guard let ref = cellRef(at: p) else { return nil }
        window?.makeFirstResponder(self)
        if !model.selectedRefs.contains(ref) { model.select(ref) }
        return GridMenus.cellMenu(model: model, onEditNote: { [weak self] in self?.editNote() })
    }
}
