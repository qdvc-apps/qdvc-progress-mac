import SwiftUI
import ProgressCore

/// The inspector on the right of the window (⌥⌘I): the selected day, or
/// the selected day's project.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Inspector", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            switch model.inspectorTab {
            case .day: DayInspector()
            case .project: ProjectInspector()
            }
        }
    }
}

// MARK: - Day

struct DayInspector: View {
    @Environment(AppModel.self) private var model
    @FocusState private var noteFocused: Bool

    var body: some View {
        @Bindable var model = model
        if let focus = model.focusRef, let project = model.project(focus.project) {
            let refs = model.selectedRefs
            let single = refs.count == 1
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title).font(.headline).lineLimit(2)
                        if single {
                            Text(GridStyle.longDay(focus.date)).foregroundStyle(.secondary)
                        } else {
                            let projects = Set(refs.map(\.project)).count
                            Text("\(refs.count) days selected across \(projects) project\(projects == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !single {
                        LabeledContent("Workload of selection",
                                       value: "\(refs.reduce(0) { $0 + model.settings.value(of: model.cell($1).label) })")
                    }
                }

                Section {
                    LabelButtons(labels: [nil] + CellLabel.sizes.map { Optional($0) })
                } header: {
                    Text("Work Done")
                } footer: {
                    Text("Type 1\u{2013}5 in the grid for XS\u{2013}XL, 0 or Delete to clear.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabelButtons(labels: CellLabel.specials.map { Optional($0) })
                } header: {
                    Text("Special")
                } footer: {
                    Text("Type m for a meeting, p for planned work, ! for a due date, v for a tick, x for a cross, ? for information. Emblems add nothing to the totals.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Note") {
                    if single {
                        TextEditor(text: Binding(get: { model.cell(focus).note },
                                                 set: { model.setNote($0, for: focus) }))
                            .font(.body)
                            .frame(minHeight: 110)
                            .focused($noteFocused)
                            .onExitCommand { model.gridFocusRequest += 1 }
                    } else {
                        Text("Select a single day to write its note.").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(single ? "Inactive on this day" : "Inactive on these days",
                           isOn: Binding(get: { model.selectionIsInactive },
                                         set: { model.setSelectionInactive($0) }))
                    if single, let period = project.inactivePeriod(on: focus.date) {
                        TextField("Label", text: Binding(
                            get: { model.project(project.key)?.inactivePeriod(on: focus.date)?.label ?? "" },
                            set: { model.setPeriodLabel(project.key, period: period.id, label: $0) }),
                                  prompt: Text("e.g. On hold"))
                        LabeledContent("Period", value: GridStyle.range(period.range))
                    }
                } header: {
                    Text("Availability")
                } footer: {
                    Text("Type i in the grid to mark the selected days inactive. The label is shown across the period.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Picker("Paste", selection: $model.pasteMode) {
                        ForEach(PasteMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Copy & Paste")
                } footer: {
                    Text("What Paste (\u{2318}V) writes into the selected days. A single copied day fills the whole selection. Edit \u{203A} Paste Special pastes once in another way.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .onAppear { consumeFocusRequest() }
            .onChange(of: model.noteFocusPending) { consumeFocusRequest() }
        } else {
            ContentUnavailableView("No Day Selected", systemImage: "square.dashed",
                                   description: Text("Click a cell in the grid."))
        }
    }

    private func consumeFocusRequest() {
        guard model.noteFocusPending else { return }
        model.noteFocusPending = false
        DispatchQueue.main.async { noteFocused = true }
    }
}

/// A row of buttons that set the selected days' label, coloured as in the
/// grid, each with the number it adds to the totals.
struct LabelButtons: View {
    @Environment(AppModel.self) private var model
    let labels: [CellLabel?]

    var body: some View {
        let current = model.commonSelectedLabel
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(labels, id: \.self) { label in
                let selected = current == .some(label)
                Button {
                    model.setLabel(label)
                } label: {
                    VStack(spacing: 1) {
                        if let label, label.isEmblem {
                            EmblemImage(label: label, size: 15)
                        } else {
                            Text(label?.text ?? "None")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(label.map { "\(model.settings.value(of: $0))" } ?? "\u{2013}")
                            .font(.system(size: 9).monospacedDigit())
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(label.map { GridStyle.swiftUIText(for: $0) } ?? Color.secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(label.flatMap { GridStyle.fill(for: $0) }.map { Color(nsColor: $0) }
                                  ?? Color.secondary.opacity(0.08))
                    }
                    .overlay {
                        if label == .planned {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: GridStyle.plannedStroke),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(tooltip(for: label))
            }
        }
        .padding(.vertical, 2)
    }

    /// A plain String, so `.help` takes its String overload: as a
    /// LocalizedStringKey, interpolating the key (a Character) is deprecated.
    private func tooltip(for label: CellLabel?) -> String {
        guard let label else { return "Clear the label (key 0)" }
        return "\(label.title) (key \(label.key))"
    }
}

/// An emblem label (due date, tick, cross, information) as in the grid: a
/// white symbol on a coloured circle.
struct EmblemImage: View {
    let label: CellLabel
    let size: CGFloat

    var body: some View {
        if let symbol = GridStyle.emblemSymbol(label), let color = GridStyle.emblemColor(label) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color(nsColor: color))
                .accessibilityLabel(label.title)
        }
    }
}

// MARK: - Project

struct ProjectInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let p = model.focusedProject {
            let key = p.key
            Form {
                Section {
                    TextField("Title", text: field(key, "title", \.title), prompt: Text("Required"))
                    TextField("ID", text: field(key, "code", \.code), prompt: Text("e.g. 26XY"))
                        .font(.system(.body, design: .monospaced))
                    if let other = model.projectList.project(withCode: p.code, excluding: key) {
                        Text("\u{201C}\(other.title)\u{201D} already has this ID. Each ID should be used once.")
                            .font(.caption).foregroundStyle(.red)
                    } else if !p.code.isEmpty && !Project.isConventionalCode(p.code) {
                        Text("IDs usually take the form NNXX: two digits, then two letters.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Programme", selection: Binding(get: { model.projectList.group(of: p) },
                                                           set: { model.setProgramme($0, for: key) })) {
                        ForEach(model.projectList.programmeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        Text(ProjectList.noProgrammeTitle).tag("")
                    }
                    TextField("Target", text: field(key, "target", \.target))
                    TextField("Collaborators", text: field(key, "collaborators", \.collaborators))
                    Toggle("Active project", isOn: Binding(get: { model.project(key)?.isActive ?? true },
                                                           set: { model.setProjectActive(key, $0) }))
                } footer: {
                    HStack {
                        Button("New Programme\u{2026}") { model.newProgramme(assignTo: key) }
                        Spacer()
                    }
                }

                Section {
                    if p.inactivePeriods.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(p.inactivePeriods) { period in
                        PeriodEditor(projectKey: key, period: period)
                    }
                    Button("Add Period") {
                        model.addPeriod(key, from: model.focusRef?.date ?? model.today)
                    }
                } header: {
                    Text("Inactive Periods")
                } footer: {
                    Text("Days the project was set aside, e.g. on hold for a few weeks. Separate from the Active project switch.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Workload") {
                    LabeledContent("Last 7 days", value: "\(workload(key, days: 7))")
                    LabeledContent("Last 30 days", value: "\(workload(key, days: 30))")
                    LabeledContent("Last worked on", value: model.lastWorked[key].map { GridStyle.longDay($0) } ?? "Never")
                    LabeledContent("Days logged", value: "\(model.entryCount(for: key))")
                }

                Section {
                    LabeledContent("File key") {
                        Text(key).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Move Up") { model.moveProject(key, by: -1) }
                            .disabled(!model.canMoveProject(key, by: -1))
                        Button("Move Down") { model.moveProject(key, by: 1) }
                            .disabled(!model.canMoveProject(key, by: 1))
                        Spacer()
                        Button("Delete\u{2026}", role: .destructive) { model.requestDeleteProject(key) }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Project Selected", systemImage: "rectangle.dashed",
                                   description: Text("Click a project in the grid."))
        }
    }

    private func field(_ key: String, _ name: String, _ path: WritableKeyPath<Project, String>) -> Binding<String> {
        Binding(get: { model.project(key)?[keyPath: path] ?? "" },
                set: { value in model.editProject(key, field: name) { $0[keyPath: path] = value } })
    }

    private func workload(_ key: String, days: Int) -> Int {
        let today = model.today
        return model.log.total(over: DayRange(from: today.adding(days: 1 - days), to: today),
                               settings: model.settings, includes: { $0 == key })
    }
}

struct PeriodEditor: View {
    @Environment(AppModel.self) private var model
    let projectKey: String
    let period: InactivePeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                DatePicker("From", selection: Binding(
                    get: { period.range.from.date() },
                    set: { model.setPeriodRange(projectKey, period: period.id, from: LocalDate($0), to: period.range.to) }),
                           displayedComponents: .date)
                    .labelsHidden()
                Text("to").foregroundStyle(.secondary)
                DatePicker("To", selection: Binding(
                    get: { period.range.to.date() },
                    set: { model.setPeriodRange(projectKey, period: period.id, from: period.range.from, to: LocalDate($0)) }),
                           displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Button(role: .destructive) {
                    model.removePeriod(projectKey, period: period.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this period (the days become active again)")
            }
            TextField("Label", text: Binding(get: { period.label },
                                             set: { model.setPeriodLabel(projectKey, period: period.id, label: $0) }),
                      prompt: Text("Label shown in the grid"))
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
