import Foundation

/// A calendar day with no time zone (a `yyyy-mm-dd` in a diary), as stored
/// in the workspace files. Weeks run Monday to Sunday throughout the app.
public struct LocalDate: Hashable, Comparable, CustomStringConvertible, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= LocalDate.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-mm-dd` (surrounding whitespace allowed).
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, (1...2).contains(parts[1].count),
              (1...2).contains(parts[2].count),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    public static func today(calendar: Calendar = .current) -> LocalDate {
        LocalDate(Date(), calendar: calendar)
    }

    /// `yyyy-mm-dd`.
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    // Codable as the `yyyy-mm-dd` string (used on the pasteboard).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let d = LocalDate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a yyyy-mm-dd date: \(text)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var daysInMonth: Int { LocalDate.daysIn(month: month, year: year) }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The inverse of `ordinal` (`civil_from_days`).
    public init(ordinal: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(ordinal: ordinal + days)
    }

    /// The same day of the month `months` later (clamped to the month's
    /// length, so 31 January + 1 month is 28 or 29 February).
    public func adding(months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let y = index / 12
        let m = index % 12 + 1
        return LocalDate(year: y, month: m, day: min(day, LocalDate.daysIn(month: m, year: y)))!
    }

    /// Whole days from `self` to `other` (negative if `other` is earlier).
    public func days(to other: LocalDate) -> Int {
        other.ordinal - ordinal
    }

    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    /// 1 = Monday … 7 = Sunday (ISO 8601).
    public var isoWeekday: Int {
        // 1970-01-01 was a Thursday (4).
        let r = (ordinal + 3) % 7
        return (r < 0 ? r + 7 : r) + 1
    }

    public var isWeekend: Bool { isoWeekday >= 6 }

    /// The Monday of the week containing this day.
    public var monday: LocalDate { adding(days: 1 - isoWeekday) }

    /// The ISO 8601 week number (1…53) and the year it belongs to.
    public var isoWeek: (year: Int, week: Int) {
        let thursday = adding(days: 4 - isoWeekday)
        let jan1 = LocalDate(year: thursday.year, month: 1, day: 1)!
        return (thursday.year, (jan1.days(to: thursday)) / 7 + 1)
    }

    /// This day at midnight in `calendar`'s time zone.
    public func date(calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: TimeInterval(ordinal) * 86400)
    }

    public func isSameMonth(as other: LocalDate) -> Bool {
        year == other.year && month == other.month
    }

    /// The `yyyy-mm` month this day belongs to.
    public var monthKey: MonthKey { MonthKey(year: year, month: month) }
}

/// A calendar month, as used to name log files (`log/2026/2026-10.csv`).
public struct MonthKey: Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// Parses `yyyy-mm`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public static func < (a: MonthKey, b: MonthKey) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }

    public var firstDay: LocalDate { LocalDate(year: year, month: month, day: 1)! }
    public var lastDay: LocalDate {
        LocalDate(year: year, month: month, day: LocalDate.daysIn(month: month, year: year))!
    }
}

/// An inclusive run of days.
public struct DayRange: Hashable, Codable {
    public var from: LocalDate
    public var to: LocalDate

    public init(from: LocalDate, to: LocalDate) {
        self.from = min(from, to)
        self.to = max(from, to)
    }

    public func contains(_ d: LocalDate) -> Bool { from <= d && d <= to }

    public var dayCount: Int { from.days(to: to) + 1 }

    public var days: [LocalDate] { (0..<dayCount).map { from.adding(days: $0) } }

    public func overlapsOrTouches(_ other: DayRange) -> Bool {
        from.ordinal <= other.to.ordinal + 1 && other.from.ordinal <= to.ordinal + 1
    }
}
