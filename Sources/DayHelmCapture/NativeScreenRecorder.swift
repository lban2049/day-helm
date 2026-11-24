import AppKit
import CoreGraphics
import Darwin
import DayHelmCore
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

// MARK: - Histogram & Perceptual Hash

public enum ImageHistogram {
    public static func computeHistogram(from image: CGImage, bins: Int = 32) -> [Double] {
        let binCount = max(2, bins)
        let sampleWidth = 128
        let sampleHeight = 72
        guard let pixels = renderRGBA8(image: image, width: sampleWidth, height: sampleHeight) else {
            return Array(repeating: 0.0, count: binCount)
        }

        var counts = Array(repeating: 0, count: binCount)
        let pixelCount = sampleWidth * sampleHeight
        for idx in 0..<pixelCount {
            let offset = idx * 4
            let r = Double(pixels[offset]) / 255.0
            let g = Double(pixels[offset + 1]) / 255.0
            let b = Double(pixels[offset + 2]) / 255.0
            let luma = max(0.0, min(1.0, 0.2126 * r + 0.7152 * g + 0.0722 * b))
            let bin = min(binCount - 1, Int(luma * Double(binCount)))
            counts[bin] += 1
        }

        let total = Double(max(1, pixelCount))
        return counts.map { Double($0) / total }
    }

    public static func computePerceptualHashHex(from image: CGImage) -> String {
        let gridSize = 8
        guard let pixels = renderRGBA8(image: image, width: gridSize, height: gridSize) else {
            return String(repeating: "0", count: 16)
        }

        var lumas: [Double] = []
        lumas.reserveCapacity(64)
        for idx in 0..<64 {
            let offset = idx * 4
            let r = Double(pixels[offset])
            let g = Double(pixels[offset + 1])
            let b = Double(pixels[offset + 2])
            lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }

        let mean = lumas.reduce(0.0, +) / 64.0
        var hash: UInt64 = 0
        for (bitIdx, luma) in lumas.enumerated() where luma >= mean {
            hash |= (UInt64(1) << UInt64(63 - bitIdx))
        }
        return String(format: "%016llx", hash)
    }

    /// Total Variation Distance in [0.0, 1.0]: 0.0 means identical, 1.0 means completely disjoint.
    public static func histogramDistance(from lhs: [Double], to rhs: [Double]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 1.0 }
        var l1 = 0.0
        for i in 0..<count {
            l1 += abs(lhs[i] - rhs[i])
        }
        if lhs.count != rhs.count {
            for i in count..<lhs.count { l1 += abs(lhs[i]) }
            for i in count..<rhs.count { l1 += abs(rhs[i]) }
        }
        return min(1.0, max(0.0, 0.5 * l1))
    }

    public static func computeThumbnailRGB(from image: CGImage, width: Int = 160, height: Int = 90) -> [UInt8] {
        let w = max(1, width)
        let h = max(1, height)
        guard let rgba = renderRGBA8(image: image, width: w, height: h) else {
            return []
        }
        let pixelCount = w * h
        var rgb = [UInt8](repeating: 0, count: pixelCount * 3)
        for i in 0..<pixelCount {
            let src = i * 4
            let dst = i * 3
            rgb[dst] = rgba[src]
            rgb[dst + 1] = rgba[src + 1]
            rgb[dst + 2] = rgba[src + 2]
        }
        return rgb
    }

    public static func pixelDiffPercentage(
        from lhs: [UInt8],
        to rhs: [UInt8],
        channelThreshold: Int = 30
    ) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count, (lhs.count % 3) == 0 else {
            return 1.0
        }
        let pixelCount = lhs.count / 3
        let thresh = max(0, channelThreshold)
        var changed = 0
        for i in 0..<pixelCount {
            let base = i * 3
            if abs(Int(lhs[base]) - Int(rhs[base])) > thresh
                || abs(Int(lhs[base + 1]) - Int(rhs[base + 1])) > thresh
                || abs(Int(lhs[base + 2]) - Int(rhs[base + 2])) > thresh {
                changed += 1
            }
        }
        return Double(changed) / Double(pixelCount)
    }

    public static func computeVisualSignature(
        from image: CGImage,
        bins: Int = 32
    ) -> (histogram: [Double], thumbnailRGB: [UInt8], hashHex: String) {
        autoreleasepool {
            let binCount = max(2, bins)
            let w = 160
            let h = 90
            guard let rgba = renderRGBA8(image: image, width: w, height: h) else {
                return (
                    Array(repeating: 0.0, count: binCount),
                    [],
                    String(repeating: "0", count: 16)
                )
            }

            let pixelCount = w * h
            var rgb = [UInt8](repeating: 0, count: pixelCount * 3)
            var counts = [Int](repeating: 0, count: binCount)

            for i in 0..<pixelCount {
                let src = i * 4
                let dst = i * 3
                let rByte = rgba[src]
                let gByte = rgba[src + 1]
                let bByte = rgba[src + 2]
                rgb[dst] = rByte
                rgb[dst + 1] = gByte
                rgb[dst + 2] = bByte

                let r = Double(rByte) / 255.0
                let g = Double(gByte) / 255.0
                let b = Double(bByte) / 255.0
                let luma = max(0.0, min(1.0, 0.2126 * r + 0.7152 * g + 0.0722 * b))
                let bin = min(binCount - 1, Int(luma * Double(binCount)))
                counts[bin] += 1
            }

            let total = Double(pixelCount)
            let histogram = counts.map { Double($0) / total }

            // Compute 8x8 perceptual hash directly from the 160x90 RGBA buffer (zero extra full-frame decode).
            var blockLumas = [Double](repeating: 0.0, count: 64)
            for gy in 0..<8 {
                let y0 = (gy * h) / 8
                let y1 = max(y0 + 1, ((gy + 1) * h) / 8)
                for gx in 0..<8 {
                    let x0 = (gx * w) / 8
                    let x1 = max(x0 + 1, ((gx + 1) * w) / 8)
                    var sum = 0.0
                    var n = 0
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            let src = (y * w + x) * 4
                            let luma = 0.2126 * Double(rgba[src]) + 0.7152 * Double(rgba[src + 1]) + 0.0722 * Double(rgba[src + 2])
                            sum += luma
                            n += 1
                        }
                    }
                    blockLumas[gy * 8 + gx] = sum / Double(max(1, n))
                }
            }
            let mean = blockLumas.reduce(0.0, +) / 64.0
            var hash: UInt64 = 0
            for (bitIdx, luma) in blockLumas.enumerated() where luma >= mean {
                hash |= (UInt64(1) << UInt64(63 - bitIdx))
            }
            let hashHex = String(format: "%016llx", hash)
            return (histogram, rgb, hashHex)
        }
    }

    private static func renderRGBA8(image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let success = buffer.withUnsafeMutableBytes { rawPtr -> Bool in
            guard let baseAddress = rawPtr.baseAddress,
                  let ctx = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? buffer : nil
    }
}

public enum DisplayGeometry {
    public struct DisplayInfo: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        public let frame: CGRect

        public init(displayID: CGDirectDisplayID, frame: CGRect) {
            self.displayID = displayID
            self.frame = frame
        }
    }

    public static func selectDisplayID(
        windowFrame: CGRect?,
        displays: [DisplayInfo],
        mainDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID? {
        guard !displays.isEmpty else { return nil }
        if let windowFrame, !windowFrame.isNull, !windowFrame.isEmpty {
            var bestID: CGDirectDisplayID?
            var bestArea: CGFloat = 0
            for display in displays {
                let intersection = display.frame.intersection(windowFrame)
                if !intersection.isNull && !intersection.isEmpty {
                    let area = intersection.width * intersection.height
                    if area > bestArea {
                        bestArea = area
                        bestID = display.displayID
                    }
                }
            }
            if let bestID {
                return bestID
            }
        }
        if let main = displays.first(where: { $0.displayID == mainDisplayID }) {
            return main.displayID
        }
        return displays.first?.displayID
    }
}

// MARK: - Screen Capture

public protocol ScreenCapturing: Sendable {
    var isScreenCaptureTrusted: Bool { get }
    func requestScreenCapturePermission() -> Bool
    func captureMainDisplayImage() async throws -> CGImage
    func captureActiveDisplayImage() async throws -> CGImage
    func captureProbeImage() async throws -> CGImage
}

public extension ScreenCapturing {
    func captureActiveDisplayImage() async throws -> CGImage {
        try await captureMainDisplayImage()
    }

    func captureProbeImage() async throws -> CGImage {
        try await captureActiveDisplayImage()
    }
}

public enum ScreenCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case noDisplayAvailable
    case jpegEncodingFailed(String)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is not granted."
        case .noDisplayAvailable:
            return "No active display available for capture."
        case .jpegEncodingFailed(let path):
            return "Failed to write JPEG snapshot to \(path)."
        }
    }
}

public final class ScreenSnapshotCapturer: ScreenCapturing, @unchecked Sendable {
    private struct DisplayListCache {
        let timestamp: Date
        let displays: [SCDisplay]
    }

    private struct WindowBoundsCache {
        let timestamp: Date
        let pid: pid_t
        let bounds: CGRect?
    }

    private let cacheLock = NSLock()
    private var displayListCache: DisplayListCache?
    private var windowBoundsCache: WindowBoundsCache?
    private let displayListCacheTTLSeconds: TimeInterval = 60.0
    private let windowBoundsCacheTTLSeconds: TimeInterval = 2.5

    public init() {}

    public var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureMainDisplayImage() async throws -> CGImage {
        try await captureDisplayImage(maxWidth: 1920, activeWindowAware: false)
    }

    public func captureActiveDisplayImage() async throws -> CGImage {
        try await captureDisplayImage(maxWidth: 1920, activeWindowAware: true)
    }

    public func captureProbeImage() async throws -> CGImage {
        try await captureDisplayImage(maxWidth: 320, activeWindowAware: true)
    }

    private func captureDisplayImage(maxWidth: Int, activeWindowAware: Bool) async throws -> CGImage {
        guard isScreenCaptureTrusted else {
            throw ScreenCaptureError.permissionDenied
        }

        let now = Date()
        let cachedDisplayList = cacheLock.withLock { displayListCache }

        let displays: [SCDisplay]
        if let cachedDisplayList,
           now.timeIntervalSince(cachedDisplayList.timestamp) < displayListCacheTTLSeconds,
           !cachedDisplayList.displays.isEmpty {
            displays = cachedDisplayList.displays
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            displays = content.displays
            cacheLock.withLock {
                displayListCache = DisplayListCache(timestamp: now, displays: displays)
            }
        }

        let windowBounds: CGRect?
        if activeWindowAware && displays.count > 1,
           let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let cachedBounds = cacheLock.withLock { windowBoundsCache }
            if let cachedBounds,
               now.timeIntervalSince(cachedBounds.timestamp) < windowBoundsCacheTTLSeconds,
               cachedBounds.pid == frontPID {
                windowBounds = cachedBounds.bounds
            } else {
                let freshBounds = Self.frontmostWindowBounds(pid: frontPID)
                cacheLock.withLock {
                    windowBoundsCache = WindowBoundsCache(timestamp: now, pid: frontPID, bounds: freshBounds)
                }
                windowBounds = freshBounds
            }
        } else {
            windowBounds = nil
        }

        let mainDisplayID = CGMainDisplayID()
        let selectedDisplayID: CGDirectDisplayID?
        if activeWindowAware {
            let displayInfos = displays.map {
                DisplayGeometry.DisplayInfo(displayID: $0.displayID, frame: $0.frame)
            }
            selectedDisplayID = DisplayGeometry.selectDisplayID(
                windowFrame: windowBounds,
                displays: displayInfos,
                mainDisplayID: mainDisplayID
            )
        } else {
            selectedDisplayID = mainDisplayID
        }

        let targetID = selectedDisplayID ?? mainDisplayID
        guard let display = displays.first(where: { $0.displayID == targetID })
                ?? displays.first(where: { $0.displayID == mainDisplayID })
                ?? displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        if display.width > maxWidth, display.width > 0 {
            let scale = Double(maxWidth) / Double(display.width)
            config.width = maxWidth
            config.height = max(1, Int((Double(display.height) * scale).rounded()))
        } else {
            config.width = max(1, display.width)
            config.height = max(1, display.height)
        }
        config.showsCursor = true
        config.capturesAudio = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func frontmostWindowBounds(pid: pid_t) -> CGRect? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }
            var rect = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
               rect.width >= 60,
               rect.height >= 40 {
                return rect
            }
        }
        return nil
    }

    @discardableResult
    public static func encodeJPEG(image: CGImage, to fileURL: URL, quality: CGFloat = 0.55) throws -> Int64 {
        try autoreleasepool {
            let fm = FileManager.default
            let dir = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            guard let destination = CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw ScreenCaptureError.jpegEncodingFailed(fileURL.path)
            }

            let props = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            CGImageDestinationAddImage(destination, image, props)
            guard CGImageDestinationFinalize(destination) else {
                throw ScreenCaptureError.jpegEncodingFailed(fileURL.path)
            }

            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    public static func decodeThumbnailCGImage(at fileURL: URL, maxPixelSize: Int) -> CGImage? {
        autoreleasepool {
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }
}

// MARK: - On-Device Apple Vision OCR

public struct OCRResult: Sendable, Equatable {
    public let text: String
    public let charCount: Int
    public let tokenCount: Int

    public init(text: String, charCount: Int, tokenCount: Int) {
        self.text = text
        self.charCount = charCount
        self.tokenCount = tokenCount
    }
}

public enum VisionOCRService {
    public static let defaultLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja"]
    /// Top 4% of full-screen captures (`y > 0.96` in Vision bottom-left coordinates)
    /// covers both standard 24pt and notch 37–38pt macOS menu bars without clipping app content.
    public static let topMenuBarExcludeHeightRatio: CGFloat = 0.04
    /// Minimum image height in pixels required before cropping the top menu bar,
    /// preserving compatibility with compact synthetic test banners (e.g. 960x240).
    public static let minTopMenuBarCropHeight: Int = 480
    private static let ocrQueue = DispatchQueue(label: "com.dayhelm.vision.ocr", qos: .utility)

    private final class WorkerClientState: @unchecked Sendable {
        var process: Process?
        var stdinHandle: FileHandle?
        var stdoutHandle: FileHandle?
        var requestsServed: Int = 0
        var idleTimer: DispatchSourceTimer?
        var stdoutBuffer = Data()
    }

    private static let workerState = WorkerClientState()

    public static func prepareOCRImage(from image: CGImage, maxDimension: Int = 1600) -> CGImage {
        let cap = max(64, maxDimension)
        let longest = max(image.width, image.height)
        guard longest > cap else {
            return image
        }
        return autoreleasepool {
            let scale = Double(cap) / Double(longest)
            let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
            let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return image
            }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return ctx.makeImage() ?? image
        }
    }

    public static func recognizeTextSync(
        from image: CGImage,
        languages: [String] = defaultLanguages,
        excludeTopMenuBar: Bool = true
    ) throws -> OCRResult {
        defer {
            malloc_zone_pressure_relief(nil, 0)
        }
        return try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false

            let shouldExcludeTopMenuBar = excludeTopMenuBar && image.height >= minTopMenuBarCropHeight
            let maxAllowedNormalizedY = 1.0 - topMenuBarExcludeHeightRatio
            if shouldExcludeTopMenuBar {
                request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: maxAllowedNormalizedY)
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { obs -> String? in
                if shouldExcludeTopMenuBar && obs.boundingBox.maxY > maxAllowedNormalizedY + 0.005 {
                    return nil
                }
                guard let candidate = obs.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !candidate.isEmpty else {
                    return nil
                }
                return candidate
            }

            let joined = lines.joined(separator: "\n")
            return OCRResult(
                text: joined,
                charCount: joined.count,
                tokenCount: ActivityDatabase.estimateTokenCount(joined)
            )
        }
    }

    public static func recognizeText(
        from image: CGImage,
        languages: [String] = defaultLanguages,
        excludeTopMenuBar: Bool = true
    ) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            ocrQueue.async {
                do {
                    let result = try recognizeTextSync(
                        from: image,
                        languages: languages,
                        excludeTopMenuBar: excludeTopMenuBar
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func recognizeText(
        at imageFileURL: URL,
        maxDimension: Int = 1280,
        languages: [String] = defaultLanguages,
        excludeTopMenuBar: Bool = true
    ) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            ocrQueue.async {
                do {
                    if let workerExec = workerExecutableURL(),
                       let result = try? runViaWorkerLocked(
                        executableURL: workerExec,
                        imageFileURL: imageFileURL,
                        maxDimension: maxDimension,
                        languages: languages,
                        excludeTopMenuBar: excludeTopMenuBar
                       ) {
                        continuation.resume(returning: result)
                        return
                    }

                    guard let cgImage = ScreenSnapshotCapturer.decodeThumbnailCGImage(
                        at: imageFileURL,
                        maxPixelSize: maxDimension
                    ) else {
                        throw ScreenCaptureError.jpegEncodingFailed(imageFileURL.path)
                    }
                    let result = try recognizeTextSync(
                        from: cgImage,
                        languages: languages,
                        excludeTopMenuBar: excludeTopMenuBar
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func shutdownWorker() {
        ocrQueue.async {
            shutdownWorkerLocked()
        }
    }

    private static func workerExecutableURL() -> URL? {
        guard let execURL = Bundle.main.executableURL,
              execURL.lastPathComponent == "DayHelm",
              FileManager.default.isExecutableFile(atPath: execURL.path) else {
            return nil
        }
        return execURL
    }

    private static func runViaWorkerLocked(
        executableURL: URL,
        imageFileURL: URL,
        maxDimension: Int,
        languages: [String],
        excludeTopMenuBar: Bool
    ) throws -> OCRResult {
        try ensureWorkerProcessLocked(executableURL: executableURL)
        guard let stdinHandle = workerState.stdinHandle,
              let stdoutHandle = workerState.stdoutHandle else {
            shutdownWorkerLocked()
            throw NSError(domain: "DayHelmOCRWorker", code: 1)
        }

        let payload: [String: Any] = [
            "imagePath": imageFileURL.path,
            "maxDimension": maxDimension,
            "languages": languages,
            "excludeTopMenuBar": excludeTopMenuBar
        ]
        var lineData = try JSONSerialization.data(withJSONObject: payload, options: [])
        lineData.append(0x0A)
        try stdinHandle.write(contentsOf: lineData)

        guard let responseLine = readLineData(from: stdoutHandle),
              let json = try JSONSerialization.jsonObject(with: responseLine) as? [String: Any],
              (json["ok"] as? Bool) == true,
              let text = json["text"] as? String,
              let charCount = json["charCount"] as? Int,
              let tokenCount = json["tokenCount"] as? Int else {
            shutdownWorkerLocked()
            throw NSError(domain: "DayHelmOCRWorker", code: 2)
        }

        workerState.requestsServed += 1
        if workerState.requestsServed >= VisionOCRWorker.maxRequestsPerProcess {
            shutdownWorkerLocked()
        } else {
            scheduleWorkerIdleTimerLocked()
        }

        return OCRResult(text: text, charCount: charCount, tokenCount: tokenCount)
    }

    private static func ensureWorkerProcessLocked(executableURL: URL) throws {
        if let proc = workerState.process, proc.isRunning,
           workerState.requestsServed < VisionOCRWorker.maxRequestsPerProcess {
            return
        }
        shutdownWorkerLocked()

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = [VisionOCRWorker.workerFlag]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        workerState.process = proc
        workerState.stdinHandle = stdinPipe.fileHandleForWriting
        workerState.stdoutHandle = stdoutPipe.fileHandleForReading
        workerState.requestsServed = 0
        workerState.stdoutBuffer.removeAll(keepingCapacity: false)
        scheduleWorkerIdleTimerLocked()
    }

    private static func scheduleWorkerIdleTimerLocked() {
        workerState.idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: ocrQueue)
        timer.schedule(deadline: .now() + VisionOCRWorker.idleTimeoutSeconds)
        timer.setEventHandler {
            shutdownWorkerLocked()
        }
        timer.resume()
        workerState.idleTimer = timer
    }

    private static func shutdownWorkerLocked() {
        workerState.idleTimer?.cancel()
        workerState.idleTimer = nil
        try? workerState.stdinHandle?.close()
        workerState.stdinHandle = nil
        try? workerState.stdoutHandle?.close()
        workerState.stdoutHandle = nil
        workerState.stdoutBuffer.removeAll(keepingCapacity: false)
        if let proc = workerState.process {
            if proc.isRunning {
                proc.terminate()
            }
            workerState.process = nil
        }
        workerState.requestsServed = 0
    }

    private static func readLineData(from handle: FileHandle) -> Data? {
        while true {
            if let newlineIdx = workerState.stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(workerState.stdoutBuffer[..<newlineIdx])
                let nextStart = workerState.stdoutBuffer.index(after: newlineIdx)
                workerState.stdoutBuffer.removeSubrange(..<nextStart)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                return nil
            }
            workerState.stdoutBuffer.append(chunk)
        }
    }
}

public enum VisionOCRWorker {
    public static let workerFlag = "__ocr-worker"
    public static let maxRequestsPerProcess = 10
    public static let idleTimeoutSeconds: TimeInterval = 15.0

    private struct RequestPayload: Decodable {
        let imagePath: String
        let maxDimension: Int?
        let languages: [String]?
        let excludeTopMenuBar: Bool?
    }

    public static func processRequestJSONData(_ data: Data) -> Data {
        defer {
            malloc_zone_pressure_relief(nil, 0)
        }
        return autoreleasepool {
            do {
                let req = try JSONDecoder().decode(RequestPayload.self, from: data)
                let fileURL = URL(fileURLWithPath: req.imagePath)
                let maxDim = max(64, req.maxDimension ?? 1280)
                let languages = (req.languages?.isEmpty == false) ? req.languages! : VisionOCRService.defaultLanguages
                guard let cgImage = ScreenSnapshotCapturer.decodeThumbnailCGImage(at: fileURL, maxPixelSize: maxDim) else {
                    return encodeError("Failed to decode image at \(req.imagePath)")
                }
                let result = try VisionOCRService.recognizeTextSync(
                    from: cgImage,
                    languages: languages,
                    excludeTopMenuBar: req.excludeTopMenuBar ?? true
                )
                let response: [String: Any] = [
                    "ok": true,
                    "text": result.text,
                    "charCount": result.charCount,
                    "tokenCount": result.tokenCount
                ]
                return (try? JSONSerialization.data(withJSONObject: response, options: [])) ?? Data("{\"ok\":false,\"error\":\"json\"}".utf8)
            } catch {
                return encodeError(error.localizedDescription)
            }
        }
    }

    public static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.dropFirst().first == workerFlag else {
            return false
        }

        let watchdogQueue = DispatchQueue(label: "com.dayhelm.ocrworker.watchdog")
        let timerLock = NSLock()
        var idleTimer: DispatchSourceTimer?

        let resetIdleTimer: () -> Void = {
            timerLock.lock()
            idleTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
            timer.schedule(deadline: .now() + idleTimeoutSeconds)
            timer.setEventHandler {
                Foundation.exit(0)
            }
            timer.resume()
            idleTimer = timer
            timerLock.unlock()
        }

        resetIdleTimer()
        var processedCount = 0
        while processedCount < maxRequestsPerProcess,
              let line = readLine(strippingNewline: true) {
            resetIdleTimer()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            var outData = processRequestJSONData(Data(trimmed.utf8))
            outData.append(0x0A)
            FileHandle.standardOutput.write(outData)
            fflush(stdout)
            processedCount += 1
            resetIdleTimer()
        }

        timerLock.lock()
        idleTimer?.cancel()
        idleTimer = nil
        timerLock.unlock()
        return true
    }

    private static func encodeError(_ message: String) -> Data {
        let obj: [String: Any] = ["ok": false, "error": message]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data("{\"ok\":false,\"error\":\"unknown\"}".utf8)
    }
}

// MARK: - Native Event Monitor (Privacy-Safe: No Keystroke Characters Logged)

public struct NativeMonitorEvent: Sendable, Equatable {
    public let timestamp: Date
    public let kind: String
    public let appName: String?
    public let bundleId: String?
    public let count: Int

    public init(
        timestamp: Date,
        kind: String,
        appName: String? = nil,
        bundleId: String? = nil,
        count: Int = 1
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.appName = appName
        self.bundleId = bundleId
        self.count = max(1, count)
    }
}

public final class NativeEventMonitor: @unchecked Sendable {
    private let clock: any DayHelmClock
    private let onRawInput: (@Sendable (_ isKeypress: Bool, _ at: Date) -> Void)?
    private let onEvent: @Sendable (NativeMonitorEvent) -> Void
    private let lock = NSLock()

    private let flushThresholdCount: Int = 40
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var globalInputMonitor: Any?
    private var flushTimerTask: Task<Void, Never>?
    private var pendingClickCount: Int = 0
    private var pendingKeypressCount: Int = 0
    private var pendingClickTimestamp: Date?
    private var pendingKeypressTimestamp: Date?
    private var lastRawKeypressAt: Date?
    private var isStarted = false
    private var inputMonitoringEnabled: Bool

    public init(
        clock: any DayHelmClock = SystemClock(),
        inputMonitoringEnabled: Bool = true,
        onRawInput: (@Sendable (_ isKeypress: Bool, _ at: Date) -> Void)? = nil,
        onEvent: @escaping @Sendable (NativeMonitorEvent) -> Void
    ) {
        self.clock = clock
        self.inputMonitoringEnabled = inputMonitoringEnabled
        self.onRawInput = onRawInput
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    public var isKeypressMonitoringEffective: Bool {
        AXIsProcessTrusted()
    }

    public var isInputMonitoringEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inputMonitoringEnabled
    }

    public func setInputMonitoringEnabled(_ enabled: Bool) {
        lock.lock()
        let wasEnabled = inputMonitoringEnabled
        inputMonitoringEnabled = enabled
        let started = isStarted
        let existingMonitor = globalInputMonitor
        if !enabled {
            globalInputMonitor = nil
        }
        lock.unlock()

        guard started, wasEnabled != enabled else { return }

        if !enabled {
            flushPendingInput(at: clock.now())
            if let existingMonitor {
                NSEvent.removeMonitor(existingMonitor)
            }
        } else if existingMonitor == nil {
            let newMonitor = installGlobalInputMonitor()
            lock.lock()
            if isStarted && inputMonitoringEnabled && globalInputMonitor == nil {
                globalInputMonitor = newMonitor
                lock.unlock()
            } else {
                lock.unlock()
                if let newMonitor {
                    NSEvent.removeMonitor(newMonitor)
                }
            }
        }
    }

    private func installGlobalInputMonitor() -> Any? {
        // Only observe event type & timestamp/count; NEVER read event.characters or event.keyCode.
        NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return }
            let now = self.clock.now()
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                self.recordMouseClick(at: now)
            case .keyDown:
                self.recordKeyPress(at: now)
            default:
                break
            }
        }
    }

    public func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        let shouldMonitorInput = inputMonitoringEnabled
        lock.unlock()

        let wsCenter = NSWorkspace.shared.notificationCenter
        let activateObs = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let now = self.clock.now()
            self.flushPendingInput(at: now)
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? app?.bundleIdentifier
            self.onEvent(NativeMonitorEvent(
                timestamp: now,
                kind: "app_focus",
                appName: name,
                bundleId: app?.bundleIdentifier
            ))
        }
        let sleepObs = wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let now = self.clock.now()
            self.flushPendingInput(at: now)
            self.onEvent(NativeMonitorEvent(timestamp: now, kind: "will_sleep"))
        }
        let wakeObs = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onEvent(NativeMonitorEvent(timestamp: self.clock.now(), kind: "did_wake"))
        }

        let distCenter = DistributedNotificationCenter.default()
        let lockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let now = self.clock.now()
            self.flushPendingInput(at: now)
            self.onEvent(NativeMonitorEvent(timestamp: now, kind: "lock"))
        }
        let unlockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onEvent(NativeMonitorEvent(timestamp: self.clock.now(), kind: "unlock"))
        }

        let inputObs = shouldMonitorInput ? installGlobalInputMonitor() : nil

        let timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { break }
                self.flushPendingInput(at: self.clock.now())
            }
        }

        lock.lock()
        workspaceObservers = [activateObs, sleepObs, wakeObs]
        distributedObservers = [lockObs, unlockObs]
        globalInputMonitor = inputObs
        flushTimerTask = timerTask
        lock.unlock()
    }

    public func stop() {
        flushPendingInput(at: clock.now())

        lock.lock()
        let wsObs = workspaceObservers
        let distObs = distributedObservers
        let inputObs = globalInputMonitor
        let timer = flushTimerTask
        workspaceObservers = []
        distributedObservers = []
        globalInputMonitor = nil
        flushTimerTask = nil
        isStarted = false
        lock.unlock()

        timer?.cancel()
        for obs in wsObs {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        let distCenter = DistributedNotificationCenter.default()
        for obs in distObs {
            distCenter.removeObserver(obs)
        }
        if let inputObs {
            NSEvent.removeMonitor(inputObs)
        }
    }

    public func recordMouseClick(at timestamp: Date) {
        onRawInput?(false, timestamp)
        var batchToEmit: NativeMonitorEvent?
        lock.lock()
        pendingClickCount += 1
        pendingClickTimestamp = pendingClickTimestamp ?? timestamp
        if pendingClickCount >= flushThresholdCount {
            batchToEmit = NativeMonitorEvent(
                timestamp: timestamp,
                kind: "click",
                count: pendingClickCount
            )
            pendingClickCount = 0
            pendingClickTimestamp = nil
        }
        lock.unlock()

        if let batchToEmit {
            onEvent(batchToEmit)
        }
    }

    public func recordKeyPress(at timestamp: Date) {
        let now = clock.now()
        var shouldEmitRaw = false
        var batchToEmit: NativeMonitorEvent?
        lock.lock()
        if let lastRaw = lastRawKeypressAt {
            if now.timeIntervalSince(lastRaw) >= 0.25 {
                lastRawKeypressAt = now
                shouldEmitRaw = true
            }
        } else {
            lastRawKeypressAt = now
            shouldEmitRaw = true
        }
        pendingKeypressCount += 1
        pendingKeypressTimestamp = pendingKeypressTimestamp ?? timestamp
        if pendingKeypressCount >= flushThresholdCount {
            batchToEmit = NativeMonitorEvent(
                timestamp: timestamp,
                kind: "keypress",
                count: pendingKeypressCount
            )
            pendingKeypressCount = 0
            pendingKeypressTimestamp = nil
        }
        lock.unlock()

        if shouldEmitRaw {
            onRawInput?(true, timestamp)
        }
        if let batchToEmit {
            onEvent(batchToEmit)
        }
    }

    public func flushPendingInput(at timestamp: Date? = nil) {
        let fallbackTime = timestamp ?? clock.now()
        var eventsToEmit: [NativeMonitorEvent] = []

        lock.lock()
        if pendingClickCount > 0 {
            eventsToEmit.append(NativeMonitorEvent(
                timestamp: timestamp ?? pendingClickTimestamp ?? fallbackTime,
                kind: "click",
                count: pendingClickCount
            ))
            pendingClickCount = 0
            pendingClickTimestamp = nil
        }
        if pendingKeypressCount > 0 {
            eventsToEmit.append(NativeMonitorEvent(
                timestamp: timestamp ?? pendingKeypressTimestamp ?? fallbackTime,
                kind: "keypress",
                count: pendingKeypressCount
            ))
            pendingKeypressCount = 0
            pendingKeypressTimestamp = nil
        }
        lock.unlock()

        for evt in eventsToEmit {
            onEvent(evt)
        }
    }
}

// MARK: - Native Screen & OCR Recorder

public final class NativeScreenRecorder: @unchecked Sendable {
    public let database: ActivityDatabase
    public let snapshotsRootDir: URL
    public let capturer: any ScreenCapturing
    public let clock: any DayHelmClock

    private var _appFocusDebounceSeconds: TimeInterval = 4.0
    private var _visualCheckIntervalSeconds: TimeInterval = 12.0
    private var _heartbeatIntervalSeconds: TimeInterval = 120.0
    private var _defaultIdleThresholdSeconds: TimeInterval = 300.0
    private var _jpegQuality: CGFloat = 0.55
    private var _visionOCREnabled: Bool = true
    private var _ocrLanguages: [String] = VisionOCRService.defaultLanguages

    public var appFocusDebounceSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _appFocusDebounceSeconds
    }

    public var visualCheckIntervalSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _visualCheckIntervalSeconds
    }

    public var heartbeatIntervalSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _heartbeatIntervalSeconds
    }

    public var defaultIdleThresholdSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _defaultIdleThresholdSeconds
    }

    public var jpegQuality: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return _jpegQuality
    }

    public var visionOCREnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _visionOCREnabled
    }

    public var ocrLanguages: [String] {
        lock.lock(); defer { lock.unlock() }
        return _ocrLanguages
    }

    public let clickCaptureMinIntervalSeconds: TimeInterval = 10.0
    public let typingPauseCaptureMinIntervalSeconds: TimeInterval = 15.0
    public let minHistogramDiffPct: Double = 0.04
    public let minPixelDiffPct: Double = 0.02
    public var minNonFocusOCRIntervalSeconds: TimeInterval = 25.0
    public var minWindowChangeOCRIntervalSeconds: TimeInterval = 3.0

    /// Snapshots older than this are re-encoded to a smaller tier before final retention pruning.
    public let downsampleAfterDays: Int = 1
    public let downsampleMaxWidth: Int = 480
    public let downsampleJPEGQuality: CGFloat = 0.4

    private struct PendingCaptureRequest: Sendable {
        let sample: ActivitySample
        let trigger: String
        let priority: Int
        let declaredTaskId: String?
        let ocrEveryN: Int
        let onCompleted: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private var lastSavedHistogram: [Double]?
    private var lastSavedThumbnailRGB: [UInt8]?
    private var lastSavedAt: Date?
    private var savedSnapshotCount: Int = 0
    private var lastOCRTextBySession: [String: String] = [:]
    private var lastOCRSessionOrder: [String] = []
    private let maxCachedOCRSessions = 4
    private var lastAppFocusCaptureAt: Date?
    private var lastWindowChangeCaptureAt: Date?
    private var lastClickCaptureAt: Date?
    private var lastTypingPauseCaptureAt: Date?
    private var lastVisualCheckAt: Date?
    private var lastOCRRunAt: Date?
    private var lastOCRWindowKey: String?
    private var lastPruneAt: Date?
    private var isCaptureInFlight: Bool = false
    private var pendingCapture: PendingCaptureRequest?

    public init(
        database: ActivityDatabase,
        snapshotsRootDir: URL,
        capturer: any ScreenCapturing = ScreenSnapshotCapturer(),
        clock: any DayHelmClock = SystemClock(),
        settings: DayHelmSettings = .default
    ) {
        self.database = database
        self.snapshotsRootDir = snapshotsRootDir
        self.capturer = capturer
        self.clock = clock
        applySettings(settings)
    }

    public func applySettings(_ settings: DayHelmSettings) {
        lock.lock()
        _appFocusDebounceSeconds = TimeInterval(max(0, settings.appFocusDebounceMs)) / 1000.0
        _heartbeatIntervalSeconds = TimeInterval(max(1000, settings.heartbeatIntervalMs)) / 1000.0
        _defaultIdleThresholdSeconds = TimeInterval(max(5000, settings.recorderIdleThresholdMs)) / 1000.0
        _visualCheckIntervalSeconds = TimeInterval(max(0, settings.visualCheckIntervalMs)) / 1000.0
        _jpegQuality = CGFloat(min(100, max(1, settings.jpegQuality))) / 100.0
        _visionOCREnabled = settings.visionOCREnabled
        _ocrLanguages = settings.ocrLanguages.isEmpty ? VisionOCRService.defaultLanguages : settings.ocrLanguages
        lock.unlock()
    }

    public var isScreenCaptureTrusted: Bool {
        capturer.isScreenCaptureTrusted
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        capturer.requestScreenCapturePermission()
    }

    public var cachedOCRSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lastOCRTextBySession.count
    }

    public func resetDeduplicationBaseline() {
        lock.lock()
        lastSavedHistogram = nil
        lastSavedThumbnailRGB = nil
        lastSavedAt = nil
        lastVisualCheckAt = nil
        lastOCRRunAt = nil
        lastOCRWindowKey = nil
        lastOCRTextBySession.removeAll(keepingCapacity: false)
        lastOCRSessionOrder.removeAll(keepingCapacity: false)
        lock.unlock()
        VisionOCRService.shutdownWorker()
    }

    public static func shouldRunOCR(savedCount: Int, trigger: String, ocrEveryN: Int) -> Bool {
        if trigger == ActivityEventKind.appFocus.rawValue || trigger == "window_change" {
            return true
        }
        let n = max(1, ocrEveryN)
        if n <= 1 || savedCount <= 1 {
            return true
        }
        return ((savedCount - 1) % n) == 0
    }

    private static func priority(for trigger: String) -> Int {
        switch trigger {
        case ActivityEventKind.appFocus.rawValue, "window_change":
            return 3
        case ActivityEventKind.click.rawValue:
            return 2
        case ActivityEventKind.typingPause.rawValue:
            return 1
        default:
            return 0
        }
    }

    public func evaluatePeriodicCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval = 180.0,
        retentionDays: Int = 7,
        maxStorageBytes: Int64 = DayHelmSettings.defaultMaxStorageBytes,
        ocrEveryN: Int = 1,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        guard deepRecordingEnabled,
              !sample.redacted,
              !sample.screenLocked,
              sample.idleSeconds < idleThresholdSeconds,
              capturer.isScreenCaptureTrusted else {
            return
        }

        let now = sample.timestamp
        pruneIfNeeded(retentionDays: retentionDays, maxStorageBytes: maxStorageBytes, now: now)

        var triggerToLaunch: String?
        lock.lock()
        let chosen: String?
        if let lastSaved = lastSavedAt {
            if now.timeIntervalSince(lastSaved) >= _heartbeatIntervalSeconds {
                chosen = "heartbeat"
            } else if _visualCheckIntervalSeconds > 0,
                      (lastVisualCheckAt == nil || now.timeIntervalSince(lastVisualCheckAt!) >= _visualCheckIntervalSeconds) {
                lastVisualCheckAt = now
                chosen = "visual_change"
            } else {
                chosen = nil
            }
        } else {
            lastVisualCheckAt = now
            chosen = "heartbeat"
        }

        if let chosen {
            if !isCaptureInFlight {
                isCaptureInFlight = true
                triggerToLaunch = chosen
            } else {
                enqueuePendingCaptureLocked(PendingCaptureRequest(
                    sample: sample,
                    trigger: chosen,
                    priority: Self.priority(for: chosen),
                    declaredTaskId: declaredTaskId,
                    ocrEveryN: ocrEveryN,
                    onCompleted: onCompleted
                ))
            }
        }
        lock.unlock()

        guard let launchTrigger = triggerToLaunch else { return }
        launchCaptureTask(
            sample: sample,
            trigger: launchTrigger,
            declaredTaskId: declaredTaskId,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    public func triggerAppFocusCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval = 180.0,
        ocrEveryN: Int = 1,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        guard deepRecordingEnabled,
              !sample.redacted,
              !sample.screenLocked,
              sample.idleSeconds < idleThresholdSeconds,
              capturer.isScreenCaptureTrusted else {
            return
        }

        let now = sample.timestamp
        var launchNow = false
        lock.lock()
        if let lastFocus = lastAppFocusCaptureAt, now.timeIntervalSince(lastFocus) < _appFocusDebounceSeconds {
            lock.unlock()
            return
        }
        lastAppFocusCaptureAt = now
        if !isCaptureInFlight {
            isCaptureInFlight = true
            launchNow = true
        } else {
            enqueuePendingCaptureLocked(PendingCaptureRequest(
                sample: sample,
                trigger: ActivityEventKind.appFocus.rawValue,
                priority: Self.priority(for: ActivityEventKind.appFocus.rawValue),
                declaredTaskId: declaredTaskId,
                ocrEveryN: ocrEveryN,
                onCompleted: onCompleted
            ))
        }
        lock.unlock()

        guard launchNow else { return }
        launchCaptureTask(
            sample: sample,
            trigger: ActivityEventKind.appFocus.rawValue,
            declaredTaskId: declaredTaskId,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    /// Captures on-demand when switching to a weak-title / multi-purpose page that needs body OCR for semantic classification.
    /// Throttled by `minWindowChangeOCRIntervalSeconds` (3s) and protected by visual de-duplication + single-flight gate.
    public func triggerWindowContextCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval = 180.0,
        ocrEveryN: Int = 1,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        triggerSecondaryCaptureIfNeeded(
            sample: sample,
            trigger: "window_change",
            minInterval: minWindowChangeOCRIntervalSeconds,
            lastCaptureAt: \.lastWindowChangeCaptureAt,
            deepRecordingEnabled: deepRecordingEnabled,
            declaredTaskId: declaredTaskId,
            idleThresholdSeconds: idleThresholdSeconds,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    /// Captures shortly after a click, with its own debounce and dual visual de-duplication.
    public func triggerClickCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval = 180.0,
        ocrEveryN: Int = 1,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        triggerSecondaryCaptureIfNeeded(
            sample: sample,
            trigger: ActivityEventKind.click.rawValue,
            minInterval: clickCaptureMinIntervalSeconds,
            lastCaptureAt: \.lastClickCaptureAt,
            deepRecordingEnabled: deepRecordingEnabled,
            declaredTaskId: declaredTaskId,
            idleThresholdSeconds: idleThresholdSeconds,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    /// Captures after typing pauses (last keystroke quiet for a short period), de-duplicated.
    public func triggerTypingPauseCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval = 180.0,
        ocrEveryN: Int = 1,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        triggerSecondaryCaptureIfNeeded(
            sample: sample,
            trigger: ActivityEventKind.typingPause.rawValue,
            minInterval: typingPauseCaptureMinIntervalSeconds,
            lastCaptureAt: \.lastTypingPauseCaptureAt,
            deepRecordingEnabled: deepRecordingEnabled,
            declaredTaskId: declaredTaskId,
            idleThresholdSeconds: idleThresholdSeconds,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    private func triggerSecondaryCaptureIfNeeded(
        sample: ActivitySample,
        trigger: String,
        minInterval: TimeInterval,
        lastCaptureAt: ReferenceWritableKeyPath<NativeScreenRecorder, Date?>,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        idleThresholdSeconds: TimeInterval,
        ocrEveryN: Int,
        onCompleted: (@Sendable () -> Void)?
    ) {
        guard deepRecordingEnabled,
              !sample.redacted,
              !sample.screenLocked,
              sample.idleSeconds < idleThresholdSeconds,
              capturer.isScreenCaptureTrusted else {
            return
        }

        let now = sample.timestamp
        var launchNow = false
        lock.lock()
        if let last = self[keyPath: lastCaptureAt], now.timeIntervalSince(last) < minInterval {
            lock.unlock()
            return
        }
        self[keyPath: lastCaptureAt] = now
        if !isCaptureInFlight {
            isCaptureInFlight = true
            launchNow = true
        } else {
            enqueuePendingCaptureLocked(PendingCaptureRequest(
                sample: sample,
                trigger: trigger,
                priority: Self.priority(for: trigger),
                declaredTaskId: declaredTaskId,
                ocrEveryN: ocrEveryN,
                onCompleted: onCompleted
            ))
        }
        lock.unlock()

        guard launchNow else { return }
        launchCaptureTask(
            sample: sample,
            trigger: trigger,
            declaredTaskId: declaredTaskId,
            ocrEveryN: ocrEveryN,
            onCompleted: onCompleted
        )
    }

    private func enqueuePendingCaptureLocked(_ request: PendingCaptureRequest) {
        guard let existing = pendingCapture else {
            pendingCapture = request
            return
        }
        if request.priority >= existing.priority {
            let prevCallback = existing.onCompleted
            let newCallback = request.onCompleted
            let combined: (@Sendable () -> Void)?
            if prevCallback == nil && newCallback == nil {
                combined = nil
            } else {
                combined = {
                    prevCallback?()
                    newCallback?()
                }
            }
            pendingCapture = PendingCaptureRequest(
                sample: request.sample,
                trigger: request.trigger,
                priority: request.priority,
                declaredTaskId: request.declaredTaskId,
                ocrEveryN: request.ocrEveryN,
                onCompleted: combined
            )
        } else if let droppedCallback = request.onCompleted {
            let existingCallback = existing.onCompleted
            pendingCapture = PendingCaptureRequest(
                sample: existing.sample,
                trigger: existing.trigger,
                priority: existing.priority,
                declaredTaskId: existing.declaredTaskId,
                ocrEveryN: existing.ocrEveryN,
                onCompleted: {
                    droppedCallback()
                    existingCallback?()
                }
            )
        }
    }

    private struct CaptureRuntimeSnapshot: Sendable {
        let histogram: [Double]?
        let thumbnailRGB: [UInt8]?
        let savedAt: Date?
        let heartbeatIntervalSeconds: TimeInterval
        let jpegQuality: CGFloat
        let visionOCREnabled: Bool
        let ocrLanguages: [String]
    }

    private func readCaptureRuntimeSnapshot() -> CaptureRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return CaptureRuntimeSnapshot(
            histogram: lastSavedHistogram,
            thumbnailRGB: lastSavedThumbnailRGB,
            savedAt: lastSavedAt,
            heartbeatIntervalSeconds: _heartbeatIntervalSeconds,
            jpegQuality: _jpegQuality,
            visionOCREnabled: _visionOCREnabled,
            ocrLanguages: _ocrLanguages
        )
    }

    private func claimUniqueOCRText(_ normalized: String, forSessionId sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if lastOCRTextBySession[sessionId] == normalized {
            return false
        }
        if lastOCRTextBySession[sessionId] == nil {
            while lastOCRSessionOrder.count >= maxCachedOCRSessions {
                let evicted = lastOCRSessionOrder.removeFirst()
                lastOCRTextBySession.removeValue(forKey: evicted)
            }
            lastOCRSessionOrder.append(sessionId)
        }
        lastOCRTextBySession[sessionId] = normalized
        return true
    }

    private struct SavedSnapshotContext: Sendable {
        let fileURL: URL
        let snapshotId: String
        let sessionId: String
        let timestampMs: Int64
        let shouldRunOCR: Bool
        let ocrLanguages: [String]
    }

    private func claimOCRCoolDownSlot(trigger: String, windowKey: String, timestamp: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if trigger != ActivityEventKind.appFocus.rawValue,
           let lastOCRRunAt,
           timestamp >= lastOCRRunAt {
            let isDifferentWindow = (lastOCRWindowKey != nil && lastOCRWindowKey != windowKey)
            let requiredInterval = isDifferentWindow ? minWindowChangeOCRIntervalSeconds : minNonFocusOCRIntervalSeconds
            if timestamp.timeIntervalSince(lastOCRRunAt) < requiredInterval {
                return false
            }
        }
        lastOCRRunAt = timestamp
        lastOCRWindowKey = windowKey
        return true
    }

    private func saveCapturedSnapshotSync(
        _ image: CGImage,
        sample: ActivitySample,
        sessionId: String?,
        trigger: String,
        declaredTaskId: String?,
        runOCR: Bool,
        ocrEveryN: Int,
        ocrLanguages: [String]?
    ) throws -> SavedSnapshotContext? {
        defer {
            malloc_zone_pressure_relief(nil, 0)
        }
        return try autoreleasepool { () -> SavedSnapshotContext? in
            // Hard privacy guard: NEVER save screenshot or run OCR on redacted or locked samples.
            guard !sample.redacted, !sample.screenLocked else {
                return nil
            }

            let signature = ImageHistogram.computeVisualSignature(from: image, bins: 32)
            let histogram = signature.histogram
            let thumbnailRGB = signature.thumbnailRGB
            let hashHex = signature.hashHex
            let runtime = readCaptureRuntimeSnapshot()

            let histDiff: Double
            if let prevHist = runtime.histogram {
                histDiff = ImageHistogram.histogramDistance(from: prevHist, to: histogram)
            } else {
                histDiff = 1.0
            }

            let pixelDiff: Double
            if let prevThumb = runtime.thumbnailRGB {
                pixelDiff = ImageHistogram.pixelDiffPercentage(from: prevThumb, to: thumbnailRGB)
            } else {
                pixelDiff = 1.0
            }

            let diffPct = max(histDiff, pixelDiff)
            let isHeartbeatDue = runtime.savedAt.map { sample.timestamp.timeIntervalSince($0) >= runtime.heartbeatIntervalSeconds } ?? true
            // All triggers respect histogram + pixel diff de-duplication unless heartbeat is due or baseline is empty.
            let shouldSave = runtime.histogram == nil
                || isHeartbeatDue
                || histDiff >= minHistogramDiffPct
                || pixelDiff >= minPixelDiffPct

            guard shouldSave else {
                return nil
            }

            let dayFolder = DayHelmDateFormatting.dayString(from: sample.timestamp)
            let tsMs = Int64(sample.timestamp.timeIntervalSince1970 * 1000)
            let fileURL = snapshotsRootDir
                .appendingPathComponent(dayFolder, isDirectory: true)
                .appendingPathComponent("\(tsMs)-\(hashHex).jpg")

            let sizeBytes = try ScreenSnapshotCapturer.encodeJPEG(image: image, to: fileURL, quality: runtime.jpegQuality)

            let targetSessionId: String
            if let explicit = sessionId {
                targetSessionId = explicit
            } else {
                targetSessionId = try database.ensureActiveSession(
                    atMs: tsMs,
                    triggerKind: trigger,
                    appName: sample.appName,
                    declaredTaskId: declaredTaskId,
                    project: declaredTaskId
                )
            }

            let recordedSnap = try database.insertSnapshot(
                sessionId: targetSessionId,
                timestampMs: tsMs,
                filePath: fileURL.path,
                width: image.width,
                height: image.height,
                sizeBytes: sizeBytes,
                trigger: trigger,
                appName: sample.appName,
                windowTitle: sample.windowTitle,
                hashHex: hashHex,
                histogram: histogram,
                diffPct: diffPct,
                storageTier: "hot",
                declaredTaskId: declaredTaskId,
                project: declaredTaskId
            )

            let currentSavedCount = recordSavedSnapshot(
                histogram: histogram,
                thumbnailRGB: thumbnailRGB,
                timestamp: sample.timestamp
            )

            let effectiveRunOCR = runOCR && runtime.visionOCREnabled
            let effectiveLanguages = ocrLanguages ?? runtime.ocrLanguages
            let ocrWindowKey = "\(sample.appName)|\(sample.windowTitle ?? "")"
            let shouldRunOCRNow = effectiveRunOCR
                && Self.shouldRunOCR(savedCount: currentSavedCount, trigger: trigger, ocrEveryN: ocrEveryN)
                && claimOCRCoolDownSlot(trigger: trigger, windowKey: ocrWindowKey, timestamp: sample.timestamp)

            return SavedSnapshotContext(
                fileURL: fileURL,
                snapshotId: recordedSnap.id,
                sessionId: targetSessionId,
                timestampMs: tsMs,
                shouldRunOCR: shouldRunOCRNow,
                ocrLanguages: effectiveLanguages
            )
        }
    }

    private func runOCROnSavedSnapshot(_ context: SavedSnapshotContext) async {
        guard context.shouldRunOCR else { return }
        if let ocr = try? await VisionOCRService.recognizeText(
            at: context.fileURL,
            maxDimension: 1280,
            languages: context.ocrLanguages
        ) {
            let trimmed = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let normalized = trimmed
                    .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .joined(separator: " ")
                    .lowercased()
                if claimUniqueOCRText(normalized, forSessionId: context.sessionId) {
                    _ = try? database.insertOCRFrame(
                        snapshotId: context.snapshotId,
                        sessionId: context.sessionId,
                        text: trimmed,
                        charCount: ocr.charCount,
                        tokenCount: ocr.tokenCount,
                        createdAtMs: context.timestampMs
                    )
                }
            }
        }
    }

    /// Processes an in-memory `CGImage` against privacy guard, 32-bin histogram + pixel diff deduplication,
    /// JPEG save, SQLite & Vision OCR (`ocrEveryN` + consecutive session OCR dedup).
    /// Returns `true` if the snapshot was saved, or `false` if skipped due to redaction/lock/deduplication.
    @discardableResult
    public func processCapturedImage(
        _ image: CGImage,
        sample: ActivitySample,
        sessionId: String? = nil,
        trigger: String,
        declaredTaskId: String? = nil,
        runOCR: Bool = true,
        ocrEveryN: Int = 1,
        ocrLanguages: [String]? = nil
    ) async throws -> Bool {
        guard let savedContext = try saveCapturedSnapshotSync(
            image,
            sample: sample,
            sessionId: sessionId,
            trigger: trigger,
            declaredTaskId: declaredTaskId,
            runOCR: runOCR,
            ocrEveryN: ocrEveryN,
            ocrLanguages: ocrLanguages
        ) else {
            return false
        }
        await runOCROnSavedSnapshot(savedContext)
        return true
    }

    @discardableResult
    private func recordSavedSnapshot(
        histogram: [Double],
        thumbnailRGB: [UInt8],
        timestamp: Date
    ) -> Int {
        lock.lock()
        lastSavedHistogram = histogram
        lastSavedThumbnailRGB = thumbnailRGB
        lastSavedAt = timestamp
        savedSnapshotCount += 1
        let count = savedSnapshotCount
        lock.unlock()
        return count
    }

    private func finishInFlightCapture() {
        lock.lock()
        let next = pendingCapture
        pendingCapture = nil
        if next == nil {
            isCaptureInFlight = false
        }
        lock.unlock()

        if let next {
            launchCaptureTask(
                sample: next.sample,
                trigger: next.trigger,
                declaredTaskId: next.declaredTaskId,
                ocrEveryN: next.ocrEveryN,
                onCompleted: next.onCompleted
            )
        }
    }

    private func shouldProceedAfterVisualProbe(sample: ActivitySample, runtime: CaptureRuntimeSnapshot) async throws -> Bool {
        let heartbeatDue = runtime.savedAt.map {
            sample.timestamp.timeIntervalSince($0) >= runtime.heartbeatIntervalSeconds
        } ?? true

        guard !heartbeatDue, let prevHist = runtime.histogram, let prevThumb = runtime.thumbnailRGB else {
            return true
        }

        let probeImage = try await self.capturer.captureProbeImage()
        return autoreleasepool {
            let probeHist = ImageHistogram.computeHistogram(from: probeImage, bins: 32)
            let probeThumb = ImageHistogram.computeThumbnailRGB(from: probeImage)
            let histDiff = ImageHistogram.histogramDistance(from: prevHist, to: probeHist)
            let pixelDiff = ImageHistogram.pixelDiffPercentage(from: prevThumb, to: probeThumb)
            return histDiff >= self.minHistogramDiffPct || pixelDiff >= self.minPixelDiffPct
        }
    }

    private func captureAndSaveSnapshotOnly(
        sample: ActivitySample,
        trigger: String,
        declaredTaskId: String?,
        runOCR: Bool,
        ocrEveryN: Int,
        ocrLanguages: [String]
    ) async throws -> SavedSnapshotContext? {
        let image = try await self.capturer.captureActiveDisplayImage()
        return try saveCapturedSnapshotSync(
            image,
            sample: sample,
            sessionId: nil,
            trigger: trigger,
            declaredTaskId: declaredTaskId,
            runOCR: runOCR,
            ocrEveryN: ocrEveryN,
            ocrLanguages: ocrLanguages
        )
    }

    private func launchCaptureTask(
        sample: ActivitySample,
        trigger: String,
        declaredTaskId: String?,
        ocrEveryN: Int,
        onCompleted: (@Sendable () -> Void)?
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                onCompleted?()
                return
            }
            defer {
                self.finishInFlightCapture()
                onCompleted?()
            }

            do {
                let runtime = self.readCaptureRuntimeSnapshot()
                if trigger == "visual_change" {
                    let proceed = try await self.shouldProceedAfterVisualProbe(sample: sample, runtime: runtime)
                    guard proceed else { return }
                }

                guard let savedContext = try await self.captureAndSaveSnapshotOnly(
                    sample: sample,
                    trigger: trigger,
                    declaredTaskId: declaredTaskId,
                    runOCR: runtime.visionOCREnabled,
                    ocrEveryN: ocrEveryN,
                    ocrLanguages: runtime.ocrLanguages
                ) else {
                    return
                }
                await self.runOCROnSavedSnapshot(savedContext)
            } catch {
                // Non-fatal: permission or transient display error should never interrupt recording
            }
        }
    }

    /// Public maintenance entry so retention/downsampling still runs even when capture is disabled or idle.
    public func runRetentionMaintenanceIfNeeded(
        retentionDays: Int,
        maxStorageBytes: Int64 = DayHelmSettings.defaultMaxStorageBytes,
        now: Date = Date()
    ) {
        pruneIfNeeded(retentionDays: retentionDays, maxStorageBytes: maxStorageBytes, now: now)
    }

    private func pruneIfNeeded(retentionDays: Int, maxStorageBytes: Int64, now: Date) {
        let shouldPrune: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if let last = lastPruneAt, now.timeIntervalSince(last) < 3600 {
                return false
            }
            lastPruneAt = now
            return true
        }()
        guard shouldPrune else { return }
        let db = database
        let root = snapshotsRootDir
        let downsampleAfter = downsampleAfterDays
        Task.detached(priority: .background) { [weak self] in
            if let self {
                // Tier 1: hot -> warm (1280px, quality 0.4) after 1 day
                _ = await self.downsampleOldSnapshots(
                    olderThanDays: downsampleAfter,
                    retentionDays: retentionDays,
                    maxWidth: 1280,
                    quality: 0.4,
                    sourceTier: "hot",
                    targetTier: "warm",
                    now: now
                )
                // Tier 2: warm -> cold (640px, quality 0.3) after 7 days when retention > 7
                if retentionDays > 7 {
                    _ = await self.downsampleOldSnapshots(
                        olderThanDays: 7,
                        retentionDays: retentionDays,
                        maxWidth: 640,
                        quality: 0.3,
                        sourceTier: "warm",
                        targetTier: "cold",
                        now: now
                    )
                }
            }
            _ = try? db.pruneOldSnapshots(olderThanDays: retentionDays, snapshotsRootDir: root, now: now)
            if maxStorageBytes > 0 {
                let targetBytes = Int64(Double(maxStorageBytes) * 0.75)
                _ = try? db.enforceSnapshotStorageCap(
                    maxTotalBytes: maxStorageBytes,
                    targetBytes: targetBytes,
                    snapshotsRootDir: root
                )
            }
        }
    }

    /// Multi-tier retention: shrink snapshots older than `olderThanDays` in `sourceTier` to `targetTier`.
    /// Missing or unreadable files are marked `pruned` so maintenance never retries them indefinitely.
    @discardableResult
    public func downsampleOldSnapshots(
        olderThanDays: Int,
        retentionDays: Int,
        maxWidth: Int = 480,
        quality: CGFloat = 0.4,
        sourceTier: String = "hot",
        targetTier: String = "downsampled",
        now: Date
    ) async -> (downsampled: Int, savedBytes: Int64) {
        let effectiveRetention = max(1, retentionDays)
        let effectiveDownsampleAfter = max(1, olderThanDays)
        guard effectiveRetention > effectiveDownsampleAfter else {
            return (0, 0)
        }

        let cutoff = now.addingTimeInterval(-Double(effectiveDownsampleAfter) * 86_400)
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
        guard let records = try? database.listSnapshotsForMaintenance(
            olderThanMs: cutoffMs,
            storageTier: sourceTier,
            limit: 500
        ) else {
            return (0, 0)
        }

        var downsampled = 0
        var savedBytes: Int64 = 0
        let fm = FileManager.default
        for record in records {
            autoreleasepool {
                let fileURL = URL(fileURLWithPath: record.filePath)
                guard fm.fileExists(atPath: fileURL.path),
                      let result = SnapshotDownsampler.downsampleJPEG(
                          at: fileURL,
                          maxWidth: maxWidth,
                          quality: quality
                      ) else {
                    try? database.updateSnapshotStorage(
                        snapshotId: record.id,
                        width: 0,
                        height: 0,
                        sizeBytes: 0,
                        storageTier: "pruned"
                    )
                    return
                }
                try? database.updateSnapshotStorage(
                    snapshotId: record.id,
                    width: result.width,
                    height: result.height,
                    sizeBytes: result.sizeBytes,
                    storageTier: targetTier
                )
                downsampled += 1
                savedBytes += max(0, record.sizeBytes - result.sizeBytes)
            }
        }
        return (downsampled, savedBytes)
    }
}

// MARK: - Snapshot Downsampling

public enum SnapshotDownsampler {
    /// Re-encodes a JPEG via a temporary file at a bounded pixel size and lower quality.
    /// Keeps the original file intact if re-encoding does not reduce byte size.
    /// Returns the resulting dimensions and byte size, or `nil` when the file cannot be read.
    @discardableResult
    public static func downsampleJPEG(
        at fileURL: URL,
        maxWidth: Int = 480,
        quality: CGFloat = 0.4
    ) -> (width: Int, height: Int, sizeBytes: Int64)? {
        autoreleasepool {
            let fm = FileManager.default
            guard fm.fileExists(atPath: fileURL.path),
                  let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return nil
            }

            let originalSize = Int64((try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0)
            let originalProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let originalWidth = originalProps?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let originalHeight = originalProps?[kCGImagePropertyPixelHeight] as? Int ?? 0

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(64, maxWidth),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            let tempURL = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString).jpg")
            defer { try? fm.removeItem(at: tempURL) }

            guard let newSizeBytes = try? ScreenSnapshotCapturer.encodeJPEG(
                image: thumbnail,
                to: tempURL,
                quality: quality
            ) else {
                return nil
            }

            if originalSize > 0 && newSizeBytes >= originalSize && originalWidth > 0 && originalHeight > 0 {
                return (originalWidth, originalHeight, originalSize)
            }

            do {
                _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
                let finalAttrs = try? fm.attributesOfItem(atPath: fileURL.path)
                let finalSize = (finalAttrs?[.size] as? NSNumber)?.int64Value ?? newSizeBytes
                return (thumbnail.width, thumbnail.height, finalSize)
            } catch {
                return nil
            }
        }
    }
}
