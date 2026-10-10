import AppKit
import SwiftUI
import ProgressCore

/// Workspace › Week Labels…: set the header's week labels by pasting two
/// columns from a spreadsheet (a date in the week, and the label), with a
/// live preview of how each row is read.
struct WeekLabelsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var order: DateOrder = Prefs.dateOrder
    @State private var replaceAll = false

    private var rows: [WeekLabelImport.Row] {
        WeekLabelImport.parse(pasted, order: order, referenceYear: model.today.year)
    }

    var body: some View {
        let parsed = rows
        let labels = WeekLabelImport.labels(from: parsed)
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Labels").font(.title3.weight(.semibold))
            Text("Each week can carry a label in the grid\u{2019}s header, such as a teaching week, a sprint or a holiday. Copy two columns from a spreadsheet \u{2014} a date in the week (any day) and its label \u{2014} and paste them below. Weeks without a label show their week number.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rows from a spreadsheet").font(.headline)
                    TextEditor(text: $pasted)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    HStack {
                        Button("Paste from Clipboard") {
                            pasted = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                        Spacer()
                        Picker("Dates", selection: $order) {
                            ForEach(DateOrder.allCases) { o in Text(o.title).tag(o) }
                        }
                        .fixedSize()
                        .onChange(of: order) { _, new in Prefs.dateOrder = new }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview").font(.headline)
                    List(parsed) { row in
                        PreviewRow(row: row)
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(minHeight: 200)
                    let skipped = parsed.count - labels.count
                    Text(parsed.isEmpty
                         ? "Nothing pasted yet."
                         : "\(labels.count) week\(labels.count == 1 ? "" : "s") to label\(skipped > 0 ? ", \(skipped) row\(skipped == 1 ? "" : "s") skipped" : "").")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Picker("When applying", selection: $replaceAll) {
                Text("Add to the current labels (replacing those of the same weeks)").tag(false)
                Text("Replace all current labels").tag(true)
            }
            .pickerStyle(.radioGroup)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Current labels").font(.headline)
                Text("\(model.weekLabels.count)").foregroundStyle(.secondary)
                Spacer()
                Button("Copy for Spreadsheet") { copyCurrent() }
                    .disabled(model.weekLabels.isEmpty)
                    .help("Copy the current labels as two tab-separated columns, to edit in a spreadsheet and paste back")
                Button("Remove All", role: .destructive) {
                    model.replaceWeekLabels(WeekLabels(), actionName: "Remove Week Labels")
                }
                .disabled(model.weekLabels.isEmpty)
            }
            List {
                ForEach(model.weekLabels.sorted, id: \.week) { item in
                    HStack {
                        Text(GridStyle.longDay(item.week)).monospacedDigit().frame(width: 130, alignment: .leading)
                        Text(item.label)
                        Spacer()
                        Button {
                            model.setWeekLabel("", for: item.week)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this label")
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 110)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply Pasted Rows") {
                    model.importWeekLabels(labels, replacingAll: replaceAll)
                    pasted = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(labels.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 780, height: 660)
    }

    private func copyCurrent() {
        let text = model.weekLabels.sorted.map { "\($0.week.iso)\t\($0.label)" }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private struct PreviewRow: View {
    let row: WeekLabelImport.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(row.line)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 24, alignment: .trailing)
            switch row.outcome {
            case let .label(week, text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Week of \(GridStyle.shortDay(week)) \(String(week.year))").monospacedDigit()
                Text("\u{2192}").foregroundStyle(.secondary)
                Text(text).fontWeight(.medium).lineLimit(1)
            case let .skipped(reason):
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
                Text(reason).foregroundStyle(.secondary)
                Text(row.source.replacingOccurrences(of: "\t", with: "  \u{21E5}  "))
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
            }
        }
    }
}
