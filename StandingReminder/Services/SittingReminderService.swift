import Foundation
import UserNotifications

@MainActor
protocol ReminderNotificationCenter: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemReminderNotificationCenter: ReminderNotificationCenter {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            notificationCenter.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        notificationCenter.delegate = delegate
    }
}

private final class ReminderPresentationDelegate: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class SittingReminderService: ObservableObject {
    static let defaultMinutes = 30
    static let minimumMinutes = 1
    static let maximumMinutes = 240

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            settingsDidChange()
        }
    }

    @Published var minutes: Int {
        didSet {
            let clampedValue = Self.clampedMinutes(minutes)
            if minutes != clampedValue {
                minutes = clampedValue
            }
            defaults.set(clampedValue, forKey: Self.minutesKey)
            settingsDidChange()
        }
    }

    @Published private(set) var notificationStatusText: String?

    private static let enabledKey = "sittingReminderEnabled"
    private static let minutesKey = "sittingReminderMinutes"
    private static let requestIdentifier = "sitting-reminder"

    private let defaults: UserDefaults
    private let notificationCenter: ReminderNotificationCenter
    private let presentationDelegate = ReminderPresentationDelegate()
    private var activeSittingSessionID: UUID?
    private var activeSittingStart: Date?
    private var scheduledDeadline: Date?
    private var schedulingRevision = 0

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: ReminderNotificationCenter = SystemReminderNotificationCenter()
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter

        if defaults.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        }

        let savedMinutes = defaults.object(forKey: Self.minutesKey) as? Int
        self.minutes = Self.clampedMinutes(savedMinutes ?? Self.defaultMinutes)

        if let systemNotificationCenter = notificationCenter as? SystemReminderNotificationCenter {
            systemNotificationCenter.setDelegate(presentationDelegate)
        }
    }

    func activeSessionDidChange(to session: WorkSession?, now: Date = .now) {
        guard session?.state == .sitting else {
            activeSittingSessionID = nil
            activeSittingStart = nil
            scheduledDeadline = nil
            rescheduleReminder(now: now)
            return
        }

        if activeSittingSessionID != session?.id {
            scheduledDeadline = nil
        }
        activeSittingSessionID = session?.id
        activeSittingStart = session?.startAt
        rescheduleReminder(now: now)
    }

    static func clampedMinutes(_ minutes: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes))
    }

    static func remainingInterval(startAt: Date, now: Date, minutes: Int) -> TimeInterval {
        max(1, TimeInterval(clampedMinutes(minutes) * 60) - now.timeIntervalSince(startAt))
    }

    private func settingsDidChange() {
        if !isEnabled {
            notificationStatusText = nil
            scheduledDeadline = nil
        }
        rescheduleReminder()
    }

    private func rescheduleReminder(now: Date = .now) {
        schedulingRevision &+= 1
        let revision = schedulingRevision
        cancelPendingReminder()
        guard isEnabled, let activeSittingStart else { return }
        guard scheduledDeadline.map({ now < $0 }) ?? true else { return }

        let configuredMinutes = minutes
        Task {
            await scheduleReminder(
                startAt: activeSittingStart,
                now: now,
                minutes: configuredMinutes,
                revision: revision
            )
        }
    }

    private func scheduleReminder(
        startAt: Date,
        now: Date,
        minutes: Int,
        revision: Int
    ) async {
        do {
            let authorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            guard schedulingRevision == revision,
                  isEnabled,
                  activeSittingStart == startAt,
                  self.minutes == minutes
            else { return }

            guard authorized else {
                notificationStatusText = "系统通知权限未开启，请在“系统设置 → 通知”中允许 StandingReminder 通知。"
                return
            }

            notificationStatusText = nil
            let content = UNMutableNotificationContent()
            content.title = "该切换状态了"
            content.body = "你已经连续坐姿办公 \(minutes) 分钟，建议站起来办公或休息一下。"
            content.sound = .default

            let remainingInterval = Self.remainingInterval(
                startAt: startAt,
                now: now,
                minutes: minutes
            )
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: remainingInterval,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.requestIdentifier,
                content: content,
                trigger: trigger
            )
            try await notificationCenter.add(request)

            if schedulingRevision == revision, isEnabled, activeSittingStart == startAt {
                scheduledDeadline = now.addingTimeInterval(remainingInterval)
            } else {
                cancelPendingReminder()
            }
        } catch {
            if schedulingRevision == revision {
                notificationStatusText = "无法安排提醒：\(error.localizedDescription)"
            }
        }
    }

    private func cancelPendingReminder() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.requestIdentifier]
        )
    }
}
