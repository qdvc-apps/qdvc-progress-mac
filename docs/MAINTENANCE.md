# QDVC Progress for macOS — Maintenance Guide

The one rule that matters most: **the workspace is the contract.** The files
the app writes are documented in [FILE_FORMAT.md](FILE_FORMAT.md) and
checked by the unit tests. Any change to a file name or to the bytes of a
file is a format change: update FILE_FORMAT.md and the tests with it.

## 1. Layout

```
Package.swift                 SwiftPM manifest (no Xcode project)
Sources/ProgressCore/         the model: Foundation + Yams, no AppKit/SwiftUI
Sources/QDVCProgress/         the SwiftUI/AppKit app
Sources/QDVCProgress/Grid/    the AppKit grid
Tests/ProgressCoreTests/      unit tests
tools/make_icon.py            regenerates Resources/AppIcon.{svg,icns}
scripts/build-app.sh          builds and ad-hoc signs "QDVC Progress.app"
Resources/Info.plist          bundle id org.qdvc.progress.mac
sample-workspace/             nine projects in three programmes, Aug–Oct 2026
docs/                         DESIGN, FILE_FORMAT, this guide
```

`ProgressCore` has no AppKit or SwiftUI imports and builds on Linux; the app
target is declared on macOS only. Yams (from 5.1.0) is the only dependency.
Commit `Package.resolved` after the first build so everyone gets the same
Yams.

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and
`Resources/AppIcon.icns` (needs `rsvg-convert`; `brew install librsvg`). The
design is a frosted-glass grid card (blue work cells, a green meeting,
today's column in yellow, a row of red totals) sealed with a navy
rising-arrow badge, in the "Ember" palette, on Apple's template geometry,
matching the other QDVC apps. `--preview` also writes
`build/icon-preview.png`.

## 2. Modules

`ProgressCore`:

| File | Responsibility |
| --- | --- |
| `Dates.swift` | `LocalDate` (zone-less day; ISO weekdays, Mondays, ISO weeks), `MonthKey`, `DayRange` |
| `Labels.swift` | `CellLabel` (sizes and specials, lenient parsing, grid keys), `Cell`, `PasteMode` |
| `Settings.swift` | `WorkloadSettings` (label values, peaks), `SizePreset`, `ExtraField` |
| `Projects.swift` | `Project` (inactive-day merge/split), `InactivePeriod`, `Programme`, `ProjectList` (keys, slugs) |
| `Log.swift` | `ProgressLog` (cells by day and project, totals, last worked), `heatLevel` |
| `Query.swift` | filter, search and sort → `GridRow`s (`RowLayout`) |
| `WeekLabels.swift` | `WeekLabels`, `FlexibleDate` (spreadsheet dates), `WeekLabelImport` |
| `Clipboard.swift` | `CellClip`: the pasteboard payload, and text from other apps |
| `CSV.swift` | RFC 4180 reading and writing |
| `YAMLSupport.swift` | Yams node helpers (key order, quoting, unknown keys) |
| `WorkspaceFiles.swift` | `ProjectsFile`, `SettingsFile`, `LogFile` |
| `Workspace.swift` | loading, atomic writes, protected files, change detection |

The app (`QDVCProgress`): `ProgressApp` (scenes, delegate), `AppModel`
(state, workspace, date range, layout, saving; `@Observable`, main actor)
with `AppModel+Cells` (selection, labels, notes, inactive days, clipboard)
and `AppModel+Projects` (projects, programmes, periods, week labels),
`Commands`, `ContentView` (window, toolbar, banners, welcome, empty
states), `InspectorView`, `Sheets`, `WeekLabelsSheet`, `SettingsView`,
`Prefs`, `Platform`; and in `Grid/`: `GridContainerView` (the scroll view,
frozen panes, range growth, SwiftUI wrapper), `GridBodyView` (cells,
mouse, keyboard, Edit menu, tooltips), `GridPanes` (header, left columns,
column headings, totals), `GridMenus` (context menus), `GridMetrics`,
`GridStyle` (colours, fonts, drawing helpers).

### 2.1 How the grid stays in sync

`AppModel.revision` changes whenever anything the grid draws changes
(`bump()`). `GridRepresentable` receives it as a property, so SwiftUI calls
`updateNSView`, which calls `GridContainerView.reloadIfNeeded()`: new
`GridMetrics`, a resized body, redrawn panes. When the date range grows at
the start (scrolling left) or the zoom changes, `reload()` keeps the same
day at the left edge.

### 2.2 How changes reach the disk

- Cells: `applyCells` writes the months touched at once (typing a note:
  after 0.6 s, via `flushSaves`) and registers one undo step with the old
  cells.
- Projects, programmes and inactive periods: `updateProjects` /
  `replaceProjects` write `projects.yml` (typing in a field: after 0.6 s)
  and register an undo step with the old list. Delete Project removes the
  project's log rows in the same step.
- Week labels: `replaceWeekLabels`; settings: `updateSettings` (no undo,
  as in a Settings window).
- `flushSaves` runs when the selection's focus changes, the app is left or
  quits, and before reloading.

## 3. Behaviour to preserve

- Log rows sorted by date then key; empty cells never written; empty months
  have no file (`LogTests`).
- Project keys never change once written; titles can (`ProjectTests`).
- Unknown YAML keys survive a round trip (`testProjectsFileRepairsAndUnknownKeys`).
- A file that could not be read is never overwritten (`WorkspaceTests`).
- Inactive periods stay sorted, merged and non-overlapping.
- Weeks are Monday–Sunday everywhere (header, totals, week labels).

## 4. Tests

```
swift test
```

`CoreTests.swift` covers dates and ISO weeks, labels and workload values,
paste modes, CSV, the log file round trip and its problems, totals,
inactive-day merging and splitting, slugs, `projects.yml` and
`progress.yml` round trips, filtering and sorting, the spreadsheet date
reader and week-label import, the clipboard, and the workspace (saving,
loading, protection, change detection).

## 5. Roadmap

- Export a period as CSV or a printable report (per programme, per week).
- A year view: one small heat-map square per day.
- Drag rows to reorder projects.
- Planned sizes (e.g. (P) M) if planning ahead needs workload forecasts.
