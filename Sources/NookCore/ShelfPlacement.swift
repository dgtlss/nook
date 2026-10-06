import Foundation
import CoreGraphics

/// Screen coordinates use AppKit's bottom-left origin. The shelf belongs to
/// the icon's display, immediately below its menu bar, regardless of window focus.
public enum ShelfPlacement {
    public static func frame(size: CGSize, icon: CGRect, screen: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let gap: CGFloat = 6
        let width = min(size.width, max(0, screen.width - 2 * gap))
        let height = min(size.height, max(0, screen.height - menuBarHeight - 2 * gap))
        let x = min(max(icon.midX - width / 2, screen.minX + gap), screen.maxX - width - gap)
        let y = screen.maxY - menuBarHeight - gap - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
