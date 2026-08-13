import SwiftUI

struct DailyHourGridView: View {
    let rows: [HourGridRow]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 14) {
                ForEach(rows) { row in
                    HourGridRowView(row: row, onSelect: onSelect)
                }
            }

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

                Text("点击已完成色块可编辑")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(22)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct HourGridRowView: View {
    @Environment(\.displayScale) private var displayScale

    let row: HourGridRow
    let onSelect: (UUID) -> Void

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    private var dividerColor: Color {
        Color(nsColor: .separatorColor).opacity(0.28)
    }

    private var borderColor: Color {
        Color(nsColor: .separatorColor).opacity(0.45)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { offset in
                    Text(String(format: "%02d:00", row.startHour + offset))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(height: 27)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.quaternary.opacity(0.65))

                    ForEach(row.slices) { slice in
                        let startX = xPosition(for: slice.start, width: width)
                        let endX = xPosition(for: slice.end, width: width)
                        let segmentWidth = max(hairlineWidth, endX - startX)

                        Button {
                            guard !slice.isActive else { return }
                            onSelect(slice.sessionID)
                        } label: {
                            Rectangle()
                                .fill(slice.state.color.gradient)
                                .overlay {
                                    if segmentWidth > 72 {
                                        Label(slice.state.shortTitle, systemImage: slice.state.symbolName)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 6)
                                    }
                                }
                                .overlay {
                                    if slice.isActive {
                                        Rectangle()
                                            .stroke(
                                                .white.opacity(0.85),
                                                style: StrokeStyle(lineWidth: 2, dash: [4])
                                            )
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(slice.isActive)
                        .frame(width: segmentWidth, height: proxy.size.height)
                        .position(x: startX + segmentWidth / 2, y: proxy.size.height / 2)
                        .help(helpText(for: slice))
                        .accessibilityLabel(helpText(for: slice))
                    }
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(height: hairlineWidth)
                }
            }
            .frame(height: 42)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(1..<6, id: \.self) { column in
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: hairlineWidth, height: proxy.size.height)
                            .position(
                                x: proxy.size.width * CGFloat(column) / 6,
                                y: proxy.size.height / 2
                            )
                    }
                }
                .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: hairlineWidth)
                .allowsHitTesting(false)
        }
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let fraction = TimelineCalculator.hourGridFraction(for: date, in: row)
        return CGFloat(fraction) * width
    }

    private func helpText(for slice: TimelineSlice) -> String {
        let start = slice.start.formatted(date: .omitted, time: .shortened)
        let end = slice.isActive ? "现在" : slice.end.formatted(date: .omitted, time: .shortened)
        let duration = TimelineCalculator.durationText(slice.duration)
        return "\(slice.state.title) · 时长：\(duration)\n\(start)–\(end)"
    }
}
