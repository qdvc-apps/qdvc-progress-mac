import AppKit
import ProgressCore

/// The grid's context menus. Each mirrors commands in the menu bar.
@MainActor
enum GridMenus {
    /// Right-click on day cells.
    static func cellMenu(model: AppModel, onEditNote: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu.manual()
        let common = model.commonSelectedLabel
        for label in CellLabel.sizes {
            menu.add(ActionMenuItem("\(label.text)  \u{2014} \(label.title)", key: String(label.key),
                                    checked: common == .some(label)) { model.setLabel(label) })
        }
        menu.separator()
        for label in CellLabel.specials {
            let title = label.isEmblem ? label.title : "\(label.text)  \u{2014} \(label.title)"
            let item = ActionMenuItem(title, key: String(label.key), checked: common == .some(label)) {
                model.setLabel(label)
            }
            if label.isEmblem { item.image = GridStyle.emblemImage(label, size: 13) }
            menu.add(item)
        }
        menu.add(ActionMenuItem("Clear Label", key: "0") { model.setLabel(nil) })
        menu.separator()
        let single = model.selectedRefs.count == 1
        menu.add(ActionMenuItem(model.focusCell?.hasNote == true ? "Edit Note\u{2026}" : "Add Note\u{2026}",
                                key: "\r", enabled: single, handler: onEditNote))
        menu.add(ActionMenuItem("Clear Note", enabled: model.selectedRefs.contains { model.cell($0).hasNote }) {
            model.clearNotes()
        })
        menu.separator()
        let inactive = model.selectionIsInactive
        menu.add(ActionMenuItem(inactive ? "Mark Days Active" : "Mark Days Inactive", key: "i") {
            model.setSelectionInactive(!inactive)
        })
        menu.separator()
        menu.add(ActionMenuItem("Cut") { model.cutSelection() })
        menu.add(ActionMenuItem("Copy") { model.copySelection() })
        menu.add(ActionMenuItem("Paste (\(model.pasteMode.title))", enabled: model.canPaste) { model.paste() })
        menu.submenu("Paste Special") { sub in
            for mode in PasteMode.allCases {
                sub.add(ActionMenuItem(mode.title, enabled: model.canPaste) { model.paste(mode: mode) })
            }
        }
        if let key = model.focusRef?.project {
            menu.separator()
            menu.submenu("Project") { sub in
                addProjectItems(to: sub, key: key, model: model)
            }
        }
        return menu
    }

    /// Right-click on a project's columns.
    static func projectMenu(model: AppModel, key: String) -> NSMenu {
        let menu = NSMenu.manual()
        addProjectItems(to: menu, key: key, model: model)
        return menu
    }

    static func addProjectItems(to menu: NSMenu, key: String, model: AppModel) {
        guard let p = model.project(key) else { return }
        menu.add(ActionMenuItem("Show in Inspector") {
            model.inspectorShown = true
            model.inspectorTab = .project
        })
        menu.add(ActionMenuItem(p.isActive ? "Mark Project Inactive" : "Mark Project Active") {
            model.setProjectActive(key, !p.isActive)
        })
        menu.submenu("Move to Programme") { sub in
            for name in model.projectList.programmeNames + [""] {
                let title = name.isEmpty ? ProjectList.noProgrammeTitle : name
                sub.add(ActionMenuItem(title, checked: model.projectList.group(of: p) == name) {
                    model.setProgramme(name, for: key)
                })
            }
            sub.separator()
            sub.add(ActionMenuItem("New Programme\u{2026}") { model.newProgramme(assignTo: key) })
        }
        menu.separator()
        menu.add(ActionMenuItem("Move Up", enabled: model.canMoveProject(key, by: -1)) { model.moveProject(key, by: -1) })
        menu.add(ActionMenuItem("Move Down", enabled: model.canMoveProject(key, by: 1)) { model.moveProject(key, by: 1) })
        menu.separator()
        menu.add(ActionMenuItem("Delete Project\u{2026}") { model.requestDeleteProject(key) })
    }

    /// Right-click on a programme heading.
    static func programmeMenu(model: AppModel, name: String) -> NSMenu {
        let menu = NSMenu.manual()
        let collapsed = model.collapsedProgrammes.contains(name)
        menu.add(ActionMenuItem(collapsed ? "Expand" : "Collapse") { model.toggleProgramme(name) })
        menu.add(ActionMenuItem("Expand All") { model.setAllProgrammes(collapsed: false) })
        menu.add(ActionMenuItem("Collapse All") { model.setAllProgrammes(collapsed: true) })
        menu.separator()
        menu.add(ActionMenuItem("New Project in \u{201C}\(name.isEmpty ? ProjectList.noProgrammeTitle : name)\u{201D}\u{2026}") {
            model.activeSheet = .newProject(programme: name)
        })
        menu.add(ActionMenuItem("Show Only This Programme") { model.query.programme = name })
        guard !name.isEmpty else { return menu }
        menu.separator()
        menu.add(ActionMenuItem("Rename Programme\u{2026}") { model.renameProgramme(name) })
        menu.add(ActionMenuItem("Move Programme Up", enabled: model.canMoveProgramme(name, by: -1)) {
            model.moveProgramme(name, by: -1)
        })
        menu.add(ActionMenuItem("Move Programme Down", enabled: model.canMoveProgramme(name, by: 1)) {
            model.moveProgramme(name, by: 1)
        })
        menu.separator()
        menu.add(ActionMenuItem("Delete Programme\u{2026}") { model.requestDeleteProgramme(name) })
        return menu
    }

    /// Right-click on the week-label row.
    static func weekMenu(model: AppModel, week: LocalDate) -> NSMenu {
        let menu = NSMenu.manual()
        menu.add(ActionMenuItem("Edit Label for Week of \(GridStyle.shortDay(week))\u{2026}") {
            model.activeSheet = .weekLabel(week)
        })
        menu.add(ActionMenuItem("Edit All Week Labels\u{2026}") { model.activeSheet = .weekLabels })
        menu.separator()
        menu.add(ActionMenuItem("Show Week Numbers for Unlabelled Weeks", checked: model.isoWeekFallback) {
            model.isoWeekFallback.toggle()
        })
        return menu
    }

    /// Right-click (or click) on the totals labels.
    static func totalsMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu.manual()
        let header = NSMenuItem(title: "Totals Add Up", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.add(header)
        for scope in TotalsScope.allCases {
            menu.add(ActionMenuItem(scope.title, checked: model.totalsScope == scope) { model.totalsScope = scope })
        }
        menu.separator()
        menu.add(ActionMenuItem("Workload Settings\u{2026}") { Platform.openSettings() })
        return menu
    }
}
