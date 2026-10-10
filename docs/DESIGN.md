# QDVC Progress for macOS — Design

Status: **first implementation written.** Decisions taken on the open
questions are recorded in §8.

QDVC Progress keeps a day-by-day record of the effort you put into your
projects. It follows the approach of the other QDVC macOS apps (Meetings,
Nice Mail, Bibliotheca, GTD EML): a Foundation-only core library with unit
tests, a SwiftUI/AppKit front-end, no Xcode project file, and an
ad-hoc-signed bundle built by `scripts/build-app.sh`.

## 1. Principles

- **The grid is the app.** Everything you do daily happens in one
  spreadsheet-like view; everything else is a sheet, a menu or the
  inspector.
- **The workspace is a plain folder** of YAML and CSV, shaped for Git
  (FILE_FORMAT.md §1). Writes are immediate and atomic.
- **Look like Numbers and Calendar where they have an answer:** frozen
  header rows and columns, a footer of totals, an inspector on the right
  (Numbers, Keynote, Xcode), Calendar's ‹ Today › control and ⌘T.
- **Every action is in the menu bar.** Toolbar buttons, context menus and
  single-key typing in the grid are shortcuts, never the only way in.
- **The keyboard is fast:** with a cell selected, one key sets a label.

## 2. Navigation: one window, no sidebar

The siblings use a sidebar and a master–detail split because their content
is a list of documents (meetings, emails, references) each with a lot of
detail. Here the content *is* a table: the "detail" of a cell is a label and
a short note, and the useful view is many projects across many days at once.
A sidebar or a detail pane would take width away from the days, which is
what you most want to see. So:

- **No tab bar and no sidebar.** Filtering by programme, which a sidebar
  would otherwise do, is a pop-up in the toolbar and the View menu. Programme
  headings in the grid fold and unfold their projects.
- **An inspector instead of a detail pane** (⌥⌘I, Space in the grid): it
  shows the selected day (label buttons, note, inactive period, paste
  setting) or the selected day's project (fields, inactive periods,
  workload). It can be hidden to give the grid the full width.

A sidebar would earn its place if the app grew several *kinds* of view
(e.g. a per-programme report or a year heat-map); then a source list on the
left choosing the view, as in Music or Finder, would be the natural move.

## 3. The grid

```
┌ corner ───────────────┬ header (scrolls horizontally) ─────────────────┐
│ 12 projects           │ October 2026                                   │
│ Today: Sat 10 Oct     │ Teaching wk 9         │ Teaching wk 10         │
│ ID  Project  Target   │ 5  6  7  8  9 10 11 │ 12 13 …                  │
│                       │ M Tu  W Th Fr Sa Su │  M Tu …                  │
├ left (scrolls ───────┼ body (scrolls both ways) ───────────────────────┤
│  vertically)          │                                                │
│ ▾ Research  3         │  4  3        6  …  (programme subtotals)      │
│ 26AR ARC grant  DP27  │ [M][L]   [mtg]                                │
│ 25SC Soil carbon …    │ ////// With co-authors ////////               │
├ footer corner ────────┼ footer (scrolls horizontally) ─────────────────┤
│ Daily total (shown) ▾ │ 12  9 14  3  8  0  2                           │
│ Mon–Fri · weekend     │ [      46       ][ 2 ]                         │
└───────────────────────┴────────────────────────────────────────────────┘
```

- The body is an `NSScrollView` document drawn with Core Graphics; the
  header, left columns, footer and corners are separate views that follow
  its scroll offset, so they stay frozen as in a spreadsheet. Drawing is
  limited to the visible rows and days, so long histories stay fast.
- The range of days grows when you scroll near either end, so there is no
  "page" to turn. ⌘[ / ⌘] move a week, ⌘T returns to today, ⇧⌘T goes to a
  date.
- Weeks run Monday to Sunday. Weekends are tinted; Mondays have a stronger
  line. Today's column is tinted yellow, its header cells solid yellow, its
  total ringed in yellow.
- Column headings sort (click again to reverse); their edges resize;
  right-click shows or hides ID, Target and Collaborators.

## 4. Colour

| Element | Colour |
| --- | --- |
| XS → XL | single-hue blue heat map: `#CFE8FB` baby blue, `#9CCBF2`, `#5A9BDB`, `#2B5EA8`, `#10275C` navy (white text on L, XL) |
| mtg | bright green `#2EDB4F` |
| (!) | amber `#FFB020` |
| (P) | no fill, dashed blue outline, grey text: not yet done |
| Totals | salmon `#FFE3D8` → red `#C62F2F`, by the total's share of the peak (Settings › Workload) |
| Today | yellow `#FFD60A` |
| Note | red corner triangle `#E5484D`, as in Excel and Numbers |
| Inactive days | grey hatching, with the period's label in a pill across it |
| Inactive projects | dimmed cells, italic title |

The colours are in `GridStyle.swift` and the icon generator.

## 5. Interaction

- **Selecting:** click, ⇧-click or drag a rectangle; click a day heading to
  select that day for every project shown, a week label for the whole week;
  click a project title to select its row's cell on the same day (and show
  the Project tab).
- **Typing** (grid focused): 1–5 = XS–XL, m = mtg, ! = (!), p = (P),
  0 / Delete = clear, i = toggle inactive days, Return = edit note,
  Space = inspector, arrows / Tab move, ⇧ extends, ⌥←/→ jump a week,
  Esc collapses the selection. The Day menu repeats these with ⌥⌘ shortcuts.
- **Copy / Cut / Paste** use the standard Edit menu. The clipboard carries
  the app's own type (labels and notes) plus tab-separated labels for other
  apps; text from a spreadsheet pastes as labels, and other text as a note.
  A single copied cell fills the whole selection; a block pastes from the
  selection's top-left. The inspector's **Copy & Paste** setting chooses
  Label and Note / Label Only / Note Only; Edit › Paste Special applies
  another mode once.
- **Undo** covers every change (typing in a note or a field is one step per
  visit).
- **Menus:** File (projects, programmes, workspace, Week Labels…), Edit
  (Paste Special, Find), View (inspector, dates, zoom, filters, sort,
  columns, totals), Day (labels, notes, inactive days), Project (info,
  active flag, programme, order, delete, programme rename/delete).

## 6. Workload numbers

The sizes are subjective — how much a day's work took out of you, not the
hours — so the mapping to numbers is a setting, saved in the workspace with
three presets:

- **Linear** 1, 2, 3, 4, 5 (default): simple to add in your head.
- **Fibonacci** 1, 2, 3, 5, 8 (recommended): felt effort grows faster than
  linearly; an XL day "costs" what eight XS days do. This is the scale agile
  teams use for the same reason, and it makes a week with two XL days stand
  out from one with five M days, which a linear scale hides (10 vs 15 on
  linear; 16 vs 15 on Fibonacci).
- **Doubling** 1, 2, 4, 8, 16: for when one exhausting day should dominate.

A meeting counts as a size (M by default); due dates and plans count 0 by
default.

## 7. Saving and syncing

Changes are written at once (typing after 0.6 s, and on leaving the app).
When the app becomes active it checks the workspace's files' dates and
sizes and reloads if anything changed (after `git pull`, say). A file that
could not be read is shown in a banner and protected from being
overwritten.

## 8. Decisions

| Question | Decision |
| --- | --- |
| What is the custom week label? | Free text per week, set by pasting two spreadsheet columns (a date in the week, the label) into File › Week Labels…, with a live preview; or by double-clicking a week. Unlabelled weeks show W41 (can be turned off). |
| Can a cell hold a size and a special label? | No: one label per cell (XS–XL, mtg, (!), (P)), plus an optional note. Inactive days are separate, so an inactive day can still carry a label. |
| What do totals add up when filtered? | The projects shown (filter and search), with View › Totals Add Up › All Projects to switch. Collapsed programmes still count. |
| Navigation | One window: grid + inspector, no tab bar or sidebar (§2). |
| Storage | YAML for settings and projects, CSV for the log (one file per month) and week labels (FILE_FORMAT.md). |
