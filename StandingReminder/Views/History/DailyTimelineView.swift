import SwiftUI

struct DailyTimelineView: View {
    let slices: [TimelineSlice]
    let date: Date
    let onSelect: (UUID) -> Void

    private var domain: TimelineDomain {
        TimelineCalculator.domain(for: slices, on: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if slices.isEmpty {
                ContentUnavailableView(
                    "当天还没有记录",
                    systemImage: "timeline.selection",
                    description: Text("开始记录后，状态区段会显示在这里。")
                )
                .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 2)
                            .offset(y: 54)

                        ForEach(tickDates, id: \.self) { tick in
                            let x = xPosition(for: tick, width: width)
                            VStack(spacing: 6) {
                                Rectangle()
                                    .fill(.tertiary)
                                    .frame(width: 1, height: 10)
                                Text(tick, format: .dateTime.hour().minute())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            .position(x: x, y: 68)
                        }

                        ForEach(slices) { slice in
                            let startX = xPosition(for: slice.start, width: width)
                            let endX = xPosition(for: slice.end, width: width)

                            Button {
                                guard !slice.isActive else { return }
                                onSelect(slice.sessionID)
                            } label: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(slice.state.color.gradient)
                                    .overlay(alignment: .leading) {
                                        if endX - startX > 72 {
                                            Label(slice.state.shortTitle, systemImage: slice.state.symbolName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 9)
                                        }
                                    }
                                    .overlay {
                                        if slice.isActive {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [4]))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(slice.isActive)
                            .frame(width: max(4, endX - startX), height: 34)
                            .position(x: (startX + endX) / 2, y: 28)
                            .help(helpText(for: slice))
                            .accessibilityLabel(helpText(for: slice))
                        }
                    }
                }
                .frame(height: 92)

                HStack(spacing: 18) {
                    ForEach(WorkState.allCases) { state in
                        Label {
                            Text(state.title)
                        } icon: {
                            Circle()
                                .fill(state.color)
                                .frame(width: 9, height: 9)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("点击已完成区段可编辑")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(22)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator.opacity(0.5), lineWidth: 1)
        }
    }

    private var tickDates: [Date] {
        let hours = domain.duration / 3_600
        let strideHours = hours <= 12 ? 1 : (hours <= 18 ? 2 : 3)
        let strideSeconds = TimeInterval(strideHours * 3_600)
        var ticks: [Date] = []
        var current = domain.start

        while current <= domain.end {
            ticks.append(current)
            current = current.addingTimeInterval(strideSeconds)
        }
        if ticks.last != domain.end {
            ticks.append(domain.end)
        }
        return ticks
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        guard domain.duration > 0 else { return 0 }
        let fraction = date.timeIntervalSince(domain.start) / domain.duration
        return min(max(CGFloat(fraction) * width, 0), width)
    }

    private func helpText(for slice: TimelineSlice) -> String {
        let start = slice.start.formatted(date: .omitted, time: .shortened)
        let end = slice.isActive ? "现在" : slice.end.formatted(date: .omitted, time: .shortened)
        let duration = TimelineCalculator.durationText(slice.duration)
        return "\(slice.state.title) · 时长：\(duration)\n\(start)–\(end)"
    }
}
