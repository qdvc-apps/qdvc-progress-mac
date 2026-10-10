# QDVC Progress for macOS

Keep track of your projects and the work you put into them, day by day, in
one spreadsheet-like grid: a row per project, a column per day. Each day you
note how much a project took out of you — XS, S, M, L or XL — or that you
had a meeting about it, that something was due, or that you plan to work on
it. The totals at the bottom show your workload per day, per working week
and per weekend. A native SwiftUI and AppKit app for macOS 14 (Sonoma) and
later.

Your data is a plain folder of small YAML and CSV files, one log file per
month, so it diffs cleanly and is easy to keep in Git. The format is
documented in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

## What it does

The window is the grid, with an inspector on its right (⌥⌘I). The layout
and its precedents in Numbers, Calendar and Finder are explained in
[docs/DESIGN.md](docs/DESIGN.md).

- **Header:** the month and year, your own label for each week (a teaching
  week, a sprint, a holiday; unlabelled weeks show their week number), the
  day of the month and the day of the week (M, Tu, W, Th, Fr, Sa, Su).
  Today is highlighted in yellow. The header, the project columns and the
  totals stay put while the days scroll; scroll as far back or ahead as you
  like.
- **Projects** are grouped under their **programme of work** (click a
  programme heading to fold it). Each has a title and, optionally, an ID
  (such as 26XY), a target and collaborators. Click a column heading to sort
  by it; drag a heading's edge to resize it; right-click to show or hide
  columns.
- **Day cells** hold one label — **XS S M L XL** in a blue heat map from
  baby blue to navy, **mtg** in bright green, **(!)** for a due date,
  **(P)** for planned work — and an optional **note**, marked by a red
  corner as in a spreadsheet (hover to read it). Days can be marked
  **inactive**, hatched, with a label shown across the period ("On hold",
  "With co-authors").
- **Totals** add up each day's labels (XS = 1 … XL = 5 by default; a meeting
  counts as M) in a salmon-to-red heat map, with a second row for each
  Monday–Friday and each weekend. They follow the filter, or cover all
  projects (View › Totals Add Up).
- **Filter and sort** from the toolbar: one programme or all, active or
  inactive projects or both, a search over titles, IDs, targets and
  collaborators, and sorting by title, ID, target, collaborators or the day
  you last worked on a project.
- **Copy and paste** cells, one or a block. The inspector's Copy & Paste
  setting decides whether Paste writes the label, the note, or both; Edit ›
  Paste Special does it the other way once. Labels copied from a spreadsheet
  paste in too.
- **Week labels** (File › Week Labels…, ⌥⌘L): paste two columns from a
  spreadsheet — a date in the week and its label — and preview how each row
  is read before applying it. Double-click the week row to label one week.
- **Settings** (⌘,): the numbers behind the sizes, with three presets
  (Linear 1–5, Fibonacci 1-2-3-5-8, Doubling 1-2-4-8-16), what a meeting,
  a due date and planned work count as, and where the totals colour peaks.
  These are saved in the workspace.
- **Projects can be marked inactive** as a whole (Project › Mark Project
  Inactive); the Status filter hides them.

## Typing in the grid

Select a cell (or drag across several) and type:

| Key | Sets |
| --- | --- |
| 1 2 3 4 5 | XS S M L XL |
| m | mtg |
| ! | (!) due date |
| p | (P) planned |
| 0, Delete | no label |
| i | inactive / active days |
| Return, double-click | edit the note in the inspector (Esc returns to the grid) |
| Space | show or hide the inspector |
| Arrows, Tab | move (⇧ extends the selection, ⌥← / ⌥→ jump a week) |

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store); Xcode 26 or later for the
  Liquid Glass look. Full Xcode is needed, not just the Command Line Tools:
  from Xcode 27, SwiftUI's `@State` is a macro whose compiler plugin
  (SwiftUIMacros) ships only with Xcode, so a Command Line Tools or swift.org
  toolchain fails with "plugin for module 'SwiftUIMacros' not found".
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
scripts/build-app.sh            # build "build/QDVC Progress.app" (release)
scripts/build-app.sh --install  # …and copy it to ~/Applications
```

`scripts/build-app.sh` builds with Xcode's toolchain even when
`xcode-select` points at the Command Line Tools: it picks the newest Xcode
installed, and says which Xcode and macOS SDK it is using (warning if the
SDK predates Liquid Glass). To run or test from the command line, point
the tools at Xcode the same way, once per Terminal session or for good:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# or: sudo xcode-select --switch /Applications/Xcode.app
swift run                       # build and launch (debug)
swift test                      # run the unit tests
```

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCProgress** scheme and press ⌘R.
Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

A ready-made `sample-workspace/` is included to try the app straight away
(File → Open Workspace…). Its log runs from late August to mid October 2026.
Opening any other folder, even an empty one, offers to start a workspace
there.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it — no account, no
certificate, no notarisation. If you give the app to someone else, macOS
will block the first launch; they can allow it in **System Settings →
Privacy & Security → Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Progress.app"
```

## App icon

The icon, a frosted-glass grid of blue work cells with today's column in
yellow and a row of red totals, sealed with a navy rising-arrow badge, is
generated by `tools/make_icon.py` on Apple's macOS icon template, in the
same style as the other QDVC apps (docs/MAINTENANCE.md §1.1). It appears in
the `.app` built by `scripts/build-app.sh`, not with `swift run`.

## Where things are stored

- Your projects, log, week labels and workload settings: only in the
  workspace folder, as described in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).
  Every change is written straight away (typing, after a short pause). The
  app notices files changed by Git or another editor when you come back to
  it, and View › Refresh (⌘R) re-reads them at any time.
- Preferences (filters, column widths, zoom, recent workspaces): the
  standard macOS defaults domain (`defaults read org.qdvc.progress.mac`).

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N / ⇧⌘N | New Project / New Programme |
| ⌘O | Open Workspace |
| ⌥⌘L | Week Labels |
| ⌘T | Today |
| ⌘[ / ⌘] | Previous / next week |
| ⇧⌘T | Go to Date |
| ⌘+ / ⌘− / ⌘0 | Wider / narrower / default day columns |
| ⌥⌘I | Show or hide the inspector |
| ⌘I | Show the selected project in the inspector |
| ⌥⌘1 … ⌥⌘5 | XS … XL (also plain 1–5 in the grid) |
| ⌥⌘6 / ⌥⌘7 / ⌥⌘8 / ⌥⌘0 | mtg / (!) / (P) / clear |
| ⌥⌘E | Edit note |
| ⌥⌘↑ / ⌥⌘↓ | Move project up / down |
| ⌘C / ⌘X / ⌘V | Copy / cut / paste cells |
| ⌘A | Select all cells |
| ⌘F | Find projects |
| ⌘R | Refresh from disk |
