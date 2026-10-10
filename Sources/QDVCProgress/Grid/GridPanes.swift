import AppKit
import ProgressCore

// MARK: - Header

/// The date header above the body: month and year, the week label, the day
/// of the month and the day of the week. Today is highlighted in yellow.
@MainActor
final class GridHeaderView: GridPaneView {
    var offsetX: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let m = metrics
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let days = m.days(from: offsetX, to: offsetX + bounds.width)
        guard !days.isEmpty else { return }
        let rowY = (0..<4).map { GridMetrics.headerTop($0) }
        let rowH = GridMetrics.headerRows
        func x(_ d: Int) -> CGFloat { m.dayX(d) - offsetX }

        // Days: weekend tint, today, numbers and letters.
        for d in days {
            let date = model.date(at: d)
            let cellX = x(d)
            let dayRect = NSRect(x: cellX, y: rowY[2], width: m.cellWidth, height: rowH[2] + rowH[3])
            let isToday = date == model.today
            if isToday {
                GridStyle.todayYellow.setFill()
                dayRect.fill()
            } else if date.isWeekend {
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                dayRect.fill()
            }
            let textColor: NSColor = isToday ? NSColor(hex: 0x1A1A1A) : (date.isWeekend ? .secondaryLabelColor : .labelColor)
            GridStyle.drawCentered("\(date.day)", in: NSRect(x: cellX, y: rowY[2], width: m.cellWidth, height: rowH[2]),
                                   font: isToday ? GridStyle.headerBoldFont : GridStyle.headerFont, color: textColor)
            GridStyle.drawCentered(GridStyle.weekdayLetters[date.isoWeekday - 1],
                                   in: NSRect(x: cellX, y: rowY[3], width: m.cellWidth, height: rowH[3]),
                                   font: isToday ? GridStyle.headerBoldFont : GridStyle.headerFont,
                                   color: isToday ? textColor : .secondaryLabelColor)
        }

        // Months: the name sticks to the left edge while its month is shown.
        var d = days.lowerBound
        while d < days.upperBound {
            let date = model.date(at: d)
            let monthEnd = min(days.upperBound, model.dayIndex(of: date.monthKey.lastDay) + 1)
            let monthStart = model.dayIndex(of: date.monthKey.firstDay)
            let x0 = max(0, x(monthStart)), x1 = x(monthEnd)
            let title = GridStyle.monthTitle(date.monthKey)
            GridStyle.drawLine(title, in: NSRect(x: x0 + 6, y: rowY[0], width: x1 - x0 - 8, height: rowH[0]),
                               font: GridStyle.monthFont, color: .labelColor)
            if monthStart >= days.lowerBound {
                NSColor.separatorColor.setFill()
                NSRect(x: x(monthStart), y: rowY[0], width: 1, height: rowH[0]).fill()
            }
            d = monthEnd
        }

        // Weeks: the custom label (or the ISO week number) across Mon–Sun.
        var w = model.dayIndex(of: model.date(at: days.lowerBound).monday)
        while w < days.upperBound {
            let monday = model.date(at: w)
            let label = model.weekLabel(for: monday)
            let rect = NSRect(x: x(w), y: rowY[1], width: 7 * m.cellWidth, height: rowH[1])
            if label.isCustom {
                NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
                rect.insetBy(dx: 1.5, dy: 2).fill()
            }
            let visible = NSRect(x: max(rect.minX, 0), y: rect.minY, width: rect.maxX - max(rect.minX, 0), height: rect.height)
            GridStyle.drawLine(label.text, in: visible.insetBy(dx: 5, dy: 0),
                               font: label.isCustom ? GridStyle.headerBoldFont : GridStyle.headerFont,
                               color: label.isCustom ? .labelColor : .tertiaryLabelColor)
            NSColor.separatorColor.setFill()
            NSRect(x: x(w), y: rowY[1], width: 1, height: rowH[1] + rowH[2] + rowH[3]).fill()
            w += 7
        }

        // Lines between the header rows and under the header.
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        for i in 1..<4 { NSRect(x: 0, y: rowY[i] - 0.5, width: bounds.width, height: 0.5).fill() }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func hit(_ event: NSEvent) -> (row: Int, day: Int)? {
        guard let model else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        guard let day = metrics.day(at: p.x + offsetX), day < model.dayCount else { return nil }
        let row = (0..<4).last { GridMetrics.headerTop($0) <= p.y } ?? 0
        return (row, day)
    }

    override func mouseDown(with event: NSEvent) {
        focusGrid()
        guard let model, let h = hit(event) else { return }
        let date = model.date(at: h.day)
        switch h.row {
        case 1:
            if event.clickCount == 2 {
                model.activeSheet = .weekLabel(date.monday)
            } else {
                // The whole week, for every project shown.
                model.selectColumn(date.monday, extend: false)
                model.selectColumn(date.monday.adding(days: 6), extend: true)
            }
        case 2, 3:
            model.selectColumn(date, extend: event.modifierFlags.contains(.shift))
        default:
            break
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let h = hit(event) else { return nil }
        return GridMenus.weekMenu(model: model, week: model.date(at: h.day).monday)
    }
}

// MARK: - Left columns

/// The project columns on the left: ID, title, target and collaborators,
/// and the programme headings.
@MainActor
final class GridLeftView: GridPaneView {
    var offsetY: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let m = metrics
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let rows = m.rows(from: offsetY, to: offsetY + bounds.height)
        let selectedRows = model.selectionBounds?.rows
        let focusRow = model.focusRef.flatMap { model.row(of: $0.project) }

        for r in rows {
            let y = m.rowTops[r] - offsetY
            let h = m.rowTops[r + 1] - m.rowTops[r]
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: h)
            switch model.rows[r] {
            case let .programme(name, count, collapsed):
                NSColor.windowBackgroundColor.setFill()
                rowRect.fill()
                let chevron = collapsed ? "\u{25B8}" : "\u{25BE}"
                GridStyle.drawLine(chevron, in: NSRect(x: 6, y: y, width: 14, height: h),
                                   font: GridStyle.rowFont, color: .secondaryLabelColor)
                let title = name.isEmpty ? ProjectList.noProgrammeTitle : name
                let titleWidth = min(GridStyle.textWidth(title, font: GridStyle.programmeFont), bounds.width - 70)
                GridStyle.drawLine(title, in: NSRect(x: 22, y: y, width: titleWidth + 2, height: h),
                                   font: GridStyle.programmeFont, color: .labelColor)
                GridStyle.drawLine("\(count)", in: NSRect(x: 28 + titleWidth, y: y, width: 40, height: h),
                                   font: GridStyle.rowSecondaryFont, color: .secondaryLabelColor)
                NSColor.separatorColor.setFill()
                NSRect(x: 0, y: y + h - 0.5, width: bounds.width, height: 0.5).fill()
            case let .project(key):
                guard let p = model.project(key) else { continue }
                if r == focusRow {
                    NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                    rowRect.fill()
                } else if let sel = selectedRows, sel.contains(r) {
                    NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
                    rowRect.fill()
                }
                for col in m.columns {
                    let cellRect = NSRect(x: col.x + 6, y: y, width: col.width - 10, height: h)
                    switch col.column {
                    case .code:
                        GridStyle.drawLine(p.code, in: cellRect, font: GridStyle.codeFont, color: .secondaryLabelColor)
                    case .title:
                        let indent: CGFloat = model.query.grouped ? 14 : 0
                        let r2 = NSRect(x: cellRect.minX + indent, y: y, width: cellRect.width - indent, height: h)
                        GridStyle.drawLine(p.title, in: r2,
                                           font: p.isActive ? GridStyle.rowFont : GridStyle.italicRowFont,
                                           color: p.isActive ? .labelColor : .secondaryLabelColor)
                    case .target:
                        GridStyle.drawLine(p.target, in: cellRect, font: GridStyle.rowSecondaryFont, color: .secondaryLabelColor)
                    case .collaborators:
                        GridStyle.drawLine(p.collaborators, in: cellRect, font: GridStyle.rowSecondaryFont,
                                           color: .secondaryLabelColor)
                    }
                }
                NSColor.separatorColor.withAlphaComponent(0.35).setFill()
                NSRect(x: 0, y: y + h - 0.5, width: bounds.width, height: 0.5).fill()
            }
        }
        drawColumnLines(m: m, height: min(bounds.height, m.contentHeight - offsetY))
    }

    private func drawColumnLines(m: GridMetrics, height: CGFloat) {
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        for col in m.columns.dropLast() {
            NSRect(x: col.x + col.width - 0.5, y: 0, width: 0.5, height: max(0, height)).fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    private func row(for event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return metrics.row(at: p.y + offsetY)
    }

    override func mouseDown(with event: NSEvent) {
        focusGrid()
        guard let model, let r = row(for: event), r < model.rows.count else { return }
        switch model.rows[r] {
        case let .programme(name, _, _):
            model.toggleProgramme(name)
        case let .project(key):
            let date = model.selection?.focus.date ?? model.today
            if event.modifierFlags.contains(.shift), let s = model.selection {
                // Extend over whole rows for the selection's days.
                model.selection = GridSelection(anchor: s.anchor, focus: CellRef(project: key, date: s.focus.date))
            } else {
                model.select(CellRef(project: key, date: date))
            }
            model.inspectorTab = .project
            if event.clickCount == 2 { model.inspectorShown = true }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let r = row(for: event), r < model.rows.count else { return nil }
        switch model.rows[r] {
        case let .programme(name, _, _):
            return GridMenus.programmeMenu(model: model, name: name)
        case let .project(key):
            if model.selection?.focus.project != key {
                model.select(CellRef(project: key, date: model.selection?.focus.date ?? model.today))
            }
            return GridMenus.projectMenu(model: model, key: key)
        }
    }
}

// MARK: - Corner (column headings)

/// Above the project columns: their headings, which sort the projects when
/// clicked and resize the columns when their edges are dragged.
@MainActor
final class GridCornerView: GridPaneView {
    private var resizing: (column: LeftColumn, startX: CGFloat, startWidth: Double)?

    private var headingRect: NSRect {
        let top = GridMetrics.headerTop(2)
        return NSRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // A summary of what is shown.
        let shown = model.includedKeys.count
        let total = model.projectList.projects.count
        let summary = shown == total ? "\(total) project\(total == 1 ? "" : "s")" : "\(shown) of \(total) projects"
        GridStyle.drawLine(summary, in: NSRect(x: 8, y: 2, width: bounds.width - 16, height: GridMetrics.headerRows[0]),
                           font: GridStyle.rowSecondaryFont, color: .secondaryLabelColor)
        GridStyle.drawLine("Today: \(GridStyle.longDay(model.today))",
                           in: NSRect(x: 8, y: GridMetrics.headerTop(1), width: bounds.width - 16,
                                      height: GridMetrics.headerRows[1]),
                           font: GridStyle.rowSecondaryFont, color: .tertiaryLabelColor)

        let h = headingRect
        for col in metrics.columns {
            var title = col.column.title
            if model.query.sort == col.column.sortKey {
                title += model.query.ascending ? " \u{25B2}" : " \u{25BC}"
            }
            GridStyle.drawLine(title, in: NSRect(x: col.x + 6, y: h.minY, width: col.width - 10, height: h.height),
                               font: GridStyle.headerBoldFont, color: .secondaryLabelColor)
            NSColor.separatorColor.setFill()
            NSRect(x: col.x + col.width - 1, y: h.minY + 4, width: 1, height: h.height - 8).fill()
        }
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: h.minY - 0.5, width: bounds.width, height: 0.5).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    override func resetCursorRects() {
        for col in metrics.columns {
            addCursorRect(NSRect(x: col.x + col.width - 3, y: headingRect.minY, width: 6, height: headingRect.height),
                          cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let model, headingRect.contains(p) else {
            if let model, p.y < GridMetrics.headerTop(2) { model.goToToday() }
            return
        }
        if let col = metrics.columnDivider(near: p.x) {
            resizing = (column: col, startX: p.x, startWidth: model.width(of: col))
            return
        }
        if let col = metrics.column(at: p.x) {
            model.setSort(col.sortKey)
        }
        focusGrid()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let r = resizing, let model else { return }
        let p = convert(event.locationInWindow, from: nil)
        let w = max(r.column.minWidth, min(600, r.startWidth + Double(p.x - r.startX)))
        model.columnWidths[r.column] = w
        container?.reloadIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        resizing = nil
        window?.invalidateCursorRects(for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let menu = NSMenu.manual()
        for col in LeftColumn.allCases where col != .title {
            menu.add(ActionMenuItem(col.title, checked: model.isColumnShown(col)) { model.toggleColumn(col) })
        }
        menu.separator()
        menu.add(ActionMenuItem("Reset Column Widths") {
            var widths: [LeftColumn: Double] = [:]
            for c in LeftColumn.allCases { widths[c] = c.defaultWidth }
            model.columnWidths = widths
        })
        return menu
    }
}

// MARK: - Footer (totals)

/// The totals under the body: each day's workload, and each working week's
/// (Monday–Friday) and weekend's, as a salmon-to-red heat map.
@MainActor
final class GridFooterView: GridPaneView {
    var offsetX: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let m = metrics
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let days = m.days(from: offsetX, to: offsetX + bounds.width)
        let row0 = GridMetrics.footerRows[0], row1 = GridMetrics.footerRows[1]
        func x(_ d: Int) -> CGFloat { m.dayX(d) - offsetX }
        let peak = model.settings.dayPeak

        for d in days {
            let date = model.date(at: d)
            let t = model.dayTotal(date)
            let rect = NSRect(x: x(d), y: 0, width: m.cellWidth, height: row0).insetBy(dx: 1, dy: 2)
            let level = heatLevel(t, peak: peak)
            if let fill = GridStyle.totalFill(level: level) {
                fill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                GridStyle.drawCentered("\(t)", in: rect, font: GridStyle.totalFont, color: GridStyle.totalText(level: level))
            }
            if date == model.today {
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 3, yRadius: 3)
                ring.lineWidth = 2
                GridStyle.todayYellow.setStroke()
                ring.stroke()
            }
        }

        // Week and weekend spans (summed over all their days, even those
        // scrolled out of view).
        guard !days.isEmpty else { return }
        var w = model.dayIndex(of: model.date(at: days.lowerBound).monday)
        while w < days.upperBound {
            let monday = model.date(at: w)
            let weekdays = model.log.total(over: DayRange(from: monday, to: monday.adding(days: 4)),
                                           settings: model.settings, includes: { model.countsInTotals($0) })
            let weekend = model.log.total(over: DayRange(from: monday.adding(days: 5), to: monday.adding(days: 6)),
                                          settings: model.settings, includes: { model.countsInTotals($0) })
            drawSpan(weekdays, peak: model.settings.weekPeak,
                     rect: NSRect(x: x(w), y: row0, width: 5 * m.cellWidth, height: row1))
            drawSpan(weekend, peak: model.settings.weekendPeak,
                     rect: NSRect(x: x(w + 5), y: row0, width: 2 * m.cellWidth, height: row1))
            w += 7
        }

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    private func drawSpan(_ total: Int, peak: Int, rect: NSRect) {
        let r = rect.insetBy(dx: 1, dy: 2)
        let level = heatLevel(total, peak: peak)
        if let fill = GridStyle.totalFill(level: level) {
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            GridStyle.drawCentered("\(total)", in: r, font: GridStyle.totalFont, color: GridStyle.totalText(level: level))
        } else {
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            p.lineWidth = 1
            NSColor.separatorColor.setStroke()
            p.stroke()
            GridStyle.drawCentered("0", in: r, font: GridStyle.smallFont, color: .tertiaryLabelColor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        focusGrid()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        return GridMenus.totalsMenu(model: model)
    }
}

/// Beside the totals: what the two rows are, and which projects they add up.
@MainActor
final class GridFooterCornerView: GridPaneView {
    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let row0 = GridMetrics.footerRows[0], row1 = GridMetrics.footerRows[1]
        let scope = model.totalsScope == .visible ? "shown" : "all"
        GridStyle.drawLine("Daily total (\(scope)) \u{25BE}", in: NSRect(x: 8, y: 0, width: bounds.width - 16, height: row0),
                           font: GridStyle.headerBoldFont, color: .secondaryLabelColor, alignment: .right)
        GridStyle.drawLine("Mon\u{2013}Fri \u{00B7} weekend", in: NSRect(x: 8, y: row0, width: bounds.width - 16, height: row1),
                           font: GridStyle.headerFont, color: .secondaryLabelColor, alignment: .right)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let menu = GridMenus.totalsMenu(model: model)
        _ = menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        return GridMenus.totalsMenu(model: model)
    }
}
