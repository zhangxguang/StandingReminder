import AppKit
import Combine
import Foundation
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case record
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "记录"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .record: "timer"
        case .history: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

enum StopReason {
    case user
    case systemInterruption
    case applicationTermination
}

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var activeSession: WorkSession?
    @Published var selectedSection: AppSection = .record
    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    @Published private(set) var displayDate = Date.now
    @Published private(set) var storageIsAvailable = true

    private let context: ModelContext
    private let reminderService: SittingReminderService?
    private var heartbeatTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isPoweringOff = false
    private var storageFailureMessage: String?

    init(
        context: ModelContext,
        observeLifecycle: Bool = true,
        heartbeatEnabled: Bool = true,
        recoverAbandonedSessions: Bool = true,
        reminderService: SittingReminderService? = nil,
        initialStorageError: String? = nil
    ) {
        self.context = context
        self.reminderService = reminderService

        if let initialStorageError {
            markStorageUnavailable(initialStorageError)
        } else {
            do {
                if recoverAbandonedSessions {
                    try recoverAbandonedSessionsAtLaunch()
                } else {
                    activeSession = try fetchAllSessions().first(where: { $0.endAt == nil })
                }
            } catch {
                context.rollback()
                activeSession = nil
                markStorageUnavailable("读取本地记录失败：\(error.localizedDescription)")
            }
        }

        if observeLifecycle {
            beginObservingLifecycle()
        }
        if heartbeatEnabled, storageIsAvailable {
            startHeartbeatTimer()
        }
        reminderService?.activeSessionDidChange(to: activeSession)
    }

    func start(_ state: WorkState, at date: Date = .now) {
        guard ensureStorageIsAvailable() else { return }
        guard activeSession == nil else {
            switchState(to: state, at: date)
            return
        }

        let previousDisplayDate = displayDate
        let session = WorkSession(state: state, startAt: date)
        context.insert(session)
        activeSession = session
        displayDate = date
        guard saveChanges(onFailure: {
            self.activeSession = nil
            self.displayDate = previousDisplayDate
        }) else { return }
        reminderService?.activeSessionDidChange(to: session, now: date)
    }

    func switchState(to state: WorkState, at date: Date = .now) {
        guard ensureStorageIsAvailable() else { return }
        guard let current = activeSession else {
            start(state, at: date)
            return
        }
        guard current.state != state else { return }

        let boundary = max(date, current.startAt)
        let previousDisplayDate = displayDate
        current.endAt = boundary
        current.lastHeartbeatAt = boundary

        let next = WorkSession(state: state, startAt: boundary)
        context.insert(next)
        activeSession = next
        displayDate = boundary
        guard saveChanges(onFailure: {
            self.activeSession = current
            self.displayDate = previousDisplayDate
        }) else { return }
        reminderService?.activeSessionDidChange(to: next, now: boundary)
    }

    func stop(reason: StopReason = .user, at date: Date = .now) {
        guard ensureStorageIsAvailable() else { return }
        guard let current = activeSession else { return }
        let boundary = max(date, current.startAt)
        let previousDisplayDate = displayDate
        current.endAt = boundary
        current.lastHeartbeatAt = boundary
        activeSession = nil
        displayDate = boundary
        guard saveChanges(onFailure: {
            self.activeSession = current
            self.displayDate = previousDisplayDate
        }) else { return }
        reminderService?.activeSessionDidChange(to: nil, now: boundary)
    }

    func beginSystemRest(at date: Date = .now) {
        guard ensureStorageIsAvailable() else { return }
        if let current = activeSession {
            if current.state == .resting, current.isSystemGeneratedRest {
                let boundary = max(current.startAt, date)
                let previousDisplayDate = displayDate
                current.lastHeartbeatAt = boundary
                displayDate = boundary
                guard saveChanges(onFailure: {
                    self.displayDate = previousDisplayDate
                }) else { return }
                reminderService?.activeSessionDidChange(to: current, now: boundary)
                return
            }

            let boundary = max(date, current.startAt)
            let previousDisplayDate = displayDate
            current.endAt = boundary
            current.lastHeartbeatAt = boundary

            let restSession = WorkSession(
                state: .resting,
                startAt: boundary,
                isSystemGeneratedRest: true
            )
            context.insert(restSession)
            activeSession = restSession
            displayDate = boundary
            guard saveChanges(onFailure: {
                self.activeSession = current
                self.displayDate = previousDisplayDate
            }) else { return }
            reminderService?.activeSessionDidChange(to: restSession, now: boundary)
            return
        }

        let restSession = WorkSession(
            state: .resting,
            startAt: date,
            isSystemGeneratedRest: true
        )
        let previousDisplayDate = displayDate
        context.insert(restSession)
        activeSession = restSession
        displayDate = date
        guard saveChanges(onFailure: {
            self.activeSession = nil
            self.displayDate = previousDisplayDate
        }) else { return }
        reminderService?.activeSessionDidChange(to: restSession, now: date)
    }

    func sessionDidChangeExternally() {
        revision += 1
    }

    func dismissError() {
        errorMessage = nil
    }

    private func fetchAllSessions() throws -> [WorkSession] {
        let descriptor = FetchDescriptor<WorkSession>(
            sortBy: [SortDescriptor(\WorkSession.startAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func recoverAbandonedSessionsAtLaunch() throws {
        let abandoned = try fetchAllSessions().filter { $0.endAt == nil }
        guard !abandoned.isEmpty else { return }

        let recoverableRest = abandoned.first {
            $0.state == .resting && $0.isSystemGeneratedRest
        }

        for session in abandoned {
            if session.id == recoverableRest?.id {
                continue
            }
            let recoveryDate = max(session.startAt, session.lastHeartbeatAt)
            session.endAt = recoveryDate
        }
        do {
            try context.save()
            activeSession = recoverableRest
            displayDate = .now
            revision += 1
        } catch {
            context.rollback()
            throw error
        }
    }

    private func heartbeat(at date: Date = .now) {
        guard ensureStorageIsAvailable() else { return }
        guard let activeSession else { return }
        let previousDisplayDate = displayDate
        let boundary = max(activeSession.startAt, date)
        activeSession.lastHeartbeatAt = boundary
        displayDate = boundary
        saveChanges(onFailure: {
            self.displayDate = previousDisplayDate
        })
    }

    @discardableResult
    private func saveChanges(onFailure: (() -> Void)? = nil) -> Bool {
        do {
            try context.save()
            revision += 1
            return true
        } catch {
            context.rollback()
            onFailure?()
            markStorageUnavailable("保存本地记录失败：\(error.localizedDescription)")
            return false
        }
    }

    private func ensureStorageIsAvailable() -> Bool {
        guard storageIsAvailable else {
            errorMessage = storageFailureMessage ?? "本地记录当前不可用，请重新启动应用后重试。"
            return false
        }
        return true
    }

    private func markStorageUnavailable(_ message: String) {
        storageIsAvailable = false
        storageFailureMessage = message
        errorMessage = message
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func startHeartbeatTimer() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heartbeat()
            }
        }
    }

    private func beginObservingLifecycle() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]

        for name in workspaceNotifications {
            let observer = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.beginSystemRest()
                }
            }
            observers.append(observer)
        }

        let powerOffObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPoweringOff = true
                self?.beginSystemRest()
            }
        }
        observers.append(powerOffObserver)

        let lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.beginSystemRest()
            }
        }
        observers.append(lockObserver)

        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPoweringOff {
                    self.heartbeat()
                } else {
                    self.stop(reason: .applicationTermination)
                }
            }
        }
        observers.append(terminationObserver)
    }
}
