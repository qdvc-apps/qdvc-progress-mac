import AppKit

/// Thin wrappers over AppKit services.
@MainActor
enum Platform {
    /// Opens the Settings window.
    static func openSettings() {
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }

    /// Puts keyboard focus in the window's toolbar search field (the one
    /// `.searchable` adds). Returns false when the window has none. (From
    /// QDVC Nice Mail.)
    @discardableResult
    static func focusSearchField(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return true
        }
        guard let field = searchField(in: window.contentView?.superview ?? window.contentView) else {
            return false
        }
        window.makeFirstResponder(field)
        return true
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField, !field.isHidden { return field }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }
}
