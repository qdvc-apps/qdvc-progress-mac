import Foundation

/// A rectangle of copied cells (rows top to bottom, days left to right),
/// as it travels on the pasteboard.
public struct CellClip: Codable, Equatable {
    public var rows: [[Cell]]

    public init(rows: [[Cell]]) {
        let width = rows.map(\.count).max() ?? 0
        self.rows = rows.map { $0 + Array(repeating: Cell(), count: width - $0.count) }
    }

    /// The pasteboard type of the app's own copies.
    public static let pasteboardType = "org.qdvc.progress.cells"

    public var height: Int { rows.count }
    public var width: Int { rows.first?.count ?? 0 }
    public var isSingleCell: Bool { height == 1 && width == 1 }

    public func cell(row: Int, column: Int) -> Cell {
        guard row >= 0, row < height, column >= 0, column < width else { return Cell() }
        return rows[row][column]
    }

    public func json() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public init?(json: Data) {
        guard let clip = try? JSONDecoder().decode(CellClip.self, from: json), clip.height > 0 else { return nil }
        self = clip
    }

    /// The labels as tab-separated text, for pasting into a spreadsheet.
    /// A cell with only a note gives its note (on one line).
    public var tsv: String {
        rows.map { row in
            row.map { cell in
                cell.label?.text ?? cell.note.split(whereSeparator: \.isNewline).joined(separator: " ")
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Text from another app. Tab-separated labels (as a spreadsheet copies
    /// them) become a rectangle of labels; with tabs, other text in a field
    /// becomes that cell's note. Text without tabs that is not all labels
    /// becomes one cell whose note is the whole text.
    public init?(text: String) {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalised.components(separatedBy: "\n")
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        let grid = lines.map { $0.components(separatedBy: "\t") }
        let fields = grid.flatMap { $0 }.map { $0.trimmingCharacters(in: .whitespaces) }
        let allLabels = fields.allSatisfy { $0.isEmpty || CellLabel(lenient: $0) != nil }
        if allLabels || normalised.contains("\t") {
            self.init(rows: grid.map { row in
                row.map { field in
                    let t = field.trimmingCharacters(in: .whitespaces)
                    if let label = CellLabel(lenient: t) { return Cell(label: label) }
                    return Cell(note: t)
                }
            })
        } else {
            let note = normalised.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return nil }
            self.init(rows: [[Cell(note: note)]])
        }
    }
}
