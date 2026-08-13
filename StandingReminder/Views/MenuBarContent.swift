import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        if let session = controller.activeSession {
            ActiveMenuBarLabel(session: session)
        } else {
            Image(systemName: "figure.stand")
                .accessibilityLabel("StandingReminder，当前没有记录")
        }
    }

    static func durationText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds >= 3_600 {
            return String(
                format: "%02d:%02d:%02d",
                seconds / 3_600,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func accessibleDurationText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return "\(hours)小时\(minutes)分钟\(remainder)秒"
    }
}

private struct ActiveMenuBarLabel: View {
    let session: WorkSession
    @State private var displayDate = Date.now

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session.state.symbolName)
            Text(MenuBarLabel.durationText(from: session.startAt, to: displayDate))
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.state.title)，已持续\(MenuBarLabel.accessibleDurationText(from: session.startAt, to: displayDate))"
        )
        .task(id: session.id) {
            displayDate = .now
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                displayDate = .now
            }
        }
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        if let activeSession = controller.activeSession {
            Section("当前：\(activeSession.state.title)") {
                ForEach(WorkState.allCases.filter { $0 != activeSession.state }) { state in
                    Button {
                        controller.switchState(to: state)
                    } label: {
                        Label("切换到\(state.title)", systemImage: state.symbolName)
                    }
                }

                Button(role: .destructive) {
                    controller.stop()
                } label: {
                    Label("停止记录", systemImage: "stop.fill")
                }
            }
        } else {
            Section("开始记录") {
                ForEach(WorkState.allCases) { state in
                    Button {
                        controller.start(state)
                    } label: {
                        Label(state.title, systemImage: state.symbolName)
                    }
                }
            }
        }

        Divider()

        Button {
            showWindow(section: .record)
        } label: {
            Label("打开记录页", systemImage: "timer")
        }

        Button {
            showWindow(section: .history)
        } label: {
            Label("打开历史页", systemImage: "chart.xyaxis.line")
        }

        Button {
            showWindow(section: .settings)
        } label: {
            Label("打开设置页", systemImage: "gearshape")
        }

        Divider()

        Button("退出 StandingReminder") {
            controller.stop(reason: .applicationTermination)
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showWindow(section: AppSection) {
        controller.selectedSection = section
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
