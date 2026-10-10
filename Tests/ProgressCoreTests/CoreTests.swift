import XCTest
@testable import ProgressCore

private func d(_ s: String) -> LocalDate { LocalDate(s)! }

final class DateTests: XCTestCase {
    func testWeekdaysAndMondays() {
        XCTAssertEqual(d("2026-10-05").isoWeekday, 1)   // Monday
        XCTAssertEqual(d("2026-10-11").isoWeekday, 7)   // Sunday
        XCTAssertEqual(d("2026-10-10").monday, d("2026-10-05"))
        XCTAssertEqual(d("2026-10-05").monday, d("2026-10-05"))
        XCTAssertTrue(d("2026-10-10").isWeekend)
        XCTAssertFalse(d("2026-10-09").isWeekend)
    }

    func testISOWeek() {
        XCTAssertEqual(d("2026-10-09").isoWeek.week, 41)
        XCTAssertEqual(d("2021-01-03").isoWeek.week, 53)   // belongs to 2020
        XCTAssertEqual(d("2021-01-03").isoWeek.year, 2020)
        XCTAssertEqual(d("2026-01-01").isoWeek.week, 1)
    }

    func testOrdinalRoundTripAndMonths() {
        let day = d("2024-02-29")
        XCTAssertEqual(LocalDate(ordinal: day.ordinal), day)
        XCTAssertEqual(day.adding(days: 1), d("2024-03-01"))
        XCTAssertEqual(d("2026-01-31").adding(months: 1), d("2026-02-28"))
        XCTAssertEqual(MonthKey("2026-10")?.lastDay, d("2026-10-31"))
        XCTAssertEqual(LogFile.relativePath(for: MonthKey(year: 2026, month: 3)), "log/2026/2026-03.csv")
    }
}

final class LabelTests: XCTestCase {
    func testLenientLabels() {
        XCTAssertEqual(CellLabel(lenient: " xs "), .xs)
        XCTAssertEqual(CellLabel(lenient: "MTG"), .meeting)
        XCTAssertEqual(CellLabel(lenient: "!"), .due)
        XCTAssertEqual(CellLabel(lenient: "(p)"), .planned)
        XCTAssertNil(CellLabel(lenient: "XXL"))
    }

    func testWorkloadValues() {
        var s = WorkloadSettings()
        XCTAssertEqual(s.value(of: .xl), 5)
        XCTAssertEqual(s.value(of: .meeting), 3)
        XCTAssertEqual(s.value(of: .due), 0)
        s.sizeValues = SizePreset.fibonacci.values
        s.meetingSize = .l
        XCTAssertEqual(s.value(of: .meeting), 5)
        XCTAssertEqual(s.matchingPreset, .fibonacci)
    }

    func testPasteModes() {
        let source = Cell(label: .l, note: "new")
        let target = Cell(label: .s, note: "old")
        XCTAssertEqual(PasteMode.both.apply(source, onto: target), source)
        XCTAssertEqual(PasteMode.label.apply(source, onto: target), Cell(label: .l, note: "old"))
        XCTAssertEqual(PasteMode.note.apply(source, onto: target), Cell(label: .s, note: "new"))
    }
}

final class CSVTests: XCTestCase {
    func testRoundTripWithQuotesAndNewlines() {
        let rows = [["a", "b,c", "say \"hi\"", "two\nlines"], ["", " padded", "x", ""]]
        XCTAssertEqual(CSV.parse(CSV.render(rows)), rows)
    }

    func testCRLFAndBOM() {
        XCTAssertEqual(CSV.parse("\u{FEFF}a,b\r\nc,d\r\n"), [["a", "b"], ["c", "d"]])
    }
}

final class LogTests: XCTestCase {
    func testLogFileRoundTrip() {
        let entries = [
            LogEntry(date: d("2026-10-06"), project: "beta", cell: Cell(label: .meeting)),
            LogEntry(date: d("2026-10-05"), project: "alpha", cell: Cell(label: .m, note: "Drafted, revised\nand sent")),
            LogEntry(date: d("2026-10-05"), project: "beta", cell: Cell(note: "Only a note")),
        ]
        let text = LogFile.render(entries)
        XCTAssertTrue(text.hasPrefix("date,project,label,note\n2026-10-05,alpha,M,\"Drafted, revised\nand sent\"\n"))
        let parsed = LogFile.parse(text, month: MonthKey(year: 2026, month: 10))
        XCTAssertEqual(parsed.problems, [])
        XCTAssertEqual(parsed.entries.count, 3)
        XCTAssertEqual(LogFile.render(parsed.entries), text)
    }

    func testLogFileProblems() {
        let parsed = LogFile.parse("date,project,label,note\n2026-11-01,a,M,\n2026-10-02,a,XXL,\n", month: MonthKey(year: 2026, month: 10))
        XCTAssertEqual(parsed.entries.count, 0)
        XCTAssertEqual(parsed.problems.count, 2)
    }

    func testTotals() {
        var log = ProgressLog()
        log["a", d("2026-10-05")] = Cell(label: .xl)
        log["b", d("2026-10-05")] = Cell(label: .meeting)
        log["c", d("2026-10-05")] = Cell(label: .due)
        log["a", d("2026-10-06")] = Cell(label: .s)
        let s = WorkloadSettings()
        XCTAssertEqual(log.total(on: d("2026-10-05"), settings: s), 8)
        XCTAssertEqual(log.total(on: d("2026-10-05"), settings: s, includes: { $0 == "a" }), 5)
        XCTAssertEqual(log.total(over: DayRange(from: d("2026-10-05"), to: d("2026-10-09")), settings: s), 10)
        XCTAssertEqual(log.lastWorked()["a"], d("2026-10-06"))
        XCTAssertNil(log.lastWorked()["c"])
        log["a", d("2026-10-06")] = Cell()
        XCTAssertEqual(log.entryCount, 3)
    }
}

final class ProjectTests: XCTestCase {
    func testInactiveDaysMergeAndSplit() {
        var p = Project(key: "p", title: "P")
        p.setInactive(true, on: [d("2026-10-05"), d("2026-10-06")])
        p.inactivePeriods[0].label = "On hold"
        p.setInactive(true, on: [d("2026-10-07"), d("2026-10-09")])
        XCTAssertEqual(p.inactivePeriods.count, 2)
        XCTAssertEqual(p.inactivePeriods[0].range, DayRange(from: d("2026-10-05"), to: d("2026-10-07")))
        XCTAssertEqual(p.inactivePeriods[0].label, "On hold")
        p.setInactive(true, on: [d("2026-10-08")])
        XCTAssertEqual(p.inactivePeriods.count, 1)
        p.setInactive(false, on: [d("2026-10-07")])
        XCTAssertEqual(p.inactivePeriods.map(\.range), [
            DayRange(from: d("2026-10-05"), to: d("2026-10-06")),
            DayRange(from: d("2026-10-08"), to: d("2026-10-09")),
        ])
        XCTAssertEqual(p.inactivePeriods.map(\.label), ["On hold", "On hold"])
    }

    func testSlugsAndKeys() {
        XCTAssertEqual(ProjectList.slug("Café Réview: Phase 2!"), "cafe-review-phase-2")
        XCTAssertEqual(ProjectList.slug("???"), "project")
        let list = ProjectList(projects: [Project(key: "grant", title: "Grant")])
        XCTAssertEqual(list.newKey(for: "Grant"), "grant-2")
        XCTAssertTrue(Project.isConventionalCode("26XY"))
        XCTAssertFalse(Project.isConventionalCode("2XYZ"))
    }

    func testProjectsFileRoundTrip() throws {
        var list = ProjectList(programmes: [Programme(name: "Research"), Programme(name: "Teaching")])
        list.projects = [
            Project(key: "grant", code: "26GR", title: "Grant renewal", programme: "Research",
                    target: "ARC DP27", collaborators: "A. Smith, B. Jones",
                    inactivePeriods: [InactivePeriod(range: DayRange(from: d("2026-11-02"), to: d("2026-11-20")),
                                                     label: "Waiting: ethics")]),
            Project(key: "stats", title: "STATS 101", programme: "Teaching", isActive: false),
            Project(key: "misc", title: "Yes"),
        ]
        let text = ProjectsFile.render(list)
        XCTAssertTrue(text.contains("id: '26GR'"))
        XCTAssertTrue(text.contains("title: 'Yes'"))
        XCTAssertTrue(text.contains("active: false"))
        let parsed = try ProjectsFile.parse(text)
        XCTAssertEqual(parsed.problems, [])
        XCTAssertEqual(parsed.list.projects.count, 3)
        XCTAssertEqual(parsed.list.projects[0].code, "26GR")
        XCTAssertEqual(parsed.list.projects[0].inactivePeriods.first?.label, "Waiting: ethics")
        XCTAssertFalse(parsed.list.projects[1].isActive)
        XCTAssertEqual(ProjectsFile.render(parsed.list), text)
    }

    func testProjectsFileRepairsAndUnknownKeys() throws {
        let text = """
        projects:
        - title: No key here
          colour: teal
        - key: a
          title: First
          programme: New Programme
        - key: a
          title: Second
        """
        let parsed = try ProjectsFile.parse(text)
        XCTAssertEqual(parsed.list.projects.map(\.key), ["no-key-here", "a", "a-2"])
        XCTAssertEqual(parsed.list.programmeNames, ["New Programme"])
        XCTAssertEqual(parsed.problems.count, 2)
        XCTAssertTrue(ProjectsFile.render(parsed.list).contains("colour: teal"))
    }

    func testSettingsRoundTrip() throws {
        var s = WorkloadSettings(sizeValues: [1, 2, 3, 5, 8], meetingSize: .s, dueValue: 1, plannedValue: 0, dayPeak: 20)
        s.extras = []
        let text = SettingsFile.render(s)
        XCTAssertEqual(try SettingsFile.parse(text), s)
    }
}

final class QueryTests: XCTestCase {
    private var list: ProjectList {
        ProjectList(programmes: [Programme(name: "Research"), Programme(name: "Teaching")], projects: [
            Project(key: "b", code: "26BB", title: "Beta", programme: "Teaching"),
            Project(key: "a", title: "Alpha", programme: "Research", collaborators: "Smith"),
            Project(key: "c", title: "Gamma", programme: "Research", isActive: false),
            Project(key: "d", title: "Delta"),
        ])
    }

    func testGroupedRows() {
        let r = RowLayout.rows(for: list, query: ProjectQuery(), collapsed: [], lastWorked: [:])
        XCTAssertEqual(r.rows, [
            .programme(name: "Research", count: 1, collapsed: false), .project(key: "a"),
            .programme(name: "Teaching", count: 1, collapsed: false), .project(key: "b"),
            .programme(name: "", count: 1, collapsed: false), .project(key: "d"),
        ])
        XCTAssertEqual(r.included, ["a", "b", "d"])
    }

    func testCollapsedFilteredAndSorted() {
        var q = ProjectQuery(status: .all, sort: .title)
        var r = RowLayout.rows(for: list, query: q, collapsed: ["Research"], lastWorked: [:])
        XCTAssertEqual(r.rows.first, .programme(name: "Research", count: 2, collapsed: true))
        XCTAssertEqual(r.included, ["a", "c", "b", "d"])
        q.grouped = false
        q.search = "smith"
        r = RowLayout.rows(for: list, query: q, collapsed: [], lastWorked: [:])
        XCTAssertEqual(r.rows, [.project(key: "a")])
        q.search = ""
        q.programme = "Research"
        q.sort = .lastWorked
        q.ascending = false
        r = RowLayout.rows(for: list, query: q, collapsed: [], lastWorked: ["c": d("2026-10-01"), "a": d("2026-09-01")])
        XCTAssertEqual(r.included, ["c", "a"])
    }
}

final class WeekLabelTests: XCTestCase {
    func testFlexibleDates() {
        func p(_ s: String, _ o: DateOrder = .dayMonth) -> LocalDate? {
            FlexibleDate.parse(s, order: o, defaultYear: 2026)?.date
        }
        XCTAssertEqual(p("2026-10-05"), d("2026-10-05"))
        XCTAssertEqual(p("2026-10-05 00:00:00"), d("2026-10-05"))
        XCTAssertEqual(p("5/10/2026"), d("2026-10-05"))
        XCTAssertEqual(p("10/5/26", .monthDay), d("2026-10-05"))
        XCTAssertEqual(p("5/10"), d("2026-10-05"))
        XCTAssertEqual(p("Monday, 5th October 2026"), d("2026-10-05"))
        XCTAssertEqual(p("Oct 5, 2026"), d("2026-10-05"))
        XCTAssertEqual(p("w/c 5 Oct"), d("2026-10-05"))
        XCTAssertEqual(p("46300"), d("2026-10-05"))
        XCTAssertNil(p("Week 5"))
        XCTAssertNil(p("Teaching week 3"))
        XCTAssertNil(p("W41"))
    }

    func testImportFromSpreadsheetRows() {
        let pasted = "Week of\tLabel\n5/10/2026\tTeaching wk 9\n\n12/10/2026\tMid-sem break\n14/10/2026\tMid-sem break\nNotes\tx\n"
        let rows = WeekLabelImport.parse(pasted, order: .dayMonth, referenceYear: 2026)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].outcome, .skipped("No date (a heading row?)"))
        XCTAssertEqual(rows[1].outcome, .label(week: d("2026-10-05"), text: "Teaching wk 9"))
        XCTAssertEqual(rows[3].outcome, .skipped("Same week as line 4"))
        let labels = WeekLabelImport.labels(from: rows)
        XCTAssertEqual(labels, [d("2026-10-05"): "Teaching wk 9", d("2026-10-12"): "Mid-sem break"])
    }

    func testYearRollsOverWithoutYears() {
        let rows = WeekLabelImport.parse("21/12\tA\n4/1\tB", order: .dayMonth, referenceYear: 2026)
        XCTAssertEqual(rows[1].outcome, .label(week: d("2027-01-04"), text: "B"))
    }

    func testFileRoundTripAndDisplay() {
        var w = WeekLabels()
        w[d("2026-10-07")] = "Sprint 4"
        XCTAssertEqual(w[d("2026-10-11")], "Sprint 4")
        XCTAssertEqual(w.renderFile(), "week,label\n2026-10-05,Sprint 4\n")
        XCTAssertEqual(WeekLabels.parseFile(w.renderFile()).labels, w)
        XCTAssertEqual(w.display(for: d("2026-10-12"), isoFallback: true).text, "W42")
    }
}

final class ClipboardTests: XCTestCase {
    func testTextToClip() {
        let clip = CellClip(text: "M\tXS\n\tmtg\n")
        XCTAssertEqual(clip?.rows, [[Cell(label: .m), Cell(label: .xs)], [Cell(), Cell(label: .meeting)]])
        let note = CellClip(text: "Wrote the intro.\nSent it to Sam.")
        XCTAssertEqual(note?.rows, [[Cell(note: "Wrote the intro.\nSent it to Sam.")]])
    }

    func testJSONRoundTrip() {
        let clip = CellClip(rows: [[Cell(label: .due, note: "Report"), Cell()]])
        XCTAssertEqual(CellClip(json: clip.json()), clip)
        XCTAssertEqual(clip.tsv, "(!)\t")
    }
}

final class WorkspaceTests: XCTestCase {
    func testSaveLoadAndProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ws = Workspace(root: root)
        try ws.ensureLayout()
        XCTAssertTrue(Workspace.looksLikeWorkspace(root))
        let oct = MonthKey(year: 2026, month: 10)
        try ws.saveMonth(oct, entries: [LogEntry(date: d("2026-10-05"), project: "a", cell: Cell(label: .l))])
        var c = ws.load()
        XCTAssertEqual(c.issues, [])
        XCTAssertEqual(c.log["a", d("2026-10-05")].label, .l)
        XCTAssertFalse(ws.hasExternalChanges())

        // An unreadable month is reported and never overwritten.
        try Data("date,project,label,note\nnot-a-date,a,M,\n".utf8)
            .write(to: root.appendingPathComponent("log/2026/2026-11.csv"))
        XCTAssertTrue(ws.hasExternalChanges())
        c = ws.load()
        XCTAssertEqual(c.issues.map(\.relativePath), ["log/2026/2026-11.csv"])
        XCTAssertThrowsError(try ws.saveMonth(MonthKey(year: 2026, month: 11), entries: []))

        // Emptying a month removes its file.
        try ws.saveMonth(oct, entries: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("log/2026/2026-10.csv").path))
    }
}
