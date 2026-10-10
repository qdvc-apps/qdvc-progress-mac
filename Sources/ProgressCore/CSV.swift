import Foundation

/// Minimal RFC 4180 CSV: comma-separated, fields quoted with `"` when they
/// hold a comma, quote, line break or leading/trailing space, quotes
/// doubled. Files are written with `\n` line ends and read with any.
public enum CSV {
    /// The rows of `text`. A trailing line break does not make an empty row;
    /// blank lines are skipped.
    public static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false
        var chars = Array(text)
        // Drop a UTF-8 byte-order mark, which Excel likes to write.
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0

        func endField() {
            row.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty && !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
            } else if c == separator {
                endField()
            } else if c == "\r\n" || c == "\n" || c == "\r" {
                endRow()
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }

    public static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n")
            || field.contains("\r") || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func render(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") + "\n" }.joined()
    }
}
