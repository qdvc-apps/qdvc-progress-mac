import Foundation

/// What a day-cell says: a work size (XS…XL, a subjective measure of the
/// effort a day's work took) or one of the special labels. A cell holds at
/// most one label (docs/DESIGN.md §3).
public enum CellLabel: String, CaseIterable, Identifiable, Codable {
    case xs = "XS"
    case s = "S"
    case m = "M"
    case l = "L"
    case xl = "XL"
    /// A meeting took place that day.
    case meeting = "mtg"
    /// A due date.
    case due = "(!)"
    /// Work planned for that day.
    case planned = "(P)"
    /// Emblems: something done or confirmed, something cancelled or
    /// refused, and something to note. Like the due date, they are drawn
    /// as a coloured circle on a blank cell and add nothing to the totals.
    case tick = "(ok)"
    case cross = "(x)"
    case info = "(i)"

    public var id: String { rawValue }

    /// The five work sizes, smallest first.
    public static let sizes: [CellLabel] = [.xs, .s, .m, .l, .xl]
    public static let specials: [CellLabel] = [.meeting, .planned, .due, .tick, .cross, .info]

    /// The labels drawn as a coloured circle with a symbol in it.
    public var isEmblem: Bool {
        switch self {
        case .due, .tick, .cross, .info: return true
        default: return false
        }
    }

    public var isSize: Bool { sizeIndex != nil }

    /// 0 for XS … 4 for XL; nil for the special labels.
    public var sizeIndex: Int? {
        switch self {
        case .xs: return 0
        case .s: return 1
        case .m: return 2
        case .l: return 3
        case .xl: return 4
        default: return nil
        }
    }

    /// The text written in the log file and shown in the grid.
    public var text: String { rawValue }

    /// A longer name, for menus and the inspector.
    public var title: String {
        switch self {
        case .xs: return "Extra Small"
        case .s: return "Small"
        case .m: return "Medium"
        case .l: return "Large"
        case .xl: return "Extra Large"
        case .meeting: return "Meeting"
        case .due: return "Due Date"
        case .planned: return "Planned"
        case .tick: return "Tick"
        case .cross: return "Cross"
        case .info: return "Information"
        }
    }

    /// The key that sets this label when the grid has keyboard focus.
    public var key: Character {
        switch self {
        case .xs: return "1"
        case .s: return "2"
        case .m: return "3"
        case .l: return "4"
        case .xl: return "5"
        case .meeting: return "m"
        case .due: return "!"
        case .planned: return "p"
        case .tick: return "v"
        case .cross: return "x"
        case .info: return "?"
        }
    }

    /// Reads a label as written in a log file or pasted from a spreadsheet.
    /// Case and surrounding brackets or spaces are forgiven, so `xs`, `Mtg`,
    /// `!`, `due`, `p`, `(p)`, `ok`, `✓`, `x` and `i` are all understood.
    /// Nil for anything else.
    public init?(lenient text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "xs": self = .xs
        case "s": self = .s
        case "m": self = .m
        case "l": self = .l
        case "xl": self = .xl
        case "mtg", "meeting": self = .meeting
        case "(!)", "!", "due": self = .due
        case "(p)", "p", "planned", "plan": self = .planned
        case "(ok)", "ok", "tick", "done", "\u{2713}", "\u{2714}", "(\u{2713})", "(\u{2714})", "(v)": self = .tick
        case "(x)", "x", "cross", "\u{2717}", "\u{2718}", "\u{00D7}", "(\u{2717})", "(\u{2718})": self = .cross
        case "(i)", "i", "info", "\u{2139}", "\u{2139}\u{FE0F}": self = .info
        default: return nil
        }
    }
}

/// One project's entry for one day: a label, a note, or both.
public struct Cell: Equatable, Codable {
    public var label: CellLabel?
    public var note: String

    public init(label: CellLabel? = nil, note: String = "") {
        self.label = label
        self.note = note
    }

    public var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var isEmpty: Bool { label == nil && !hasNote }
}

/// Which parts of a copied cell Paste writes.
public enum PasteMode: String, CaseIterable, Identifiable {
    case both
    case label
    case note

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .both: return "Label and Note"
        case .label: return "Label Only"
        case .note: return "Note Only"
        }
    }

    public var includesLabel: Bool { self != .note }
    public var includesNote: Bool { self != .label }

    /// `source` written over `target` in this mode.
    public func apply(_ source: Cell, onto target: Cell) -> Cell {
        var out = target
        if includesLabel { out.label = source.label }
        if includesNote { out.note = source.note }
        return out
    }
}
