import Foundation
import Yams

public enum FileError: Error, Equatable, CustomStringConvertible {
    case invalidYAML(String)
    case notAMapping
    case notUTF8
    case invalid(String)

    public var description: String {
        switch self {
        case .invalidYAML(let detail): return "The file is not valid YAML (\(detail))."
        case .notAMapping: return "The file does not hold a YAML mapping."
        case .notUTF8: return "The file is not UTF-8 text."
        case .invalid(let detail): return detail
        }
    }
}

/// Reading and writing YAML with Yams' node API, which keeps key order and
/// lets unknown keys be written back as they were read.
enum YamlIO {
    /// The top-level mapping as (key, value) pairs in file order. An empty
    /// file is an empty mapping.
    static func mappingPairs(_ text: String) throws -> [(String, Node)] {
        let node: Node?
        do {
            node = try Yams.compose(yaml: text)
        } catch {
            throw FileError.invalidYAML(String(describing: error).split(separator: "\n").first.map(String.init) ?? "")
        }
        guard let root = node else { return [] }
        return try pairs(root)
    }

    static func pairs(_ node: Node) throws -> [(String, Node)] {
        if isNull(node) { return [] }
        guard let mapping = node.mapping else { throw FileError.notAMapping }
        return mapping.map { ($0.key.string ?? "", $0.value) }
    }

    /// A scalar's text, or nil for null and for non-scalars.
    static func string(_ node: Node) -> String? {
        guard let scalar = node.scalar else { return nil }
        if isNull(node) { return nil }
        return scalar.string
    }

    static func int(_ node: Node) -> Int? {
        string(node).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func bool(_ node: Node) -> Bool? {
        guard let s = string(node)?.lowercased() else { return nil }
        if ["true", "yes", "on", "y"].contains(s) { return true }
        if ["false", "no", "off", "n"].contains(s) { return false }
        return nil
    }

    static func isNull(_ node: Node) -> Bool {
        guard let scalar = node.scalar else { return false }
        if scalar.style != .plain && scalar.style != .any { return false }
        return ["", "~", "null", "Null", "NULL"].contains(scalar.string)
    }

    /// A sequence's items; a lone scalar counts as a one-item sequence.
    static func sequence(_ node: Node) -> [Node] {
        if let seq = node.sequence { return Array(seq) }
        if isNull(node) { return [] }
        return [node]
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static func key(_ k: String) -> Node { Node(k, Tag(.implicit), .plain) }

    static func number(_ v: Int) -> Node { Node(String(v), Tag(.implicit), .plain) }

    static func boolean(_ v: Bool) -> Node { Node(v ? "true" : "false", Tag(.implicit), .plain) }

    static func date(_ d: LocalDate) -> Node { Node(d.iso, Tag(.implicit), .plain) }

    /// A string scalar in the plainest style that reads back as the same
    /// string in YAML 1.1 and 1.2 readers: literal (`|`) for several lines,
    /// single-quoted where a plain scalar would read as something else.
    static func str(_ s: String) -> Node {
        if s.contains("\n") { return Node(s, Tag(.implicit), .literal) }
        return Node(s, Tag(.implicit), needsQuotes(s) ? .singleQuoted : .plain)
    }

    static func needsQuotes(_ s: String) -> Bool {
        if s.isEmpty || s != s.trimmingCharacters(in: .whitespaces) { return true }
        let reserved: Set<String> = ["y", "n", "yes", "no", "true", "false", "on", "off", "null", "~"]
        if reserved.contains(s.lowercased()) { return true }
        // Anything starting like a number, date, time or YAML indicator
        // (a project ID such as 26XY starts with a digit, so it is quoted).
        if let first = s.unicodeScalars.first, "0123456789+-.:?!&*#|>'\"%@`,[]{}=".unicodeScalars.contains(first) {
            return true
        }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        return false
    }

    static func emit(_ node: Node) -> String {
        do {
            return try Yams.serialize(node: node, indent: 2, width: -1, allowUnicode: true, lineBreak: .ln)
        } catch {
            // Serialising a tree built from strings cannot fail in practice.
            return ""
        }
    }
}
