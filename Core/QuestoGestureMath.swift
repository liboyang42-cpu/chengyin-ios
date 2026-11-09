import Foundation

// Pure gesture maths for the Questo polish wave (qx-u4), used by App/QuestoInteractionKit.swift.
// Thresholds match the mini-program lane qx-u1. Native SwiftUI sheets already drag, dismiss and
// rubber-band by themselves; this file covers only what the system does not: sheet heights and the
// floating corner widget. Velocity is in points per second, distances in points.

/// Sheet heights from the shared brief: peek / half / full are at most 30 / 60 / 80 % of the screen.
public enum QuestoSheetSize: CaseIterable, Sendable {
    case peek, half, full
    public var fraction: Double {
        switch self {
        case .peek: return 0.3
        case .half: return 0.6
        case .full: return 0.8
        }
    }
}

public enum QuestoRubberBand {
    /// Travel past a limit keeps a quarter of the finger's offset, then springs back on release.
    public static let resistance = 0.25
    public static func resisted(_ overshoot: Double) -> Double { overshoot * resistance }

    /// Clamps `value` into `range`; any overshoot is resisted, not cut. Reduced motion clamps hard.
    public static func clamp(_ value: Double, to range: ClosedRange<Double>, reduceMotion: Bool = false) -> Double {
        if value < range.lowerBound { return reduceMotion ? range.lowerBound : range.lowerBound + resisted(value - range.lowerBound) }
        if value > range.upperBound { return reduceMotion ? range.upperBound : range.upperBound + resisted(value - range.upperBound) }
        return value
    }
}

/// Picture-in-picture style corner snapping for a floating player, like iOS.
public enum QuestoCornerSnap {
    public enum Corner: CaseIterable, Sendable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// UIScrollView's normal deceleration rate (0.998 per millisecond).
    public static let decelerationRate = 0.998

    /// Distance a fling would still travel, in points: v / 1000 × r / (1 − r).
    public static func projection(velocity: Double, decelerationRate: Double = decelerationRate) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Centre of `item` when parked in `corner` inside `bounds`, already inset by safe area and bars.
    public static func center(of corner: Corner, item: (width: Double, height: Double),
                              bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> (x: Double, y: Double) {
        let left = bounds.minX + item.width / 2, right = bounds.maxX - item.width / 2
        let top = bounds.minY + item.height / 2, bottom = bounds.maxY - item.height / 2
        switch corner {
        case .topLeading: return (left, top)
        case .topTrailing: return (right, top)
        case .bottomLeading: return (left, bottom)
        case .bottomTrailing: return (right, bottom)
        }
    }

    /// The corner nearest the point the item would coast to after release.
    public static func target(position: (x: Double, y: Double), velocity: (x: Double, y: Double),
                              item: (width: Double, height: Double),
                              bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> Corner {
        let projected = (x: position.x + projection(velocity: velocity.x), y: position.y + projection(velocity: velocity.y))
        var best = Corner.bottomTrailing, bestDistance = Double.infinity
        for corner in Corner.allCases {
            let c = center(of: corner, item: item, bounds: bounds)
            let distance = (c.x - projected.x) * (c.x - projected.x) + (c.y - projected.y) * (c.y - projected.y)
            if distance < bestDistance { best = corner; bestDistance = distance }
        }
        return best
    }
}
