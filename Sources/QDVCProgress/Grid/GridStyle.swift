import AppKit
import SwiftUI
import ProgressCore

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Linear blend towards `other` (t = 0 is self, 1 is other), in sRGB.
    func mixed(with other: NSColor, _ t: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        let u = max(0, min(1, t))
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * u,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * u,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * u,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * u)
    }
}

/// The grid's colours (docs/DESIGN.md §4). Work sizes are a single-hue blue
/// heat map, from baby blue (XS) to navy (XL); totals are a salmon-to-red
/// heat map; meetings are bright green.
@MainActor
enum GridStyle {
    static let sizeFills: [NSColor] = [
        NSColor(hex: 0xCFE8FB),   // XS, baby blue
        NSColor(hex: 0x9CCBF2),   // S
        NSColor(hex: 0x5A9BDB),   // M
        NSColor(hex: 0x2B5EA8),   // L
        NSColor(hex: 0x10275C),   // XL, navy
    ]
    static let meetingFill = NSColor(hex: 0x2EDB4F)
    static let dueFill = NSColor(hex: 0xFFB020)
    static let plannedStroke = NSColor(hex: 0x5A9BDB)
    static let noteMarker = NSColor(hex: 0xE5484D)
    static let todayYellow = NSColor(hex: 0xFFD60A)
    static let totalLow = NSColor(hex: 0xFFE3D8)
    static let totalHigh = NSColor(hex: 0xC62F2F)

    static func fill(for label: CellLabel) -> NSColor? {
        if let i = label.sizeIndex { return sizeFills[i] }
        switch label {
        case .meeting: return meetingFill
        case .due: return dueFill
        default: return nil
        }
    }

    static func text(for label: CellLabel) -> NSColor {
        switch label {
        case .l, .xl: return .white
        case .planned: return .secondaryLabelColor
        default: return NSColor(hex: 0x111111)
        }
    }

    /// The fill of a total, or nil for zero.
    static func totalFill(level: Double) -> NSColor? {
        guard level > 0 else { return nil }
        // Even a small total is visibly tinted.
        return totalLow.mixed(with: totalHigh, CGFloat(0.12 + 0.88 * level))
    }

    static func totalText(level: Double) -> NSColor {
        level > 0.55 ? .white : NSColor(hex: 0x3A1A14)
    }

    // SwiftUI versions, for the inspector and Settings.
    static func swiftUIFill(for label: CellLabel) -> Color {
        fill(for: label).map(Color.init(nsColor:)) ?? Color.clear
    }

    static func swiftUIText(for label: CellLabel) -> Color {
        Color(nsColor: text(for: label))
    }

    // MARK: Fonts and text

    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let totalFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let headerFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let headerBoldFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let monthFont = NSFont.systemFont(ofSize: 12, weight: .bold)
    static let rowFont = NSFont.systemFont(ofSize: 12)
    static let rowSecondaryFont = NSFont.systemFont(ofSize: 11)
    static let codeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let programmeFont = NSFont.systemFont(ofSize: 12, weight: .bold)
    static let italicFont: NSFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 10.5), toHaveTrait: .italicFontMask)
    static let italicRowFont: NSFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)

    /// Draws `text` centred in `rect` (one line, not truncated).
    static func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: p, withAttributes: attrs)
    }

    /// Draws `text` on one line in `rect`, vertically centred, truncated
    /// with an ellipsis if it does not fit.
    static func drawLine(_ text: String, in rect: NSRect, font: NSFont, color: NSColor,
                         alignment: NSTextAlignment = .left) {
        guard rect.width > 4 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let height = ceil(font.ascender - font.descender + font.leading)
        let r = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        (text as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Diagonal hatching over `rect`, for inactive days.
    static func hatch(_ rect: NSRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        let step: CGFloat = 6
        // Anchor the pattern to whole multiples of the step, so neighbouring
        // spans line up.
        var x = (rect.minX - rect.height).rounded(.down)
        x -= x.truncatingRemainder(dividingBy: step) + step
        while x < rect.maxX {
            ctx.move(to: CGPoint(x: x, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Weekday letters, Monday first.
    static let weekdayLetters = ["M", "Tu", "W", "Th", "Fr", "Sa", "Su"]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()

    private static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static var monthTitles: [MonthKey: String] = [:]

    static func monthTitle(_ m: MonthKey) -> String {
        if let t = monthTitles[m] { return t }
        let t = monthFormatter.string(from: m.firstDay.date())
        monthTitles[m] = t
        return t
    }

    /// "Fri 9 Oct 2026".
    static func longDay(_ d: LocalDate) -> String { longDayFormatter.string(from: d.date()) }

    /// "9 Oct".
    static func shortDay(_ d: LocalDate) -> String { shortDayFormatter.string(from: d.date()) }

    /// "5 Oct – 16 Oct 2026".
    static func range(_ r: DayRange) -> String {
        if r.from == r.to { return longDay(r.from) }
        return "\(shortDay(r.from)) \u{2013} \(shortDay(r.to)) \(r.to.year)"
    }
}

/// A menu item that runs a closure. Used for the grid's context menus.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", checked: Bool = false, enabled: Bool = true,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        keyEquivalentModifierMask = []
        state = checked ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() { handler() }
}

extension NSMenu {
    /// A menu whose items are enabled or disabled as created.
    static func manual(_ title: String = "") -> NSMenu {
        let m = NSMenu(title: title)
        m.autoenablesItems = false
        return m
    }

    func add(_ item: NSMenuItem) { addItem(item) }
    func separator() { addItem(.separator()) }

    func submenu(_ title: String, _ build: (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu.manual(title)
        build(sub)
        item.submenu = sub
        addItem(item)
    }
}
