import AppKit
import DayHelmCapture
import SwiftUI

enum DayHelmMenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for state: MenuBarVisualState, isDark: Bool) -> NSImage {
        let key = "\(state)-\(isDark ? "dark" : "light")"
        if let cached = cache[key] {
            return cached
        }
        let img = renderImage(for: state, isDark: isDark)
        cache[key] = img
        return img
    }

    private static func renderImage(for state: MenuBarVisualState, isDark: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            let center = CGPoint(x: 8.0, y: 8.0)
            let baseAlpha: CGFloat = (state == .standby) ? 0.45 : 1.0
            let fgColor: NSColor = isDark
                ? NSColor.white.withAlphaComponent(baseAlpha)
                : NSColor.black.withAlphaComponent(baseAlpha)

            // Outer helm ring
            ctx.setStrokeColor(fgColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addEllipse(in: CGRect(x: center.x - 5.0, y: center.y - 5.0, width: 10.0, height: 10.0))
            ctx.strokePath()

            // Four cardinal helm grips
            for angleDeg in [0.0, 90.0, 180.0, 270.0] {
                let rad = CGFloat(angleDeg * .pi / 180.0)
                let p1 = CGPoint(x: center.x + cos(rad) * 5.0, y: center.y + sin(rad) * 5.0)
                let p2 = CGPoint(x: center.x + cos(rad) * 6.8, y: center.y + sin(rad) * 6.8)
                ctx.setLineWidth(1.4)
                ctx.setLineCap(.round)
                ctx.move(to: p1)
                ctx.addLine(to: p2)
                ctx.strokePath()
            }

            // Diagonal compass/helm needle
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: -22.0 * .pi / 180.0)

            let needle = CGMutablePath()
            needle.move(to: CGPoint(x: 0, y: 4.1))
            needle.addLine(to: CGPoint(x: 1.5, y: 0))
            needle.addLine(to: CGPoint(x: 0, y: -3.8))
            needle.addLine(to: CGPoint(x: -1.5, y: 0))
            needle.closeSubpath()
            ctx.addPath(needle)
            ctx.setFillColor(fgColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Semantic status dot at bottom-right (in flipped=false coords, y=0 is bottom)
            let dotColor: NSColor? = switch state {
            case .standby:
                nil
            case .focusing:
                NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) // #3B82F6
            case .targetMet:
                NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1.0) // #10B981
            case .capReached:
                NSColor(srgbRed: 0.961, green: 0.620, blue: 0.043, alpha: 1.0) // #F59E0B
            case .otherWork:
                NSColor(srgbRed: 0.580, green: 0.639, blue: 0.722, alpha: 1.0) // #94A3B8
            case .distraction:
                NSColor(srgbRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0) // #EF4444
            }

            if let dotColor {
                let dotCenter = CGPoint(x: 14.5, y: 3.5)
                let cutoutR: CGFloat = 3.8
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.addEllipse(in: CGRect(
                    x: dotCenter.x - cutoutR,
                    y: dotCenter.y - cutoutR,
                    width: cutoutR * 2,
                    height: cutoutR * 2
                ))
                ctx.fillPath()
                ctx.restoreGState()

                let dotR: CGFloat = 2.7
                ctx.setFillColor(dotColor.cgColor)
                ctx.addEllipse(in: CGRect(
                    x: dotCenter.x - dotR,
                    y: dotCenter.y - dotR,
                    width: dotR * 2,
                    height: dotR * 2
                ))
                ctx.fillPath()
            }

            return true
        }
        image.isTemplate = false
        return image
    }
}

struct DayHelmHeaderLogoView: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1E293B"), Color(hex: "#0F172A")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                )

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) * 0.30
                let strokeWidth = max(2.0, canvasSize.width * 0.09)

                // Segmented spectrum arcs matching AppIcon
                let specs: [(Double, Double, Color)] = [
                    (190, 328, DayHelmColors.primaryBlue),
                    (346, 82, DayHelmColors.successEmerald),
                    (100, 166, DayHelmColors.warningAmber)
                ]
                for (startDeg, endDeg, col) in specs {
                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(startDeg),
                        endAngle: .degrees(endDeg),
                        clockwise: false
                    )
                    context.stroke(
                        arc,
                        with: .color(col),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                }

                // Tilted helm needle
                let angleRad = 22.0 * .pi / 180.0
                let tipLen = radius * 0.85
                let tailLen = radius * 0.65
                let halfW = strokeWidth * 0.55

                func rot(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    let rx = x * cos(angleRad) - y * sin(angleRad)
                    let ry = x * sin(angleRad) + y * cos(angleRad)
                    return CGPoint(x: center.x + rx, y: center.y + ry)
                }

                var north = Path()
                north.move(to: rot(0, -tipLen))
                north.addLine(to: rot(halfW, 0))
                north.addLine(to: rot(-halfW, 0))
                north.closeSubpath()
                context.fill(north, with: .color(.white))

                var south = Path()
                south.move(to: rot(0, tailLen))
                south.addLine(to: rot(halfW * 0.85, 0))
                south.addLine(to: rot(-halfW * 0.85, 0))
                south.closeSubpath()
                context.fill(south, with: .color(DayHelmColors.primaryBlue))

                let jewelR = max(1.8, strokeWidth * 0.65)
                let jewelRect = CGRect(x: center.x - jewelR, y: center.y - jewelR, width: jewelR * 2, height: jewelR * 2)
                context.fill(Path(ellipseIn: jewelRect), with: .color(.white))
            }
        }
        .frame(width: size, height: size)
    }
}
