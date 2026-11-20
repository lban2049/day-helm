import DayHelmCore
import SwiftUI

struct DaySpectrumRibbonView: View {
    let segments: [SpectrumSegment]
    let budgets: [TaskBudget]

    private var totalDurationMinutes: Double {
        let sum = segments.reduce(0.0) { $0 + max(0.0, $1.durationMinutes) }
        return max(sum, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日时间光谱")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let first = segments.first, let last = segments.last {
                    Text("\(formatHHMM(first.startedAt)) – \(formatHHMM(last.endedAt))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            Group {
                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .overlay(
                            Text("尚无活动轨迹")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        )
                } else {
                    Canvas { context, size in
                        let totalWidth = max(1.0, size.width)
                        let gap: CGFloat = 1.0
                        var x: CGFloat = 0.0
                        let totalMinutes = totalDurationMinutes

                        for segment in segments {
                            let fraction = max(0.0, segment.durationMinutes) / totalMinutes
                            let segWidth = max(2.0, totalWidth * fraction - gap)
                            let rect = CGRect(x: x, y: 0, width: segWidth, height: size.height)

                            switch segment.kind {
                            case .task(_, _, let colorHex):
                                context.fill(Path(rect), with: .color(Color(hex: colorHex)))
                            case .activityMode(let rawValue):
                                let colorHex = ActivityMode(rawValue: rawValue)?.colorHex ?? "#64748B"
                                context.fill(Path(rect), with: .color(Color(hex: colorHex)))
                            case .thrashing:
                                context.fill(Path(rect), with: .color(Color(hex: "#EF4444").opacity(0.28)))
                                context.drawLayer { layerCtx in
                                    layerCtx.clip(to: Path(rect))
                                    var hatch = Path()
                                    var hx = rect.minX - rect.height
                                    while hx < rect.maxX + rect.height {
                                        hatch.move(to: CGPoint(x: hx, y: rect.maxY))
                                        hatch.addLine(to: CGPoint(x: hx + rect.height, y: rect.minY))
                                        hx += 6.0
                                    }
                                    layerCtx.stroke(hatch, with: .color(Color(hex: "#EF4444").opacity(0.85)), lineWidth: 1.5)
                                }
                            case .idle:
                                context.fill(Path(rect), with: .color(Color.secondary.opacity(0.22)))
                            case .unassigned:
                                context.fill(Path(rect), with: .color(Color.secondary.opacity(0.45)))
                            }
                            x += segWidth + gap
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .help(summaryTooltipText)
                }
            }
            .frame(height: 22)

            legendRow
        }
    }

    private var summaryTooltipText: String {
        guard let first = segments.first, let last = segments.last else { return "" }
        let thrashCount = segments.filter {
            if case .thrashing = $0.kind { return true }
            return false
        }.count
        let totalMins = Int(totalDurationMinutes.rounded())
        return "\(formatHHMM(first.startedAt))–\(formatHHMM(last.endedAt)) · \(segments.count) 段 · \(totalMins)m"
            + (thrashCount > 0 ? " · 乱切 \(thrashCount) 段" : "")
    }

    private var legendModes: [ActivityMode] {
        var present = Set<ActivityMode>()
        for segment in segments {
            if case .activityMode(let rawValue) = segment.kind,
               let mode = ActivityMode(rawValue: rawValue) {
                present.insert(mode)
            }
        }
        return ActivityMode.allCases.filter { present.contains($0) }
    }

    private var hasUnassignedSegments: Bool {
        segments.contains {
            if case .unassigned = $0.kind { return true }
            return false
        }
    }

    private var legendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(budgets) { budget in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: budget.colorHex))
                            .frame(width: 6, height: 6)
                        Text(shortLabel(for: budget.displayName))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ForEach(legendModes, id: \.rawValue) { mode in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: mode.colorHex))
                            .frame(width: 6, height: 6)
                        Text(mode.compactLabel)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if hasUnassignedSegments {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text("未指定")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 3) {
                    ThrashingHatchView()
                        .frame(width: 8, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    Text("乱切")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.28))
                        .frame(width: 8, height: 8)
                    Text("空闲")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shortLabel(for name: String) -> String {
        if name.count <= 5 { return name }
        if name.contains("Hermes") { return "Hermes" }
        if name.contains("Infra") { return "Infra" }
        return String(name.prefix(4))
    }

    private static let hhmmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func formatHHMM(_ date: Date) -> String {
        Self.hhmmFormatter.string(from: date)
    }

    private func tooltipText(for segment: SpectrumSegment) -> String {
        let range = "\(formatHHMM(segment.startedAt))–\(formatHHMM(segment.endedAt))"
        let mins = String(format: "%.0fm", segment.durationMinutes)
        switch segment.kind {
        case .task(_, let displayName, _):
            return "\(displayName) · \(mins) (\(range))"
        case .activityMode(let rawValue):
            let label = ActivityMode(rawValue: rawValue)?.displayName ?? rawValue
            return "\(label) · \(mins) (\(range))"
        case .thrashing(let switchCount):
            return "高频切换警示 (\(switchCount)次) · \(mins) (\(range))"
        case .idle:
            return "空闲/离开 · \(mins) (\(range))"
        case .unassigned:
            return "未指定专注 · \(mins) (\(range))"
        }
    }
}

struct ThrashingHatchView: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(DayHelmColors.destructiveRed.opacity(0.28))
            )
            var path = Path()
            let step: CGFloat = 5
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(
                path,
                with: .color(DayHelmColors.destructiveRed.opacity(0.9)),
                lineWidth: 1.5
            )
        }
    }
}
