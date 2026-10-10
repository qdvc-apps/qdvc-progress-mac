import AppKit
import SwiftUI
import ProgressCore

/// What a note callout shows.
struct NoteCalloutContent: Equatable {
    let title: String
    let subtitle: String
    let note: String
}

/// The callout balloon beside a cell with a note (docs/DESIGN.md §5).
///
/// - Clicking a cell with a note shows it straight away and keeps it
///   ("pinned") until another cell is clicked, a key is pressed, the grid
///   scrolls, or Escape.
/// - Hovering over a cell with a note shows it after `hoverDelay`; it goes
///   `hideDelay` after the pointer leaves the cell.
@MainActor
final class NoteCalloutController {
    static let hoverDelay: TimeInterval = 0.5
    static let hideDelay: TimeInterval = 0.3

    private(set) var ref: CellRef?
    private(set) var isPinned = false
    private(set) var content: NoteCalloutContent?
    private var popover: NSPopover?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    var isShown: Bool { popover?.isShown == true }

    /// Shows the callout for `ref` at `rect` in `view` now.
    func show(_ content: NoteCalloutContent, for ref: CellRef, at rect: NSRect, in view: NSView, pinned: Bool) {
        cancelTimers()
        if isShown, self.ref == ref, self.content == content {
            isPinned = isPinned || pinned
            return
        }
        close()
        let hosting = NSHostingController(rootView: NoteCalloutView(content: content))
        hosting.sizingOptions = [.preferredContentSize]
        let p = NSPopover()
        p.contentViewController = hosting
        p.behavior = .applicationDefined
        p.animates = pinned
        p.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        popover = p
        self.ref = ref
        self.content = content
        isPinned = pinned
    }

    /// The pointer is over a cell with a note: show its callout after a
    /// short pause (unless it is already showing).
    func hover(_ content: NoteCalloutContent, for ref: CellRef, at rect: NSRect, in view: NSView) {
        hideTask?.cancel()
        hideTask = nil
        if isShown && self.ref == ref { return }
        showTask?.cancel()
        showTask = Task { [weak self, weak view] in
            try? await Task.sleep(for: .milliseconds(Int(NoteCalloutController.hoverDelay * 1000)))
            guard !Task.isCancelled, let self, let view, view.window != nil else { return }
            // A pinned callout for another cell gives way to the hovered one.
            self.show(content, for: ref, at: rect, in: view, pinned: false)
        }
    }

    /// The pointer left the cell (or is over one without a note).
    func hoverEnded() {
        showTask?.cancel()
        showTask = nil
        guard isShown, !isPinned, hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(NoteCalloutController.hideDelay * 1000)))
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            if !self.isPinned { self.close() }
        }
    }

    func close() {
        cancelTimers()
        popover?.close()
        popover = nil
        ref = nil
        content = nil
        isPinned = false
    }

    private func cancelTimers() {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = nil
    }
}

/// The callout's contents: the project and day, then the note. A long note
/// scrolls.
struct NoteCalloutView: View {
    let content: NoteCalloutContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.headline)
                .lineLimit(1)
            Text(content.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
                .padding(.vertical, 2)
            ViewThatFits(in: .vertical) {
                noteText
                ScrollView { noteText }
            }
            .frame(maxHeight: 280)
        }
        .padding(12)
        .frame(width: 290, alignment: .leading)
    }

    private var noteText: some View {
        Text(content.note)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
