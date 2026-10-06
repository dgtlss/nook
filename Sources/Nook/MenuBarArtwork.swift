import AppKit
import NookCore

/// Original vector marks; every choice remains visible in both states.
enum MenuBarArtwork {
    static func image(_ choice: MenuBarIcon, peeking: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            switch choice {
            case .nook:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 2.5, y: 3)); path.line(to: NSPoint(x: 2.5, y: 9.5))
                path.curve(to: NSPoint(x: 9, y: 16), controlPoint1: NSPoint(x: 2.5, y: 13.2), controlPoint2: NSPoint(x: 5.4, y: 16))
                path.curve(to: NSPoint(x: 15.5, y: 9.5), controlPoint1: NSPoint(x: 12.6, y: 16), controlPoint2: NSPoint(x: 15.5, y: 13.2))
                path.line(to: NSPoint(x: 15.5, y: 3)); path.close(); stroke(path, width: 1.5)
                let y = peeking ? 8.0 : 5.3
                for x in [5.4, 10.5] { NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2.1, height: peeking ? 3 : 1.3)).fill() }
            case .dot:
                let path = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10))
                if peeking { stroke(path, width: 1.8) } else { path.fill() }
            case .chevron:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 4, y: peeking ? 11.5 : 6.5))
                path.line(to: NSPoint(x: 9, y: peeking ? 6.5 : 11.5))
                path.line(to: NSPoint(x: 14, y: peeking ? 11.5 : 6.5))
                stroke(path, width: 2)
            case .leaf:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 3, y: 3))
                path.curve(to: NSPoint(x: 15, y: 15), controlPoint1: NSPoint(x: 2, y: 12), controlPoint2: NSPoint(x: 9, y: 16))
                path.curve(to: NSPoint(x: 3, y: 3), controlPoint1: NSPoint(x: 16, y: 9), controlPoint2: NSPoint(x: 12, y: 2))
                path.close()
                if peeking { stroke(path, width: 1.5) } else { path.fill() }
                let stem = NSBezierPath(); stem.move(to: NSPoint(x: 3, y: 3)); stem.line(to: NSPoint(x: 11.5, y: 11.5))
                NSGraphicsContext.saveGraphicsState()
                if !peeking { NSGraphicsContext.current?.compositingOperation = .destinationOut }
                stroke(stem, width: 1.2)
                NSGraphicsContext.restoreGraphicsState()
            case .tiles:
                for x in [3.0, 10.0] {
                    for y in [3.0, 10.0] {
                        let tile = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 5, height: 5), xRadius: 1, yRadius: 1)
                        if peeking { stroke(tile, width: 1.2) } else { tile.fill() }
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nook — \(choice.title)"
        return image
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    }
}
