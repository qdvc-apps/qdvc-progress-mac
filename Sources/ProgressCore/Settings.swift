import Foundation
import Yams

/// A key the app does not know, kept as read so that saving never loses
/// what someone (or a newer version) put in a file.
public struct ExtraField: Equatable {
    public let key: String
    public let value: Node

    public init(key: String, value: Node) {
        self.key = key
        self.value = value
    }
}

/// A named mapping from the five work sizes to numbers.
public struct SizePreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let values: [Int]
    public let detail: String

    /// XS = 1, S = 2, M = 3, L = 4, XL = 5. The default.
    public static let linear = SizePreset(
        id: "linear", name: "Linear", values: [1, 2, 3, 4, 5],
        detail: "Each size is one step more than the last. Simple to add up in your head.")

    /// XS = 1, S = 2, M = 3, L = 5, XL = 8, the planning-poker scale.
    public static let fibonacci = SizePreset(
        id: "fibonacci", name: "Fibonacci", values: [1, 2, 3, 5, 8],
        detail: "The big days weigh more: an XL day counts as much as eight XS days. Felt effort grows faster than linearly, which is why agile teams estimate with this scale.")

    /// XS = 1, S = 2, M = 4, L = 8, XL = 16.
    public static let doubling = SizePreset(
        id: "doubling", name: "Doubling", values: [1, 2, 4, 8, 16],
        detail: "Each size is twice the last. Makes one exhausting day stand out sharply in the totals.")

    public static let all: [SizePreset] = [.linear, .fibonacci, .doubling]
}

/// How labels turn into workload numbers, and how the totals are coloured.
/// Saved in the workspace (`progress.yml`) so it travels with the data.
public struct WorkloadSettings: Equatable {
    /// The numbers for XS, S, M, L, XL, in that order.
    public var sizeValues: [Int]
    /// The size a meeting counts as.
    public var meetingSize: CellLabel
    public var dueValue: Int
    public var plannedValue: Int
    /// The daily total at which the totals colour is at its deepest. The
    /// working week (Monday–Friday) peaks at five times this, the weekend at
    /// twice it.
    public var dayPeak: Int
    public var extras: [ExtraField]

    public init(sizeValues: [Int] = SizePreset.linear.values, meetingSize: CellLabel = .m,
                dueValue: Int = 0, plannedValue: Int = 0, dayPeak: Int = 15,
                extras: [ExtraField] = []) {
        self.sizeValues = WorkloadSettings.normalised(sizeValues)
        self.meetingSize = meetingSize.isSize ? meetingSize : .m
        self.dueValue = dueValue
        self.plannedValue = plannedValue
        self.dayPeak = max(1, dayPeak)
        self.extras = extras
    }

    static func normalised(_ values: [Int]) -> [Int] {
        var v = Array(values.prefix(5))
        let fallback = SizePreset.linear.values
        while v.count < 5 { v.append(fallback[v.count]) }
        return v
    }

    /// The number a label adds to the totals.
    public func value(of label: CellLabel?) -> Int {
        guard let label else { return 0 }
        if let i = label.sizeIndex { return sizeValues[i] }
        switch label {
        case .meeting: return sizeValues[meetingSize.sizeIndex ?? 2]
        case .due: return dueValue
        case .planned: return plannedValue
        default: return 0   // tick, cross, info
        }
    }

    public var matchingPreset: SizePreset? {
        SizePreset.all.first { $0.values == sizeValues }
    }

    public var weekPeak: Int { dayPeak * 5 }
    public var weekendPeak: Int { dayPeak * 2 }
}
