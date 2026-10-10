import SwiftUI
import ProgressCore

/// Settings (⌘,). Workload is saved in the workspace (progress.yml), so it
/// travels with the data; General is saved on this Mac.
struct SettingsView: View {
    var body: some View {
        TabView {
            WorkloadSettingsView()
                .tabItem { Label("Workload", systemImage: "scalemass") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520)
    }
}

struct WorkloadSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.workspace == nil {
            ContentUnavailableView("No Workspace Open", systemImage: "folder",
                                   description: Text("The workload settings are saved in the workspace. Open one to change them."))
                .frame(height: 300)
        } else {
            Form {
                Section {
                    Picker("Preset", selection: Binding(
                        get: { model.settings.matchingPreset?.id ?? "custom" },
                        set: { id in
                            if let preset = SizePreset.all.first(where: { $0.id == id }) {
                                model.updateSettings { $0.sizeValues = preset.values }
                            }
                        })) {
                        ForEach(SizePreset.all) { preset in
                            Text("\(preset.name) (\(preset.values.map(String.init).joined(separator: ", ")))").tag(preset.id)
                        }
                        if model.settings.matchingPreset == nil {
                            Text("Custom").tag("custom")
                        }
                    }
                    if let preset = model.settings.matchingPreset {
                        Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(CellLabel.sizes.enumerated()), id: \.offset) { i, label in
                        Stepper(value: Binding(get: { model.settings.sizeValues[i] },
                                               set: { v in model.updateSettings { $0.sizeValues[i] = v } }),
                                in: 0...100) {
                            HStack {
                                SizeChip(label: label)
                                Text(label.title)
                                Spacer()
                                Text("\(model.settings.sizeValues[i])").monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Work Sizes")
                } footer: {
                    Text("How much each size adds to the totals. The sizes are your own sense of the effort a day\u{2019}s work took, not the hours.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Special Labels") {
                    Picker(selection: Binding(get: { model.settings.meetingSize },
                                              set: { v in model.updateSettings { $0.meetingSize = v } })) {
                        ForEach(CellLabel.sizes) { size in
                            Text("\(size.text) (\(model.settings.value(of: size)))").tag(size)
                        }
                    } label: {
                        HStack { SizeChip(label: .meeting); Text("A meeting counts as") }
                    }
                    Stepper(value: Binding(get: { model.settings.dueValue },
                                           set: { v in model.updateSettings { $0.dueValue = v } }), in: 0...100) {
                        HStack {
                            SizeChip(label: .due)
                            Text("A due date adds")
                            Spacer()
                            Text("\(model.settings.dueValue)").monospacedDigit()
                        }
                    }
                    Stepper(value: Binding(get: { model.settings.plannedValue },
                                           set: { v in model.updateSettings { $0.plannedValue = v } }), in: 0...100) {
                        HStack {
                            SizeChip(label: .planned)
                            Text("Planned work adds")
                            Spacer()
                            Text("\(model.settings.plannedValue)").monospacedDigit()
                        }
                    }
                }

                Section {
                    Stepper(value: Binding(get: { model.settings.dayPeak },
                                           set: { v in model.updateSettings { $0.dayPeak = max(1, v) } }), in: 1...200) {
                        HStack {
                            Text("Deepest colour at a daily total of")
                            Spacer()
                            Text("\(model.settings.dayPeak)").monospacedDigit()
                        }
                    }
                    HeatPreview(peak: model.settings.dayPeak)
                } header: {
                    Text("Totals")
                } footer: {
                    Text("Week totals (Monday\u{2013}Friday) are deepest at five times this, weekends at twice it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 560)
        }
    }
}

struct SizeChip: View {
    let label: CellLabel

    var body: some View {
        Text(label.text)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 30, height: 18)
            .foregroundStyle(GridStyle.swiftUIText(for: label))
            .background(RoundedRectangle(cornerRadius: 3).fill(GridStyle.swiftUIFill(for: label)))
            .overlay {
                if label == .planned {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color(nsColor: GridStyle.plannedStroke), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }
}

/// The totals colour scale, from 0 to the peak.
struct HeatPreview: View {
    let peak: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6) { i in
                let value = Int((Double(peak) * Double(i) / 5).rounded())
                let level = heatLevel(value, peak: peak)
                Text("\(value)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .foregroundStyle(Color(nsColor: GridStyle.totalText(level: level)))
                    .background(RoundedRectangle(cornerRadius: 3).fill(
                        GridStyle.totalFill(level: level).map { Color(nsColor: $0) } ?? Color.secondary.opacity(0.1)))
            }
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Reopen the last workspace at launch", isOn: $model.reopenLast)
            Toggle("Show week numbers for weeks without a label", isOn: $model.isoWeekFallback)
            Toggle("Show programme subtotals in programme headings", isOn: $model.showProgrammeSubtotals)
            Picker("Totals add up", selection: $model.totalsScope) {
                ForEach(TotalsScope.allCases) { s in Text(s.title).tag(s) }
            }
            LabeledContent("Day column width") {
                Slider(value: $model.cellWidth, in: Prefs.cellWidthRange, step: 2)
                    .frame(width: 200)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
