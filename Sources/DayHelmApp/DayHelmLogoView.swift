import AppKit
import SwiftUI

enum DayHelmMenuBarIcon {
    static let templateImage: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)

            let center = CGPoint(x: rect.midX, y: rect.midY)

            // Outer helm ring
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addEllipse(in: CGRect(x: center.x - 5.2, y: center.y - 5.2, width: 10.4, height: 10.4))
            ctx.strokePath()

            // Four cardinal helm grips
            for angleDeg in [0.0, 90.0, 180.0, 270.0] {
                let rad = CGFloat(angleDeg * .pi / 180.0)
                let p1 = CGPoint(x: center.x + cos(rad) * 5.2, y: center.y + sin(rad) * 5.2)
                let p2 = CGPoint(x: center.x + cos(rad) * 7.0, y: center.y + sin(rad) * 7.0)
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
            needle.move(to: CGPoint(x: 0, y: 4.3))
            needle.addLine(to: CGPoint(x: 1.5, y: 0))
            needle.addLine(to: CGPoint(x: 0, y: -4.0))
            needle.addLine(to: CGPoint(x: -1.5, y: 0))
            needle.closeSubpath()
            ctx.addPath(needle)
            ctx.setFillColor(NSColor.labelColor.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        return image
    }()
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
