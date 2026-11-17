#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// DayHelm (日舵) App Icon Generator
// Renders a 1024x1024 macOS squircle Precision Telemetry icon and builds branding/AppIcon.icns.

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let brandingDir = rootDir.appendingPathComponent("branding", isDirectory: true)
let masterPNGURL = brandingDir.appendingPathComponent("dayhelm-icon-1024.png")
let iconsetURL = brandingDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = brandingDir.appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: brandingDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, alpha])!
}

func renderIcon(size: Int) -> NSBitmapImageRep {
    let pixels = size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let nsContext = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsContext
    let ctx = nsContext.cgContext

    let s = CGFloat(pixels)
    let scale = s / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS squircle bounds (824x824 centered in 1024x1024)
    let cardRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // 1. Subtle outer drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: CGColor(gray: 0, alpha: 0.42))
    ctx.addPath(squirclePath)
    ctx.setFillColor(color(0x0F172A))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip to squircle & draw deep navy-slate background gradient (#0F172A -> #1E293B)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x0F172A), color(0x162033), color(0x1E293B)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 512, y: 100),
        end: CGPoint(x: 512, y: 924),
        options: []
    )

    // Ambient telemetry radial glow behind helm
    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x3B82F6, alpha: 0.22), color(0x10B981, alpha: 0.08), color(0x0F172A, alpha: 0.0)] as CFArray,
        locations: [0.0, 0.45, 1.0]
    )!
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: 512, y: 520),
        startRadius: 20,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 420,
        options: []
    )

    // Subtle concentric instrument guide rings
    let center = CGPoint(x: 512, y: 512)
    ctx.setStrokeColor(color(0x94A3B8, alpha: 0.10))
    ctx.setLineWidth(2)
    ctx.addEllipse(in: CGRect(x: center.x - 320, y: center.y - 320, width: 640, height: 640))
    ctx.strokePath()

    ctx.setStrokeColor(color(0x94A3B8, alpha: 0.08))
    ctx.setLineWidth(1.5)
    ctx.addEllipse(in: CGRect(x: center.x - 165, y: center.y - 165, width: 330, height: 330))
    ctx.strokePath()

    // 3. Precision dial ticks
    for i in 0..<48 {
        let angle = CGFloat(i) * (.pi * 2.0 / 48.0)
        let isMajor = (i % 4 == 0)
        let rOuter: CGFloat = 312
        let rInner: CGFloat = isMajor ? 286 : 298
        let p1 = CGPoint(x: center.x + cos(angle) * rInner, y: center.y + sin(angle) * rInner)
        let p2 = CGPoint(x: center.x + cos(angle) * rOuter, y: center.y + sin(angle) * rOuter)
        ctx.setStrokeColor(color(0xCBD5E1, alpha: isMajor ? 0.34 : 0.14))
        ctx.setLineWidth(isMajor ? 3.5 : 2.0)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }

    // 4. Segmented Spectrum Arcs (Primary Blue #3B82F6, Emerald #10B981, Amber #F59E0B)
    // Remember CoreGraphics uses standard mathematical angles (0 = right, pi/2 = top)
    let ringRadius: CGFloat = 240
    let ringWidth: CGFloat = 38

    struct ArcSpec {
        let startDeg: CGFloat
        let endDeg: CGFloat
        let hex: UInt32
        let glowAlpha: CGFloat
    }

    let arcs: [ArcSpec] = [
        // Primary Blue: left around top to upper-right (144 deg span, 18 deg gaps)
        ArcSpec(startDeg: 176, endDeg: 32, hex: 0x3B82F6, glowAlpha: 0.45),
        // Emerald: right down to bottom (96 deg span, 18 deg gaps)
        ArcSpec(startDeg: 14, endDeg: -82, hex: 0x10B981, glowAlpha: 0.40),
        // Amber: bottom-left (66 deg span, 18 deg gaps)
        ArcSpec(startDeg: -100, endDeg: -166, hex: 0xF59E0B, glowAlpha: 0.40),
    ]

    // Dark recessed track underneath arcs
    ctx.saveGState()
    ctx.setStrokeColor(color(0x020617, alpha: 0.55))
    ctx.setLineWidth(ringWidth + 8)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    for arc in arcs {
        let startRad = arc.startDeg * .pi / 180.0
        let endRad = arc.endDeg * .pi / 180.0
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 20, color: color(arc.hex, alpha: arc.glowAlpha))
        ctx.setStrokeColor(color(arc.hex, alpha: 0.96))
        ctx.setLineWidth(ringWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: ringRadius, startAngle: startRad, endAngle: endRad, clockwise: true)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 5. Helm Spokes (8 precision spokes from hub to ring, with subtle metallic gradient look)
    for i in 0..<8 {
        let angle = CGFloat(i) * (.pi / 4.0) + (.pi / 8.0)
        let innerR: CGFloat = 56
        let outerR: CGFloat = 205
        let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
        let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)

        ctx.saveGState()
        ctx.setStrokeColor(color(0x94A3B8, alpha: 0.36))
        ctx.setLineWidth(10)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        // Small helm grip peg protruding slightly outward on outer ring
        let pegStart = CGPoint(x: center.x + cos(angle) * 265, y: center.y + sin(angle) * 265)
        let pegEnd = CGPoint(x: center.x + cos(angle) * 284, y: center.y + sin(angle) * 284)
        ctx.setStrokeColor(color(0xE2E8F0, alpha: 0.45))
        ctx.setLineWidth(9)
        ctx.move(to: pegStart)
        ctx.addLine(to: pegEnd)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 6. Central Helm / Compass Needle (tilted slightly to ~22 degrees right of North for dynamic steering feel)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -22.0 * .pi / 180.0)

    // Needle shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: CGColor(gray: 0, alpha: 0.55))

    // Upper (North) pointer blade - crisp bright white-silver
    let northBlade = CGMutablePath()
    northBlade.move(to: CGPoint(x: 0, y: 185))
    northBlade.addLine(to: CGPoint(x: 34, y: 0))
    northBlade.addLine(to: CGPoint(x: 0, y: 20))
    northBlade.addLine(to: CGPoint(x: -34, y: 0))
    northBlade.closeSubpath()
    ctx.addPath(northBlade)
    ctx.setFillColor(color(0xF8FAFC))
    ctx.fillPath()

    // Left facet highlight on north blade for sculpted 3D precision feel
    let northLeft = CGMutablePath()
    northLeft.move(to: CGPoint(x: 0, y: 185))
    northLeft.addLine(to: CGPoint(x: 0, y: 20))
    northLeft.addLine(to: CGPoint(x: -34, y: 0))
    northLeft.closeSubpath()
    ctx.addPath(northLeft)
    ctx.setFillColor(color(0xE2E8F0))
    ctx.fillPath()

    // Lower (South) counterweight blade - deep telemetry slate-blue
    let southBlade = CGMutablePath()
    southBlade.move(to: CGPoint(x: 0, y: -155))
    southBlade.addLine(to: CGPoint(x: 28, y: 0))
    southBlade.addLine(to: CGPoint(x: 0, y: -16))
    southBlade.addLine(to: CGPoint(x: -28, y: 0))
    southBlade.closeSubpath()
    ctx.addPath(southBlade)
    ctx.setFillColor(color(0x3B82F6, alpha: 0.90))
    ctx.fillPath()

    ctx.restoreGState()

    // 7. Center precision hub & luminous jewel
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12, color: CGColor(gray: 0, alpha: 0.45))
    ctx.setFillColor(color(0x0F172A))
    ctx.addEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setStrokeColor(color(0x3B82F6))
    ctx.setLineWidth(10)
    ctx.addEllipse(in: CGRect(x: center.x - 40, y: center.y - 40, width: 80, height: 80))
    ctx.strokePath()

    ctx.setFillColor(color(0xF8FAFC))
    ctx.addEllipse(in: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))
    ctx.fillPath()

    // 8. Subtle inner glass highlight border on squircle
    let borderRect = cardRect.insetBy(dx: 2, dy: 2)
    let borderPath = CGPath(roundedRect: borderRect, cornerWidth: cornerRadius - 2, cornerHeight: cornerRadius - 2, transform: nil)
    ctx.addPath(borderPath)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.14))
    ctx.setLineWidth(4)
    ctx.strokePath()

    ctx.restoreGState() // End squircle clip

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DayHelmIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: .atomic)
}

func resizePNG(_ sourceRep: NSBitmapImageRep, pixelSize: Int, to url: URL) throws {
    let targetRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    targetRep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: targetRep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    sourceRep.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    try writePNG(targetRep, to: url)
}

let masterRep = renderIcon(size: 1024)
try writePNG(masterRep, to: masterPNGURL)

if fileManager.fileExists(atPath: iconsetURL.path) {
    try fileManager.removeItem(at: iconsetURL)
}
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, px) in iconSizes {
    try resizePNG(masterRep, pixelSize: px, to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("Error: iconutil failed with exit code \(process.terminationStatus)\n", stderr)
    exit(1)
}

try? fileManager.removeItem(at: iconsetURL)
print("[DayHelm] Generated icon PNG: \(masterPNGURL.path)")
print("[DayHelm] Generated AppIcon.icns: \(icnsURL.path)")
