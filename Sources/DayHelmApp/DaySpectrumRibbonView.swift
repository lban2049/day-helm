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

            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .overlay(
                            Text("尚无活动轨迹")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        )
                } else {
                    HStack(spacing: 1) {
                        ForEach(segments) { segment in
                            let fraction = max(0.0, segment.durationMinutes) / totalDurationMinutes
                            let segWidth = max(2.0, totalWidth * fraction - 1.0)
                            segmentView(for: segment)
                                .frame(width: segWidth, height: 22)
                                .help(tooltipText(for: segment))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }
            .frame(height: 22)

            legendRow
        }
    }

    @ViewBuilder
    private func segmentView(for segment: SpectrumSegment) -> some View {
        switch segment.kind {
        case .task(_, _, let colorHex):
            Rectangle()
                .fill(Color(hex: colorHex))
        case .thrashing:
            ThrashingHatchView()
        case .idle:
            Rectangle()
                .fill(Color.secondary.opacity(0.22))
        case .unassigned:
            Rectangle()
                .fill(Color.secondary.opacity(0.45))
        }
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            ForEach(budgets.prefix(4)) { budget in
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

    private func shortLabel(for name: String) -> String {
        if name.count <= 5 { return name }
        if name.contains("Hermes") { return "Hermes" }
        if name.contains("Infra") { return "Infra" }
        return String(name.prefix(4))
    }

    private func formatHHMM(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func tooltipText(for segment: SpectrumSegment) -> String {
        let range = "\(formatHHMM(segment.startedAt))–\(formatHHMM(segment.endedAt))"
        let mins = String(format: "%.0fm", segment.durationMinutes)
        switch segment.kind {
        case .task(_, let displayName, _):
            return "\(displayName) · \(mins) (\(range))"
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
