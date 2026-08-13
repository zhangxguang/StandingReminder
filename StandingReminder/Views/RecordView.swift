import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        Group {
            if let activeSession = controller.activeSession {
                ActiveSessionView(session: activeSession)
            } else {
                StateSelectionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct StateSelectionView: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("现在是什么状态？")
                    .font(.largeTitle.weight(.bold))

                Text("选择后立即开始记录")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            VStack(spacing: 14) {
                ForEach(WorkState.allCases) { state in
                    StateActionButton(state: state) {
                        controller.start(state)
                    }
                }
            }
            .frame(maxWidth: 480)
        }
    }
}

private struct ActiveSessionView: View {
    @EnvironmentObject private var controller: SessionController
    let session: WorkSession

    private var availableStates: [WorkState] {
        WorkState.allCases.filter { $0 != session.state }
    }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Image(systemName: session.state.symbolName)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(session.state.color)

                Text(session.state.title)
                    .font(.largeTitle.weight(.bold))

                Text("正在记录")
                    .font(.headline)
                    .foregroundStyle(session.state.color)
            }

            TimelineView(.periodic(from: session.startAt, by: 1)) { context in
                Text(Self.elapsedText(from: session.startAt, to: context.date))
                    .font(.system(size: 68, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("已持续\(Self.accessibleElapsedText(from: session.startAt, to: context.date))")
            }
            .padding(.vertical, 4)

            VStack(spacing: 14) {
                Text("一键切换状态")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    ForEach(availableStates) { state in
                        StateActionButton(state: state) {
                            controller.switchState(to: state)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)
        }
    }

    static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds >= 3_600 {
            return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func accessibleElapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return "\(hours)小时\(minutes)分钟\(remainder)秒"
    }
}
