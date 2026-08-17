import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var reminderService: SittingReminderService
    @EnvironmentObject private var updateService: UpdateService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("设置")
                        .font(.largeTitle.weight(.bold))
                    Text("控制坐姿办公提醒。设置会自动保存。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 22) {
                    Toggle(isOn: $reminderService.isEnabled) {
                        Label("坐姿超时提醒", systemImage: "bell.badge.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .toggleStyle(.switch)

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("提醒时间")
                                .font(.headline)
                            Text("连续坐姿办公达到该时长后提醒切换状态")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Stepper(
                            value: $reminderService.minutes,
                            in: SittingReminderService.minimumMinutes...SittingReminderService.maximumMinutes,
                            step: 1
                        ) {
                            Text("\(reminderService.minutes) 分钟")
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .frame(minWidth: 82, alignment: .trailing)
                        }
                        .disabled(!reminderService.isEnabled)
                    }

                    if let notificationStatusText = reminderService.notificationStatusText {
                        Label(notificationStatusText, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(24)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("应用更新")
                                .font(.title3.weight(.semibold))
                            Text("当前版本 \(updateService.versionDescription)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("检查更新…") {
                            updateService.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updateService.canCheckForUpdates)
                    }

                    Text("正式安装版会通过 GitHub Releases 安全检查更新，下载内容由 Sparkle 签名验证。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(36)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
