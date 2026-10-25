import Foundation
import CoreGraphics

public enum MenuBarGeometry {
    public static func segments(in bounds: CGRect, shape: BarShape, notch: CGRect? = nil) -> [CGRect] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        if shape == .full { return [bounds] }
        let rect = bounds.insetBy(dx: min(3, bounds.width / 2), dy: min(2, bounds.height / 2))
        guard rect.width > 0, rect.height > 0 else { return [] }
        guard shape == .split else { return [rect] }
        let gap = notch ?? CGRect(x: bounds.midX - 14, y: bounds.minY, width: 28, height: bounds.height)
        let left = min(max(gap.minX - 3, rect.minX), rect.maxX)
        let right = max(min(gap.maxX + 3, rect.maxX), rect.minX)
        return [
            CGRect(x: rect.minX, y: rect.minY, width: left - rect.minX, height: rect.height),
            CGRect(x: right, y: rect.minY, width: rect.maxX - right, height: rect.height)
        ].filter { $0.width > 0 }
    }
}
