import Foundation

public struct TaggedSample: Sendable, Equatable {
    public let sample: ActivitySample
    public let declaredTaskId: String?

    public init(sample: ActivitySample, declaredTaskId: String? = nil) {
        self.sample = sample
        self.declaredTaskId = declaredTaskId
    }
}

public enum EventMerger {
    public static let defaultPulsetime: TimeInterval = 60.0

    public static func merge(
        samples: [ActivitySample],
        declaredTaskId: String? = nil,
        pulsetime: TimeInterval = defaultPulsetime
    ) -> [EnrichedSpan] {
        let tagged = samples.map { TaggedSample(sample: $0, declaredTaskId: declaredTaskId) }
        return merge(taggedSamples: tagged, pulsetime: pulsetime)
    }

    public static func merge(
        taggedSamples: [TaggedSample],
        pulsetime: TimeInterval = defaultPulsetime
    ) -> [EnrichedSpan] {
        let sorted = taggedSamples.sorted { $0.sample.timestamp < $1.sample.timestamp }
        var spans: [EnrichedSpan] = []
        spans.reserveCapacity(sorted.count)
        for item in sorted {
            append(
                sample: item.sample,
                declaredTaskId: item.declaredTaskId,
                to: &spans,
                pulsetime: pulsetime
            )
        }
        return spans
    }

    public static func append(
        sample: ActivitySample,
        declaredTaskId: String?,
        to spans: inout [EnrichedSpan],
        pulsetime: TimeInterval = defaultPulsetime
    ) {
        if let lastIndex = spans.indices.last {
            let last = spans[lastIndex]
            let delta = sample.timestamp.timeIntervalSince(last.endedAt)
            if delta >= 0 && delta <= pulsetime && matchesIdentity(span: last, sample: sample, declaredTaskId: declaredTaskId) {
                spans[lastIndex].endedAt = max(last.endedAt, sample.timestamp)
                return
            }
        }

        spans.append(
            EnrichedSpan(
                startedAt: sample.timestamp,
                endedAt: sample.timestamp,
                appName: sample.appName,
                bundleId: sample.bundleId,
                windowTitle: sample.windowTitle,
                url: sample.url,
                declaredTaskId: declaredTaskId,
                redacted: sample.redacted
            )
        )
    }

    private static func matchesIdentity(
        span: EnrichedSpan,
        sample: ActivitySample,
        declaredTaskId: String?
    ) -> Bool {
        span.appName == sample.appName
            && span.bundleId == sample.bundleId
            && span.windowTitle == sample.windowTitle
            && span.url == sample.url
            && span.declaredTaskId == declaredTaskId
            && span.redacted == sample.redacted
    }
}
