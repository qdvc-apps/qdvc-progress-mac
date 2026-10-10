import SwiftUI
import ProgressCore

/// New Project (⌘N).
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var code = ""
    @State private var programme: String
    @State private var target = ""
    @State private var collaborators = ""

    init(programme: String) {
        _programme = State(initialValue: programme)
    }

    /// The project that already has the ID typed, if any.
    private var duplicate: Project? { model.projectList.project(withCode: code) }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && duplicate == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Project").font(.headline).padding([.top, .horizontal], 20)
            Form {
                TextField("Title", text: $title, prompt: Text("Required"))
                TextField("ID", text: $code, prompt: Text("Optional, e.g. 26XY"))
                    .font(.system(.body, design: .monospaced))
                if let duplicate {
                    Text("\u{201C}\(duplicate.title)\u{201D} already has the ID \(duplicate.code). Each ID can be used once.")
                        .font(.caption).foregroundStyle(.red)
                } else if !code.isEmpty && !Project.isConventionalCode(code) {
                    Text("IDs usually take the form NNXX: two digits, then two letters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Programme", selection: $programme) {
                    ForEach(model.projectList.programmeNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    Text(ProjectList.noProgrammeTitle).tag("")
                }
                TextField("Target", text: $target, prompt: Text("Optional"))
                TextField("Collaborators", text: $collaborators, prompt: Text("Optional"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    model.addProject(title: title, code: code, programme: programme, target: target,
                                     collaborators: collaborators)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .onAppear {
            if !programme.isEmpty && !model.projectList.programmeNames.contains(programme) { programme = "" }
        }
    }
}

/// New Programme / Rename Programme.
struct ProgrammeNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ProgrammeNameRequest
    @State private var name = ""

    private var problem: String? { model.programmeNameProblem(name, renaming: request.original) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.original == nil ? "New Programme" : "Rename Programme").font(.headline)
            Text("A programme is a major stream of work that groups related projects.")
                .foregroundStyle(.secondary)
            TextField("Name", text: $name, prompt: Text("e.g. Research"))
                .textFieldStyle(.roundedBorder)
            if let problem, !name.isEmpty {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.original == nil ? "Create" : "Rename") {
                    model.commitProgrammeName(request, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || name.trimmingCharacters(in: .whitespaces) == request.original)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = request.original ?? "" }
    }
}

/// The label of one week (double-click the week row of the header).
struct WeekLabelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let week: LocalDate
    @State private var label = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Week of \(GridStyle.longDay(week))").font(.headline)
            TextField("Label", text: $label, prompt: Text("e.g. Teaching week 7, Sprint 12, Leave"))
                .textFieldStyle(.roundedBorder)
            Text("Leave empty to show the week number (W\(week.isoWeek.week)).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Edit All Week Labels\u{2026}") {
                    dismiss()
                    DispatchQueue.main.async { model.activeSheet = .weekLabels }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setWeekLabel(label, for: week)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { label = model.weekLabels[week] ?? "" }
    }
}

/// Go to Date (⇧⌘T).
struct GoToDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Go to Date").font(.headline)
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Button("Today") { date = Date() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go") {
                    model.goTo(LocalDate(date))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { date = (model.focusRef?.date ?? model.today).date() }
    }
}
