import AppKit
import SwiftUI
import ProgressCore

/// The main window: the welcome screen, or the grid with the inspector on
/// its right (docs/DESIGN.md §2).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        Group {
            if model.workspace == nil {
                WelcomeView()
            } else {
                MainView()
            }
        }
        .navigationTitle(model.windowTitle)
        .sheet(item: $model.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .confirmationDialog(deletionTitle,
                            isPresented: Binding(get: { model.pendingDeletion != nil },
                                                 set: { if !$0 { model.pendingDeletion = nil } })) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: {
            Text(deletionMessage)
        }
        .onAppear { if model.undoManager == nil { model.undoManager = undoManager } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.appWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.dayChanged()
        }
    }

    private var deletionTitle: String {
        switch model.pendingDeletion {
        case .project(let key)?:
            return "Delete \u{201C}\(model.project(key)?.title ?? key)\u{201D}?"
        case .programme(let name)?:
            return "Delete the programme \u{201C}\(name)\u{201D}?"
        case nil:
            return ""
        }
    }

    private var deletionMessage: String {
        switch model.pendingDeletion {
        case .project(let key)?:
            let n = model.entryCount(for: key)
            let days = n == 1 ? "1 logged day" : "\(n) logged days"
            return "The project and its \(days) are removed from the workspace. You can undo this, and Git keeps the history. To keep the project but hide it, mark it inactive instead."
        case .programme(let name)?:
            let n = model.projectCount(in: name)
            return n == 0
                ? "The programme has no projects."
                : "Its \(n == 1 ? "project moves" : "\(n) projects move") to No Programme; no project or log entry is deleted."
        case nil:
            return ""
        }
    }
}

struct SheetContent: View {
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .newProject(let programme):
            NewProjectSheet(programme: programme)
        case .programmeName(let request):
            ProgrammeNameSheet(request: request)
        case .weekLabels:
            WeekLabelsSheet()
        case .weekLabel(let week):
            WeekLabelSheet(week: week)
        case .goToDate:
            GoToDateSheet()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            BannerStack()
            GridRepresentable(model: model, revision: model.revision, scrollTarget: model.scrollTarget,
                              focusRequest: model.gridFocusRequest)
                .overlay { EmptyGridNotice() }
        }
        .frame(minWidth: 560, minHeight: 320)
        .inspector(isPresented: $model.inspectorShown) {
            InspectorView()
                .inspectorColumnWidth(min: 250, ideal: 290, max: 420)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Filter projects"))
        .toolbar { MainToolbar(model: model).content }
    }
}

/// The window's toolbar. Every item is also in the menu bar.
@MainActor
struct MainToolbar {
    @Bindable var model: AppModel

    @ToolbarContentBuilder
    var content: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button {
                    model.shiftWeeks(-1)
                } label: {
                    Label("Previous Week", systemImage: "chevron.left")
                }
                .help("Previous week (\u{2318}[)")
                Button("Today") { model.goToToday() }
                    .help("Go to today (\u{2318}T)")
                Button {
                    model.shiftWeeks(1)
                } label: {
                    Label("Next Week", systemImage: "chevron.right")
                }
                .help("Next week (\u{2318}])")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker(selection: $model.query.programme) {
                Text("All Programmes").tag(String?.none)
                Divider()
                ForEach(model.projectList.programmeNames, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
                Text(ProjectList.noProgrammeTitle).tag(String?.some(""))
            } label: {
                Label("Programme", systemImage: "square.stack.3d.up")
            }
            .pickerStyle(.menu)
            .help("Show one programme of work, or all of them")

            Picker(selection: $model.query.status) {
                ForEach(StatusFilter.allCases) { s in
                    Text(s.title).tag(s)
                }
            } label: {
                Label("Status", systemImage: "line.3.horizontal.decrease.circle")
            }
            .pickerStyle(.menu)
            .help("Show active projects, inactive projects, or both")

            Menu {
                SortMenuItems()
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort and group the projects")

            Button {
                model.activeSheet = .newProject(programme: model.query.programme ?? "")
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .help("New project (\u{2318}N)")

            Button {
                model.inspectorShown.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the inspector (\u{2325}\u{2318}I)")
        }
    }
}

/// Sort by…, ascending/descending, group by programme. Shared by the
/// toolbar and the View menu.
struct SortMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(SortKey.allCases) { key in
            Toggle(key.title, isOn: Binding(get: { model.query.sort == key },
                                            set: { _ in model.setSort(key) }))
        }
        Divider()
        Toggle(model.query.sort == .lastWorked ? "Oldest First" : "Ascending",
               isOn: Binding(get: { model.query.ascending }, set: { model.query.ascending = $0 }))
        Toggle(model.query.sort == .lastWorked ? "Most Recent First" : "Descending",
               isOn: Binding(get: { !model.query.ascending }, set: { model.query.ascending = !$0 }))
        Divider()
        Toggle("Group by Programme", isOn: Binding(get: { model.query.grouped },
                                                   set: { model.query.grouped = $0 }))
    }
}

/// Shown over the grid when there are no projects, or none pass the filter.
struct EmptyGridNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.projectList.projects.isEmpty {
            ContentUnavailableView {
                Label("No Projects Yet", systemImage: "square.grid.3x3")
            } description: {
                Text("Add the projects you are working on, grouped into programmes of work if you like. Each gets a row, and each day a column.")
            } actions: {
                Button("New Project\u{2026}") { model.activeSheet = .newProject(programme: "") }
                Button("New Programme\u{2026}") { model.newProgramme() }
            }
            .background(.background.opacity(0.9))
        } else if model.rows.isEmpty {
            ContentUnavailableView {
                Label("No Matching Projects", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No project passes the current programme, status and search filters.")
            } actions: {
                Button("Show All Projects") {
                    var q = model.query
                    q.programme = nil
                    q.status = .all
                    q.search = ""
                    model.query = q
                }
            }
            .background(.background.opacity(0.9))
        }
    }
}

/// Notices above the grid: files that could not be read, and a failed save.
struct BannerStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let first = model.issues.first {
                let n = model.issues.count
                let protectedNote = first.isProtected ? " It will not be changed until it is fixed." : ""
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: n == 1
                           ? "\(first.relativePath): \(first.messages.joined(separator: "; ")).\(protectedNote)"
                           : "\(n) files had problems, starting with \(first.relativePath): \(first.messages.first ?? "")",
                       action: "Reveal in Finder") { model.revealIssue(first) }
            }
            if let error = model.saveError {
                Banner(symbol: "xmark.octagon.fill", tint: .red, text: "Couldn\u{2019}t save: \(error)",
                       action: "Dismiss") { model.saveError = nil }
            }
        }
    }
}

struct Banner: View {
    let symbol: String
    let tint: Color
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action, action: perform).controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("QDVC Progress")
                .font(.largeTitle.weight(.semibold))
            Text("Open a progress workspace, or choose an empty folder to start one. Your projects and the work you log against them are kept there as plain YAML and CSV files, ready to commit to Git.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(Array(model.recentWorkspaces.prefix(5)), id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
