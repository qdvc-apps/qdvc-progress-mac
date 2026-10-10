import AppKit
import SwiftUI
import ProgressCore

/// The grid in SwiftUI. It redraws when the model's revision changes, and
/// scrolls or takes the focus when asked to.
struct GridRepresentable: NSViewRepresentable {
    let model: AppModel
    let revision: Int
    let scrollTarget: ScrollTarget?
    let focusRequest: Int

    func makeNSView(context: Context) -> GridContainerView {
        GridContainerView(model: model)
    }

    func updateNSView(_ view: GridContainerView, context: Context) {
        view.reloadIfNeeded()
        view.handle(scrollTarget)
        view.handleFocusRequest(focusRequest)
    }
}

/// The spreadsheet: a scrolling body of day cells, with the date header,
/// the project columns and the totals frozen around it (docs/DESIGN.md §3).
/// The body is the scroll view's document; the frozen panes are separate
/// views that follow its scroll offset.
@MainActor
final class GridContainerView: NSView {
    let model: AppModel
    let scrollView = NSScrollView()
    let body = GridBodyView()
    let header = GridHeaderView()
    let left = GridLeftView()
    let footer = GridFooterView()
    let corner = GridCornerView()
    let footerCorner = GridFooterCornerView()

    private(set) var metrics = GridMetrics()
    private var lastRevision = -1
    private var lastRangeStart: LocalDate?
    private var handledScrollTarget: UUID?
    private var handledFocusRequest = 0
    private var pendingScrollDate: LocalDate?
    private var isAdjusting = false

    override var isFlipped: Bool { true }

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))

        scrollView.documentView = body
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)

        for pane in [header, left, footer, corner, footerCorner] as [GridPaneView] {
            pane.container = self
            addSubview(pane)
        }
        body.container = self

        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Start with the keyboard in the grid, ready for typing labels.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !(window.firstResponder is NSText) else { return }
            window.makeFirstResponder(self.body)
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let lw = min(metrics.leftWidth, max(120, w - 120))
        let top = metrics.headerHeight, bottom = metrics.footerHeight
        let midHeight = max(0, h - top - bottom)
        scrollView.frame = NSRect(x: lw, y: top, width: max(0, w - lw), height: midHeight)
        header.frame = NSRect(x: lw, y: 0, width: max(0, w - lw), height: top)
        corner.frame = NSRect(x: 0, y: 0, width: lw, height: top)
        left.frame = NSRect(x: 0, y: top, width: lw, height: midHeight)
        footer.frame = NSRect(x: lw, y: h - bottom, width: max(0, w - lw), height: bottom)
        footerCorner.frame = NSRect(x: 0, y: h - bottom, width: lw, height: bottom)
        applyPendingScroll()
        syncPanes()
    }

    /// The scroll offset of the body.
    var offset: NSPoint { scrollView.contentView.bounds.origin }

    /// The width of the body's visible area (the header and footer align
    /// with it).
    var visibleBodyWidth: CGFloat { scrollView.contentView.bounds.width }

    // MARK: Reloading

    func reloadIfNeeded() {
        guard model.revision != lastRevision else { return }
        reload()
    }

    /// Recomputes the geometry and redraws, keeping the same day at the left
    /// edge (the range may have grown at the start, or the zoom changed).
    func reload() {
        isAdjusting = true
        defer { isAdjusting = false }
        let clip = scrollView.contentView
        var anchorOrdinal: Double?
        if let start = lastRangeStart, metrics.cellWidth > 0 {
            anchorOrdinal = Double(start.ordinal) + Double(clip.bounds.minX / metrics.cellWidth)
        }
        let oldLeftWidth = metrics.leftWidth
        metrics = GridMetrics(model: model)
        lastRevision = model.revision
        lastRangeStart = model.rangeStart

        body.frame = NSRect(x: 0, y: 0, width: max(1, metrics.contentWidth), height: max(1, metrics.contentHeight))
        if let anchor = anchorOrdinal {
            let x = CGFloat(anchor - Double(model.rangeStart.ordinal)) * metrics.cellWidth
            if abs(x - clip.bounds.minX) > 0.5 {
                scrollBody(to: NSPoint(x: x, y: clip.bounds.minY))
            }
        }
        if oldLeftWidth != metrics.leftWidth { needsLayout = true }
        body.needsDisplay = true
        for pane in [header, left, footer, corner, footerCorner] as [GridPaneView] { pane.needsDisplay = true }
        body.window?.invalidateCursorRects(for: corner)
    }

    private func scrollBody(to point: NSPoint) {
        let clip = scrollView.contentView
        let maxX = max(0, metrics.contentWidth - clip.bounds.width)
        let maxY = max(0, metrics.contentHeight - clip.bounds.height)
        let p = NSPoint(x: min(max(0, point.x), maxX), y: min(max(0, point.y), maxY))
        clip.scroll(to: p)
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Scrolling

    func handle(_ target: ScrollTarget?) {
        guard let target, target.id != handledScrollTarget else { return }
        handledScrollTarget = target.id
        pendingScrollDate = target.date
        applyPendingScroll()
    }

    /// Shows `date` with the week before it to its left.
    private func applyPendingScroll() {
        guard let date = pendingScrollDate, scrollView.contentView.bounds.width > 0 else { return }
        pendingScrollDate = nil
        let day = model.dayIndex(of: date)
        isAdjusting = true
        scrollBody(to: NSPoint(x: metrics.dayX(day - 7), y: offset.y))
        isAdjusting = false
        syncPanes()
    }

    func handleFocusRequest(_ n: Int) {
        guard n != handledFocusRequest else { return }
        handledFocusRequest = n
        window?.makeFirstResponder(body)
    }

    /// Makes the selected cell visible (after a keyboard move).
    func revealFocus() {
        guard let f = model.focusRef, let row = model.row(of: f.project) else { return }
        let rect = metrics.cellRect(row: row, day: model.dayIndex(of: f.date))
        _ = body.scrollToVisible(rect.insetBy(dx: -metrics.cellWidth, dy: -4))
    }

    @objc private func clipBoundsChanged(_ note: Notification) {
        syncPanes()
        guard !isAdjusting else { return }
        // Grow the range of days when scrolling near either end.
        let b = scrollView.contentView.bounds
        let margin = 14 * metrics.cellWidth
        if b.minX < margin && model.rangeStart.year > 1900 {
            model.extendEarlier()
            reload()
        } else if b.maxX > metrics.contentWidth - margin {
            model.extendLater()
            reload()
        }
    }

    private func syncPanes() {
        let o = offset
        header.offsetX = o.x
        footer.offsetX = o.x
        left.offsetY = o.y
        header.needsDisplay = true
        footer.needsDisplay = true
        left.needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        scrollView.scrollWheel(with: event)
    }
}

/// A frozen pane around the body. Scroll gestures over it scroll the body.
@MainActor
class GridPaneView: NSView {
    weak var container: GridContainerView?
    var model: AppModel? { container?.model }
    var metrics: GridMetrics { container?.metrics ?? GridMetrics() }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        container?.scrollView.scrollWheel(with: event)
    }

    /// Clicking a pane keeps the keyboard focus in the grid.
    func focusGrid() {
        guard let c = container else { return }
        window?.makeFirstResponder(c.body)
    }
}
