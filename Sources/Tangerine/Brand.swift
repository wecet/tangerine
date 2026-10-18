import AppKit

/// A template citrus mark remains crisp and adapts to the menu bar's appearance.
enum Brand {
    static let menuIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            func point(_ radius: CGFloat, _ degrees: CGFloat) -> NSPoint {
                let radians = degrees * .pi / 180
                return NSPoint(x: 9 + radius * cos(radians), y: 9 + radius * sin(radians))
            }
            for index in 0..<6 {
                let start = CGFloat(index) * 60 + 5
                let end = start + 50
                let path = NSBezierPath()
                path.move(to: point(7.2, start))
                path.curve(to: point(8, start + 5), controlPoint1: point(8, start), controlPoint2: point(8, start + 2))
                path.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 8, startAngle: start + 5, endAngle: end - 5)
                path.curve(to: point(7.2, end), controlPoint1: point(8, end - 2), controlPoint2: point(8, end))
                path.line(to: point(3.3, end))
                path.curve(to: point(2.6, end - 8), controlPoint1: point(2.6, end), controlPoint2: point(2.6, end - 4))
                path.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 2.6, startAngle: end - 8, endAngle: start + 8, clockwise: true)
                path.curve(to: point(3.3, start), controlPoint1: point(2.6, start + 4), controlPoint2: point(2.6, start))
                path.close(); path.fill()
            }
            NSBezierPath(ovalIn: NSRect(x: 7.7, y: 7.7, width: 2.6, height: 2.6)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tangerine"
        return image
    }()
}
