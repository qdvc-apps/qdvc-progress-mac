import AppKit
import SwiftUI
import ProgressCore

/// Menu-bar commands. Standard items (Undo, Cut, Copy, Paste, Select All,
/// Window, Settings…, Quit) come from the system and act on the grid when it
/// has the keyboard focus; these add the workspace, view, day and project
/// commands (docs/DESIGN.md §5).
@MainActor
struct ProgressCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project\u{2026}") {
                model.activeSheet = .newProject(programme: model.focusedProject.map { model.projectList.group(of: $0) }
                                                    ?? model.query.programme ?? "")
            }
            .keyboardShortcut("n")
            .disabled(model.workspace == nil)
            Button("New Programme\u{2026}") { model.newProgramme() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
            Divider()
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { path in
                    Button((path as NSString).abbreviatingWithTildeInPath) {
                        model.open(URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            Button("Reveal Workspace in Finder") { model.revealWorkspace() }
                .disabled(model.workspace == nil)
            Divider()
            Button("Week Labels\u{2026}") { model.activeSheet = .weekLabels }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(model.workspace == nil)
            Divider()
            Button("Close Workspace") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
        }

        CommandGroup(after: .pasteboard) {
            Menu("Paste Special") {
                ForEach(PasteMode.allCases) { mode in
                    Button(mode.title) { model.paste(mode: mode) }
                }
            }
            .disabled(!model.hasSelection)
            Divider()
            Button("Find Projects") {
                Platform.focusSearchField(in: NSApp.keyWindow ?? NSApp.mainWindow)
            }
            .keyboardShortcut("f")
            .disabled(model.workspace == nil)
        }

        CommandGroup(after: .toolbar) {
            Button(model.inspectorShown ? "Hide Inspector" : "Show Inspector") { model.inspectorShown.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model.workspace == nil)
            Divider()
            Button("Today") { model.goToToday() }
                .keyboardShortcut("t")
                .disabled(model.workspace == nil)
            Button("Previous Week") { model.shiftWeeks(-1) }
                .keyboardShortcut("[")
                .disabled(model.workspace == nil)
            Button("Next Week") { model.shiftWeeks(1) }
                .keyboardShortcut("]")
                .disabled(model.workspace == nil)
            Button("Go to Date\u{2026}") { model.activeSheet = .goToDate }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
            Divider()
            Button("Zoom In") { model.zoom(by: 4) }
                .keyboardShortcut("+")
            Button("Zoom Out") { model.zoom(by: -4) }
                .keyboardShortcut("-")
            Button("Actual Size") { model.cellWidth = Prefs.defaultCellWidth }
                .keyboardShortcut("0")
            Divider()
            Menu("Programme") {
                Toggle("All Programmes", isOn: Binding(get: { model.query.programme == nil },
                                                       set: { if $0 { model.query.programme = nil } }))
                Divider()
                ForEach(model.projectList.programmeNames + [""], id: \.self) { name in
                    Toggle(name.isEmpty ? ProjectList.noProgrammeTitle : name,
                           isOn: Binding(get: { model.query.programme == name },
                                         set: { if $0 { model.query.programme = name } }))
                }
            }
            Menu("Status") {
                ForEach(StatusFilter.allCases) { s in
                    Toggle(s.title, isOn: Binding(get: { model.query.status == s },
                                                  set: { if $0 { model.query.status = s } }))
                }
            }
            Menu("Sort By") {
                SortMenuItems()
                    .environment(model)
            }
            Menu("Columns") {
                ForEach(LeftColumn.allCases.filter { $0 != .title }) { c in
                    Toggle(c.title, isOn: Binding(get: { model.isColumnShown(c) }, set: { _ in model.toggleColumn(c) }))
                }
            }
            Menu("Totals Add Up") {
                ForEach(TotalsScope.allCases) { s in
                    Toggle(s.title, isOn: Binding(get: { model.totalsScope == s },
                                                  set: { if $0 { model.totalsScope = s } }))
                }
            }
            Toggle("Programme Subtotals", isOn: $model.showProgrammeSubtotals)
            Toggle("Week Numbers for Unlabelled Weeks", isOn: $model.isoWeekFallback)
            Divider()
            Button("Expand All Programmes") { model.setAllProgrammes(collapsed: false) }
                .disabled(model.workspace == nil)
            Button("Collapse All Programmes") { model.setAllProgrammes(collapsed: true) }
                .disabled(model.workspace == nil)
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.workspace == nil)
            Divider()
        }

        CommandMenu("Day") {
            let has = model.hasSelection
            ForEach(Array(CellLabel.sizes.enumerated()), id: \.offset) { i, label in
                Button("\(label.text) \u{2014} \(label.title)") { model.setLabel(label) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                    .disabled(!has)
            }
            Divider()
            Button("mtg \u{2014} Meeting") { model.setLabel(.meeting) }
                .keyboardShortcut("6", modifiers: [.command, .option])
                .disabled(!has)
            Button("(!) \u{2014} Due Date") { model.setLabel(.due) }
                .keyboardShortcut("7", modifiers: [.command, .option])
                .disabled(!has)
            Button("(P) \u{2014} Planned") { model.setLabel(.planned) }
                .keyboardShortcut("8", modifiers: [.command, .option])
                .disabled(!has)
            Button("Clear Label") { model.setLabel(nil) }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!has)
            Divider()
            Button("Edit Note") {
                model.collapseSelection()
                model.inspectorShown = true
                model.inspectorTab = .day
                model.noteFocusPending = true
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(!has)
            Button("Clear Note") { model.clearNotes() }
                .disabled(!has)
            Button("Clear Label and Note") { model.clearCells() }
                .disabled(!has)
            Divider()
            Button(model.selectionIsInactive ? "Mark Days Active" : "Mark Days Inactive") {
                model.toggleSelectionInactive()
            }
            .disabled(!has)
        }

        CommandMenu("Project") {
            let p = model.focusedProject
            Button("Show Project Info") {
                model.inspectorShown = true
                model.inspectorTab = .project
            }
            .keyboardShortcut("i")
            .disabled(p == nil)
            Button(p?.isActive == false ? "Mark Project Active" : "Mark Project Inactive") {
                if let p { model.setProjectActive(p.key, !p.isActive) }
            }
            .disabled(p == nil)
            Menu("Move to Programme") {
                ForEach(model.projectList.programmeNames + [""], id: \.self) { name in
                    Button(name.isEmpty ? ProjectList.noProgrammeTitle : name) {
                        if let p { model.setProgramme(name, for: p.key) }
                    }
                }
            }
            .disabled(p == nil)
            Divider()
            Button("Move Up") { model.moveProject(nil, by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.canMoveProject(nil, by: -1))
            Button("Move Down") { model.moveProject(nil, by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.canMoveProject(nil, by: 1))
            Divider()
            Button("Delete Project\u{2026}") { model.requestDeleteProject(nil) }
                .disabled(p == nil)
            Divider()
            let programme = p.map { model.projectList.group(of: $0) } ?? ""
            Button("Rename Programme\u{2026}") { model.renameProgramme(programme) }
                .disabled(programme.isEmpty)
            Button("Delete Programme\u{2026}") { model.requestDeleteProgramme(programme) }
                .disabled(programme.isEmpty)
        }
    }
}
