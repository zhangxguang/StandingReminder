# StandingReminder

一款使用 SwiftUI 和 SwiftData 构建的原生 macOS 工作状态记录器，支持坐姿办公、站立办公和休息三种状态。

## 运行

1. 使用 Xcode 打开 `StandingReminder.xcodeproj`。
2. 选择 `StandingReminder` scheme 和 `My Mac` 运行。

最低支持 macOS 14。记录保存在当前用户的 `Application Support/StandingReminder` 目录中。

Mac 进入睡眠、锁屏、切换用户或关机时，当前状态会自动切换为“休息”。唤醒或下次启动后会保持休息，直到手动选择新的办公状态；普通退出应用不会把离线时间计为休息。

历史页右上角可以把全部记录导出为 `.xlsx` Excel 表格，包含开始时间、结束时间、状态、持续分钟数和记录来源。

历史页默认使用四行六列的 24 小时网格，从左到右连续展示状态色块，并可切换回原有时间轴；应用会记住最后使用的历史显示模式。

设置页可以开启或关闭“坐姿超时提醒”，提醒时长默认为 30 分钟，可在 1–240 分钟之间调整。连续坐姿达到设定时长后，应用会通过 macOS 系统通知提示切换为站立办公或休息；第一次使用时需要允许通知权限。

## 测试

```sh
xcodebuild test \
  -project StandingReminder.xcodeproj \
  -scheme StandingReminder \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO
```
