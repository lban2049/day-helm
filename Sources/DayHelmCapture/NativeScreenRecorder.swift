import AppKit
import CoreGraphics
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

// MARK: - Screen Capture

public protocol ScreenCapturing: Sendable {
    var isScreenCaptureTrusted: Bool { get }
    func requestScreenCapturePermission() -> Bool
    func captureMainDisplayImage() async throws -> CGImage
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
    public init() {}

    public var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureMainDisplayImage() async throws -> CGImage {
        guard isScreenCaptureTrusted else {
            throw ScreenCaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let maxWidth = 1920
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

    @discardableResult
    public static func encodeJPEG(image: CGImage, to fileURL: URL, quality: CGFloat = 0.55) throws -> Int64 {
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

    public static func recognizeText(
        from image: CGImage,
        languages: [String] = defaultLanguages
    ) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = languages
                    request.usesLanguageCorrection = true

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])

                    let observations = request.results ?? []
                    let lines = observations.compactMap { obs -> String? in
                        guard let candidate = obs.topCandidates(1).first?.string
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !candidate.isEmpty else {
                            return nil
                        }
                        return candidate
                    }

                    let joined = lines.joined(separator: "\n")
                    let result = OCRResult(
                        text: joined,
                        charCount: joined.count,
                        tokenCount: ActivityDatabase.estimateTokenCount(joined)
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Native Event Monitor (Privacy-Safe: No Keystroke Characters Logged)

public struct NativeMonitorEvent: Sendable, Equatable {
    public let timestamp: Date
    public let kind: String
    public let appName: String?
    public let bundleId: String?

    public init(timestamp: Date, kind: String, appName: String? = nil, bundleId: String? = nil) {
        self.timestamp = timestamp
        self.kind = kind
        self.appName = appName
        self.bundleId = bundleId
    }
}

public final class NativeEventMonitor: @unchecked Sendable {
    private let clock: any DayHelmClock
    private let onEvent: @Sendable (NativeMonitorEvent) -> Void
    private let lock = NSLock()

    private var workspaceObserver: NSObjectProtocol?
    private var distributedObservers: [NSObjectProtocol] = []
    private var globalInputMonitor: Any?
    private var lastClickEmit: Date?
    private var lastKeypressEmit: Date?
    private var isStarted = false

    public init(
        clock: any DayHelmClock = SystemClock(),
        onEvent: @escaping @Sendable (NativeMonitorEvent) -> Void
    ) {
        self.clock = clock
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        let wsCenter = NSWorkspace.shared.notificationCenter
        let wsObs = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? app?.bundleIdentifier
            self.onEvent(NativeMonitorEvent(
                timestamp: self.clock.now(),
                kind: "app_focus",
                appName: name,
                bundleId: app?.bundleIdentifier
            ))
        }

        let distCenter = DistributedNotificationCenter.default()
        let lockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onEvent(NativeMonitorEvent(timestamp: self.clock.now(), kind: "lock"))
        }
        let unlockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onEvent(NativeMonitorEvent(timestamp: self.clock.now(), kind: "unlock"))
        }

        // Only observe event timing/counts; NEVER read event.characters or event.keyCode.
        let inputObs = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return }
            let now = self.clock.now()
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                guard self.shouldEmitThrottled(isKeypress: false, now: now, minInterval: 2.0) else { return }
                self.onEvent(NativeMonitorEvent(timestamp: now, kind: "click"))
            case .keyDown:
                guard self.shouldEmitThrottled(isKeypress: true, now: now, minInterval: 2.0) else { return }
                self.onEvent(NativeMonitorEvent(timestamp: now, kind: "keypress"))
            default:
                break
            }
        }

        lock.lock()
        workspaceObserver = wsObs
        distributedObservers = [lockObs, unlockObs]
        globalInputMonitor = inputObs
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let wsObs = workspaceObserver
        let distObs = distributedObservers
        let inputObs = globalInputMonitor
        workspaceObserver = nil
        distributedObservers = []
        globalInputMonitor = nil
        isStarted = false
        lock.unlock()

        if let wsObs {
            NSWorkspace.shared.notificationCenter.removeObserver(wsObs)
        }
        let distCenter = DistributedNotificationCenter.default()
        for obs in distObs {
            distCenter.removeObserver(obs)
        }
        if let inputObs {
            NSEvent.removeMonitor(inputObs)
        }
    }

    private func shouldEmitThrottled(isKeypress: Bool, now: Date, minInterval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isKeypress {
            if let last = lastKeypressEmit, now.timeIntervalSince(last) < minInterval {
                return false
            }
            lastKeypressEmit = now
            return true
        } else {
            if let last = lastClickEmit, now.timeIntervalSince(last) < minInterval {
                return false
            }
            lastClickEmit = now
            return true
        }
    }
}

// MARK: - Native Screen & OCR Recorder

public final class NativeScreenRecorder: @unchecked Sendable {
    public let database: ActivityDatabase
    public let snapshotsRootDir: URL
    public let capturer: any ScreenCapturing
    public let clock: any DayHelmClock

    public let appFocusDebounceSeconds: TimeInterval = 4.0
    public let visualCheckIntervalSeconds: TimeInterval = 12.0
    public let heartbeatIntervalSeconds: TimeInterval = 120.0
    public let minHistogramDiffPct: Double = 0.04
    public let jpegQuality: CGFloat = 0.55

    private let lock = NSLock()
    private var lastSavedHistogram: [Double]?
    private var lastSavedAt: Date?
    private var lastAppFocusCaptureAt: Date?
    private var lastVisualCheckAt: Date?
    private var lastPruneAt: Date?
    private var isCaptureInFlight: Bool = false

    public init(
        database: ActivityDatabase,
        snapshotsRootDir: URL,
        capturer: any ScreenCapturing = ScreenSnapshotCapturer(),
        clock: any DayHelmClock = SystemClock()
    ) {
        self.database = database
        self.snapshotsRootDir = snapshotsRootDir
        self.capturer = capturer
        self.clock = clock
    }

    public var isScreenCaptureTrusted: Bool {
        capturer.isScreenCaptureTrusted
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        capturer.requestScreenCapturePermission()
    }

    public func evaluatePeriodicCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        retentionDays: Int = 7,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        guard deepRecordingEnabled,
              !sample.redacted,
              !sample.screenLocked,
              capturer.isScreenCaptureTrusted else {
            return
        }

        let now = sample.timestamp
        pruneIfNeeded(retentionDays: retentionDays, now: now)

        var trigger: String?
        lock.lock()
        if !isCaptureInFlight {
            if let lastSaved = lastSavedAt {
                if now.timeIntervalSince(lastSaved) >= heartbeatIntervalSeconds {
                    trigger = "heartbeat"
                    isCaptureInFlight = true
                } else if lastVisualCheckAt == nil || now.timeIntervalSince(lastVisualCheckAt!) >= visualCheckIntervalSeconds {
                    lastVisualCheckAt = now
                    trigger = "visual_change"
                    isCaptureInFlight = true
                }
            } else {
                lastVisualCheckAt = now
                trigger = "heartbeat"
                isCaptureInFlight = true
            }
        }
        lock.unlock()

        guard let chosenTrigger = trigger else { return }
        launchCaptureTask(
            sample: sample,
            trigger: chosenTrigger,
            declaredTaskId: declaredTaskId,
            onCompleted: onCompleted
        )
    }

    public func triggerAppFocusCaptureIfNeeded(
        sample: ActivitySample,
        deepRecordingEnabled: Bool,
        declaredTaskId: String?,
        onCompleted: (@Sendable () -> Void)? = nil
    ) {
        guard deepRecordingEnabled,
              !sample.redacted,
              !sample.screenLocked,
              capturer.isScreenCaptureTrusted else {
            return
        }

        let now = sample.timestamp
        lock.lock()
        guard !isCaptureInFlight else {
            lock.unlock()
            return
        }
        if let lastFocus = lastAppFocusCaptureAt, now.timeIntervalSince(lastFocus) < appFocusDebounceSeconds {
            lock.unlock()
            return
        }
        lastAppFocusCaptureAt = now
        isCaptureInFlight = true
        lock.unlock()

        launchCaptureTask(
            sample: sample,
            trigger: "app_focus",
            declaredTaskId: declaredTaskId,
            onCompleted: onCompleted
        )
    }

    /// Processes an in-memory `CGImage` against privacy guard, 32-bin histogram deduplication, JPEG save, SQLite & Vision OCR.
    /// Returns `true` if the snapshot was saved, or `false` if skipped due to redaction/lock/deduplication.
    @discardableResult
    public func processCapturedImage(
        _ image: CGImage,
        sample: ActivitySample,
        sessionId: String? = nil,
        trigger: String,
        declaredTaskId: String? = nil,
        runOCR: Bool = true
    ) async throws -> Bool {
        // Hard privacy guard: NEVER save screenshot or run OCR on redacted or locked samples.
        guard !sample.redacted, !sample.screenLocked else {
            return false
        }

        let histogram = ImageHistogram.computeHistogram(from: image, bins: 32)
        let hashHex = ImageHistogram.computePerceptualHashHex(from: image)

        let prevState: (histogram: [Double]?, savedAt: Date?) = {
            lock.lock()
            defer { lock.unlock() }
            return (lastSavedHistogram, lastSavedAt)
        }()

        let diffPct: Double
        if let prevHist = prevState.histogram {
            diffPct = ImageHistogram.histogramDistance(from: prevHist, to: histogram)
        } else {
            diffPct = 1.0
        }

        let isHeartbeatDue = prevState.savedAt.map { sample.timestamp.timeIntervalSince($0) >= heartbeatIntervalSeconds } ?? true
        let isAppFocus = (trigger == "app_focus")
        let shouldSave = prevState.histogram == nil || isHeartbeatDue || isAppFocus || diffPct >= minHistogramDiffPct

        guard shouldSave else {
            return false
        }

        let dayFolder = DayHelmDateFormatting.dayString(from: sample.timestamp)
        let tsMs = Int64(sample.timestamp.timeIntervalSince1970 * 1000)
        let fileURL = snapshotsRootDir
            .appendingPathComponent(dayFolder, isDirectory: true)
            .appendingPathComponent("\(tsMs)-\(hashHex).jpg")

        let sizeBytes = try ScreenSnapshotCapturer.encodeJPEG(image: image, to: fileURL, quality: jpegQuality)

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

        recordSavedSnapshot(histogram: histogram, timestamp: sample.timestamp)

        if runOCR {
            if let ocr = try? await VisionOCRService.recognizeText(from: image), !ocr.text.isEmpty {
                _ = try? database.insertOCRFrame(
                    snapshotId: recordedSnap.id,
                    sessionId: targetSessionId,
                    text: ocr.text,
                    charCount: ocr.charCount,
                    tokenCount: ocr.tokenCount,
                    createdAtMs: tsMs
                )
            }
        }

        return true
    }

    private func recordSavedSnapshot(histogram: [Double], timestamp: Date) {
        lock.lock()
        lastSavedHistogram = histogram
        lastSavedAt = timestamp
        lock.unlock()
    }

    private func finishInFlightCapture() {
        lock.lock()
        isCaptureInFlight = false
        lock.unlock()
    }

    private func launchCaptureTask(
        sample: ActivitySample,
        trigger: String,
        declaredTaskId: String?,
        onCompleted: (@Sendable () -> Void)?
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.finishInFlightCapture()
                onCompleted?()
            }

            do {
                let image = try await self.capturer.captureMainDisplayImage()
                _ = try await self.processCapturedImage(
                    image,
                    sample: sample,
                    trigger: trigger,
                    declaredTaskId: declaredTaskId,
                    runOCR: true
                )
            } catch {
                // Non-fatal: permission or transient display error should never interrupt recording
            }
        }
    }

    private func pruneIfNeeded(retentionDays: Int, now: Date) {
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
        Task.detached(priority: .background) {
            _ = try? db.pruneOldSnapshots(olderThanDays: retentionDays, snapshotsRootDir: root, now: now)
        }
    }
}
