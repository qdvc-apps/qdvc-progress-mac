import AppKit
import ProgressCore

/// The grid's geometry, recomputed whenever the model's revision changes.
/// Day columns and rows are measured in the body's coordinates: day 0 at
/// x = 0, the first row at y = 0.
struct GridMetrics {
    static let headerRows: [CGFloat] = [22, 20, 17, 18]   // month, week, day, weekday
    static let footerRows: [CGFloat] = [22, 22]           // daily totals, week and weekend
    static let rowHeight: CGFloat = 22
    static let programmeRowHeight: CGFloat = 26

    var cellWidth: CGFloat = 30
    var dayCount = 0
    /// The visible left columns, each with its x and width.
    var columns: [(column: LeftColumn, x: CGFloat, width: CGFloat)] = []
    /// The top of each row, plus the bottom of the last.
    var rowTops: [CGFloat] = [0]

    var headerHeight: CGFloat { GridMetrics.headerRows.reduce(0, +) }
    var footerHeight: CGFloat { GridMetrics.footerRows.reduce(0, +) }
    var leftWidth: CGFloat { columns.last.map { $0.x + $0.width } ?? 0 }
    var contentWidth: CGFloat { CGFloat(dayCount) * cellWidth }
    var contentHeight: CGFloat { rowTops.last ?? 0 }
    var rowCount: Int { rowTops.count - 1 }

    /// The top of header row `i`.
    static func headerTop(_ i: Int) -> CGFloat { headerRows.prefix(i).reduce(0, +) }

    @MainActor
    init(model: AppModel) {
        cellWidth = CGFloat(model.cellWidth)
        dayCount = model.dayCount
        var x: CGFloat = 0
        for c in model.visibleColumns {
            let w = CGFloat(model.width(of: c))
            columns.append((column: c, x: x, width: w))
            x += w
        }
        var tops: [CGFloat] = [0]
        var y: CGFloat = 0
        for row in model.rows {
            if case .programme = row { y += GridMetrics.programmeRowHeight } else { y += GridMetrics.rowHeight }
            tops.append(y)
        }
        rowTops = tops
    }

    init() {}

    func rowRect(_ row: Int, width: CGFloat) -> NSRect {
        NSRect(x: 0, y: rowTops[row], width: width, height: rowTops[row + 1] - rowTops[row])
    }

    func dayX(_ day: Int) -> CGFloat { CGFloat(day) * cellWidth }

    func cellRect(row: Int, day: Int) -> NSRect {
        NSRect(x: dayX(day), y: rowTops[row], width: cellWidth, height: rowTops[row + 1] - rowTops[row])
    }

    /// The row at `y`, if any.
    func row(at y: CGFloat) -> Int? {
        guard rowCount > 0, y >= 0, y < contentHeight else { return nil }
        var lo = 0, hi = rowCount - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if rowTops[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The day at `x`, if any.
    func day(at x: CGFloat) -> Int? {
        guard x >= 0, cellWidth > 0 else { return nil }
        let d = Int(x / cellWidth)
        return d < dayCount ? d : nil
    }

    /// The days that overlap `minX..<maxX`.
    func days(from minX: CGFloat, to maxX: CGFloat) -> Range<Int> {
        guard dayCount > 0, cellWidth > 0 else { return 0..<0 }
        let lo = max(0, Int(floor(minX / cellWidth)))
        let hi = min(dayCount, Int(ceil(maxX / cellWidth)))
        return lo < hi ? lo..<hi : 0..<0
    }

    /// The rows that overlap `minY..<maxY`.
    func rows(from minY: CGFloat, to maxY: CGFloat) -> Range<Int> {
        guard rowCount > 0 else { return 0..<0 }
        let lo = row(at: max(0, minY)) ?? (minY < 0 ? 0 : rowCount)
        let hi = (row(at: min(maxY, contentHeight - 0.5)) ?? (maxY <= 0 ? -1 : rowCount - 1)) + 1
        return lo < hi ? lo..<hi : 0..<0
    }

    /// The left column whose right edge is within a few points of `x`.
    func columnDivider(near x: CGFloat) -> LeftColumn? {
        columns.first { abs($0.x + $0.width - x) <= 3 }?.column
    }

    func column(at x: CGFloat) -> LeftColumn? {
        columns.first { x >= $0.x && x < $0.x + $0.width }?.column
    }
}
