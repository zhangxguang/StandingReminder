import SwiftData
import UserNotifications
import XCTest
@testable import StandingReminder

@MainActor
private final class FakeReminderNotificationCenter: ReminderNotificationCenter {
    var authorizationGranted = true
    var deliversCallbacksOnBackgroundQueue = false
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping @Sendable (Bool, String?) -> Void
    ) {
        let granted = authorizationGranted
        if deliversCallbacksOnBackgroundQueue {
            DispatchQueue.global().async {
                completion(granted, nil)
            }
        } else {
            completion(granted, nil)
        }
    }

    func add(
        _ request: UNNotificationRequest,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
        completion(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        requests.removeAll { identifiers.contains($0.identifier) }
    }
}

@MainActor
final class StandingReminderTests: XCTestCase {
    private func makeSystemUnderTest() throws -> (ModelContainer, SessionController) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkSession.self, configurations: configuration)
        let controller = SessionController(
            context: container.mainContext,
            observeLifecycle: false,
            heartbeatEnabled: false,
            recoverAbandonedSessions: false
        )
        return (container, controller)
    }

    func testStartAndSwitchUseSameBoundaryDate() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 1_000)
        let switchDate = start.addingTimeInterval(600)

        controller.start(.sitting, at: start)
        controller.switchState(to: .standing, at: switchDate)

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let sitting = try XCTUnwrap(sessions.first { $0.state == .sitting })
        let standing = try XCTUnwrap(sessions.first { $0.state == .standing })

        XCTAssertEqual(sitting.endAt, switchDate)
        XCTAssertEqual(standing.startAt, switchDate)
        XCTAssertEqual(controller.activeSession?.id, standing.id)
        XCTAssertEqual(sessions.filter { $0.endAt == nil }.count, 1)
    }

    func testSwitchClampsBoundaryWhenClockMovesBackward() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 1_000)
        let earlierDate = start.addingTimeInterval(-120)

        controller.start(.sitting, at: start)
        controller.switchState(to: .standing, at: earlierDate)

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let sitting = try XCTUnwrap(sessions.first { $0.state == .sitting })
        let standing = try XCTUnwrap(sessions.first { $0.state == .standing })
        XCTAssertEqual(sitting.endAt, start)
        XCTAssertEqual(sitting.lastHeartbeatAt, start)
        XCTAssertEqual(standing.startAt, start)
    }

    func testSwitchingToCurrentStateDoesNotCreateDuplicate() throws {
        let (container, controller) = try makeSystemUnderTest()
        let date = Date(timeIntervalSince1970: 2_000)
        controller.start(.resting, at: date)
        controller.switchState(to: .resting, at: date.addingTimeInterval(60))

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].endAt)
    }

    func testStopClosesActiveSession() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 3_000)
        let stop = start.addingTimeInterval(900)
        controller.start(.standing, at: start)
        controller.stop(at: stop)

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        XCTAssertNil(controller.activeSession)
        XCTAssertEqual(sessions.first?.endAt, stop)
    }

    func testLaunchRecoveryClosesSessionAtLastHeartbeat() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkSession.self, configurations: configuration)
        let start = Date(timeIntervalSince1970: 4_000)
        let heartbeat = start.addingTimeInterval(120)
        let abandoned = WorkSession(
            state: .sitting,
            startAt: start,
            lastHeartbeatAt: heartbeat
        )
        container.mainContext.insert(abandoned)
        try container.mainContext.save()

        let recoveredController = SessionController(
            context: container.mainContext,
            observeLifecycle: false,
            heartbeatEnabled: false,
            recoverAbandonedSessions: true
        )

        XCTAssertNil(recoveredController.activeSession)
        XCTAssertEqual(abandoned.endAt, heartbeat)
    }

    func testLaunchRecoveryKeepsSystemRestActive() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkSession.self, configurations: configuration)
        let start = Date(timeIntervalSince1970: 5_000)
        let systemRest = WorkSession(
            state: .resting,
            startAt: start,
            isSystemGeneratedRest: true
        )
        container.mainContext.insert(systemRest)
        try container.mainContext.save()

        let recoveredController = SessionController(
            context: container.mainContext,
            observeLifecycle: false,
            heartbeatEnabled: false,
            recoverAbandonedSessions: true
        )

        XCTAssertEqual(recoveredController.activeSession?.id, systemRest.id)
        XCTAssertNil(systemRest.endAt)
    }

    func testSystemInterruptionSwitchesWorkToRestAtSameBoundary() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 6_000)
        let sleepDate = start.addingTimeInterval(900)

        controller.start(.sitting, at: start)
        controller.beginSystemRest(at: sleepDate)

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let sitting = try XCTUnwrap(sessions.first { $0.state == .sitting })
        let resting = try XCTUnwrap(sessions.first { $0.state == .resting })
        XCTAssertEqual(sitting.endAt, sleepDate)
        XCTAssertEqual(resting.startAt, sleepDate)
        XCTAssertTrue(resting.isSystemGeneratedRest)
        XCTAssertEqual(controller.activeSession?.id, resting.id)
    }

    func testSystemInterruptionSplitsManualRestAndPreservesItsSource() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 7_000)
        let sleepDate = start.addingTimeInterval(300)

        controller.start(.resting, at: start)
        controller.beginSystemRest(at: sleepDate)

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let manualRest = try XCTUnwrap(sessions.first { !$0.isSystemGeneratedRest })
        let systemRest = try XCTUnwrap(sessions.first { $0.isSystemGeneratedRest })
        XCTAssertEqual(manualRest.endAt, sleepDate)
        XCTAssertEqual(systemRest.startAt, sleepDate)
        XCTAssertNil(systemRest.endAt)
        XCTAssertEqual(controller.activeSession?.id, systemRest.id)
    }

    func testSystemInterruptionClampsBoundaryWhenClockMovesBackward() throws {
        let (container, controller) = try makeSystemUnderTest()
        let start = Date(timeIntervalSince1970: 7_500)

        controller.start(.standing, at: start)
        controller.beginSystemRest(at: start.addingTimeInterval(-60))

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let standing = try XCTUnwrap(sessions.first { $0.state == .standing })
        let systemRest = try XCTUnwrap(sessions.first { $0.isSystemGeneratedRest })
        XCTAssertEqual(standing.endAt, start)
        XCTAssertEqual(systemRest.startAt, start)
    }

    func testInitialStorageErrorBlocksNewSessions() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkSession.self, configurations: configuration)
        let controller = SessionController(
            context: container.mainContext,
            observeLifecycle: false,
            heartbeatEnabled: false,
            recoverAbandonedSessions: false,
            initialStorageError: "数据库不可用"
        )

        controller.start(.sitting, at: Date(timeIntervalSince1970: 8_000))

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertNil(controller.activeSession)
        XCTAssertFalse(controller.storageIsAvailable)
        XCTAssertEqual(controller.errorMessage, "数据库不可用")
    }

    func testTimelineClipsSessionToSelectedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 24 * 60 * 60)
        let dayInterval = TimelineCalculator.dayInterval(containing: day, calendar: calendar)
        let session = WorkSession(
            state: .sitting,
            startAt: dayInterval.start.addingTimeInterval(-1_800),
            endAt: dayInterval.start.addingTimeInterval(3_600)
        )

        let slices = TimelineCalculator.slices(
            for: [session],
            on: day,
            calendar: calendar
        )

        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].start, dayInterval.start)
        XCTAssertEqual(slices[0].duration, 3_600)
    }

    func testTimelineDomainIsAtLeastEightHours() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 100_000)
        let interval = TimelineCalculator.dayInterval(containing: day, calendar: calendar)
        let slice = TimelineSlice(
            sessionID: UUID(),
            state: .resting,
            start: interval.start.addingTimeInterval(10 * 3_600),
            end: interval.start.addingTimeInterval(10.5 * 3_600),
            isActive: false
        )

        let domain = TimelineCalculator.domain(for: [slice], on: day, calendar: calendar)
        XCTAssertGreaterThanOrEqual(domain.duration, 8 * 3_600)
    }

    func testHistoryDurationTextIncludesSecondsAndHours() {
        XCTAssertEqual(TimelineCalculator.durationText(0), "0 秒")
        XCTAssertEqual(TimelineCalculator.durationText(125), "2 分 5 秒")
        XCTAssertEqual(
            TimelineCalculator.durationText(3_661),
            "1 小时 1 分 1 秒"
        )
    }

    func testEmptyTimelineUsesNineToEighteenDomain() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 200_000)

        let domain = TimelineCalculator.domain(for: [], on: day, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: domain.start), 9)
        XCTAssertEqual(calendar.component(.hour, from: domain.end), 18)
    }

    func testHourGridAlwaysCreatesFourRowsCoveringTwentyFourHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 24 * 60 * 60)

        let rows = TimelineCalculator.hourGridRows(
            for: [],
            on: day,
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.startHour), [0, 6, 12, 18])
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.duration == 6 * 3_600 })
        XCTAssertTrue(rows.allSatisfy { $0.slices.isEmpty })
    }

    func testHourGridAlignsWithWallClockAcrossSpringDSTTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        )
        let row = try XCTUnwrap(
            TimelineCalculator.hourGridRows(for: [], on: day, calendar: calendar).first
        )
        let threeAM = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3))
        )

        XCTAssertEqual(row.duration, 5 * 3_600)
        XCTAssertEqual(
            TimelineCalculator.hourGridFraction(for: threeAM, in: row, calendar: calendar),
            0.5,
            accuracy: 0.000_001
        )
    }

    func testHourGridKeepsRepeatedFallDSTHourMonotonic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))
        )
        let row = try XCTUnwrap(
            TimelineCalculator.hourGridRows(for: [], on: day, calendar: calendar).first
        )
        let firstOneThirty = row.start.addingTimeInterval(1.5 * 3_600)
        let secondOneThirty = row.start.addingTimeInterval(2.5 * 3_600)
        let twoAM = row.start.addingTimeInterval(3 * 3_600)
        let firstFraction = TimelineCalculator.hourGridFraction(
            for: firstOneThirty,
            in: row,
            calendar: calendar
        )
        let secondFraction = TimelineCalculator.hourGridFraction(
            for: secondOneThirty,
            in: row,
            calendar: calendar
        )

        XCTAssertEqual(row.duration, 7 * 3_600)
        XCTAssertLessThan(firstFraction, secondFraction)
        XCTAssertEqual(firstFraction, 1.25 / 6, accuracy: 0.000_001)
        XCTAssertEqual(secondFraction, 1.75 / 6, accuracy: 0.000_001)
        XCTAssertEqual(
            TimelineCalculator.hourGridFraction(for: twoAM, in: row, calendar: calendar),
            2.0 / 6,
            accuracy: 0.000_001
        )
    }

    func testHourGridClipsSessionAtSixHourRowBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 2 * 24 * 60 * 60)
        let dayStart = TimelineCalculator.dayInterval(
            containing: day,
            calendar: calendar
        ).start
        let sessionID = UUID()
        let slice = TimelineSlice(
            sessionID: sessionID,
            state: .sitting,
            start: dayStart.addingTimeInterval(5.5 * 3_600),
            end: dayStart.addingTimeInterval(6.5 * 3_600),
            isActive: false
        )

        let rows = TimelineCalculator.hourGridRows(
            for: [slice],
            on: day,
            calendar: calendar
        )
        let firstPart = try XCTUnwrap(rows[0].slices.first)
        let secondPart = try XCTUnwrap(rows[1].slices.first)
        let boundary = dayStart.addingTimeInterval(6 * 3_600)

        XCTAssertEqual(firstPart.sessionID, sessionID)
        XCTAssertEqual(firstPart.end, boundary)
        XCTAssertEqual(secondPart.sessionID, sessionID)
        XCTAssertEqual(secondPart.start, boundary)
        XCTAssertEqual(firstPart.duration + secondPart.duration, 3_600)
    }

    func testHourGridPreservesContinuousStateBoundaryAndRealGap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 3 * 24 * 60 * 60)
        let dayStart = TimelineCalculator.dayInterval(
            containing: day,
            calendar: calendar
        ).start
        let sittingEnd = dayStart.addingTimeInterval(9.75 * 3_600)
        let standingEnd = dayStart.addingTimeInterval(10.25 * 3_600)
        let restingStart = dayStart.addingTimeInterval(10.5 * 3_600)
        let slices = [
            TimelineSlice(
                sessionID: UUID(),
                state: .sitting,
                start: dayStart.addingTimeInterval(9.25 * 3_600),
                end: sittingEnd,
                isActive: false
            ),
            TimelineSlice(
                sessionID: UUID(),
                state: .standing,
                start: sittingEnd,
                end: standingEnd,
                isActive: false
            ),
            TimelineSlice(
                sessionID: UUID(),
                state: .resting,
                start: restingStart,
                end: dayStart.addingTimeInterval(11 * 3_600),
                isActive: false
            )
        ]

        let row = try XCTUnwrap(
            TimelineCalculator.hourGridRows(
                for: slices,
                on: day,
                calendar: calendar
            ).first { $0.startHour == 6 }
        )

        XCTAssertEqual(row.slices.map(\.state), [.sitting, .standing, .resting])
        XCTAssertEqual(row.slices[0].end, row.slices[1].start)
        XCTAssertEqual(row.slices[2].start.timeIntervalSince(row.slices[1].end), 15 * 60)
    }

    func testHourGridUsesOnlySelectedDayPortionOfCrossMidnightSession() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 4 * 24 * 60 * 60)
        let dayInterval = TimelineCalculator.dayInterval(
            containing: day,
            calendar: calendar
        )
        let session = WorkSession(
            state: .resting,
            startAt: dayInterval.start.addingTimeInterval(-30 * 60),
            endAt: dayInterval.start.addingTimeInterval(30 * 60)
        )
        let slices = TimelineCalculator.slices(
            for: [session],
            on: day,
            calendar: calendar
        )

        let rows = TimelineCalculator.hourGridRows(
            for: slices,
            on: day,
            calendar: calendar
        )
        let visiblePart = try XCTUnwrap(rows[0].slices.first)

        XCTAssertEqual(visiblePart.start, dayInterval.start)
        XCTAssertEqual(visiblePart.duration, 30 * 60)
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.slices.isEmpty })
    }

    func testOverlapValidationAllowsTouchingBoundaries() {
        let start = Date(timeIntervalSince1970: 10_000)
        let existing = WorkSession(
            state: .sitting,
            startAt: start,
            endAt: start.addingTimeInterval(600)
        )

        XCTAssertFalse(
            TimelineCalculator.overlaps(
                start: start.addingTimeInterval(600),
                end: start.addingTimeInterval(1_200),
                excluding: UUID(),
                sessions: [existing]
            )
        )
        XCTAssertTrue(
            TimelineCalculator.overlaps(
                start: start.addingTimeInterval(300),
                end: start.addingTimeInterval(900),
                excluding: UUID(),
                sessions: [existing]
            )
        )
    }

    func testOverlapValidationTreatsActiveSessionAsOpenEnded() {
        let start = Date(timeIntervalSince1970: 10_000)
        let active = WorkSession(state: .standing, startAt: start)

        XCTAssertTrue(
            TimelineCalculator.overlaps(
                start: start.addingTimeInterval(24 * 60 * 60),
                end: start.addingTimeInterval(25 * 60 * 60),
                excluding: UUID(),
                sessions: [active]
            )
        )
    }

    func testExcelExportCreatesValidWorkbookWithAllStates() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            WorkSession(
                state: .sitting,
                startAt: start,
                endAt: start.addingTimeInterval(30 * 60)
            ),
            WorkSession(
                state: .standing,
                startAt: start.addingTimeInterval(30 * 60),
                endAt: start.addingTimeInterval(75 * 60)
            ),
            WorkSession(
                state: .resting,
                startAt: start.addingTimeInterval(75 * 60),
                isSystemGeneratedRest: true
            )
        ]
        let snapshotDate = start.addingTimeInterval(90 * 60)

        let workbook = try ExcelExporter.export(sessions: sessions, snapshotDate: snapshotDate)
        XCTAssertEqual(Array(workbook.prefix(2)), [0x50, 0x4B])

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StandingReminder-\(UUID().uuidString).xlsx")
        try workbook.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let testArchive = Process()
        testArchive.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        testArchive.arguments = ["-t", temporaryURL.path]
        testArchive.standardOutput = Pipe()
        testArchive.standardError = Pipe()
        try testArchive.run()
        testArchive.waitUntilExit()
        XCTAssertEqual(testArchive.terminationStatus, 0)

        let inspectSheet = Process()
        inspectSheet.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        inspectSheet.arguments = ["-p", temporaryURL.path, "xl/worksheets/sheet1.xml"]
        let sheetOutput = Pipe()
        inspectSheet.standardOutput = sheetOutput
        inspectSheet.standardError = Pipe()
        try inspectSheet.run()
        inspectSheet.waitUntilExit()
        let sheetXML = String(
            data: sheetOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )

        XCTAssertEqual(inspectSheet.terminationStatus, 0)
        XCTAssertTrue(sheetXML?.contains("开始时间") == true)
        XCTAssertTrue(sheetXML?.contains("坐姿办公") == true)
        XCTAssertTrue(sheetXML?.contains("站立办公") == true)
        XCTAssertTrue(sheetXML?.contains("休息") == true)
        XCTAssertTrue(sheetXML?.contains("系统自动") == true)
        XCTAssertTrue(sheetXML?.contains("<v>30.0000000000</v>") == true)
        XCTAssertTrue(sheetXML?.contains("<v>45.0000000000</v>") == true)
        XCTAssertTrue(sheetXML?.contains("<v>15.0000000000</v>") == true)
    }

    func testMenuBarDurationUsesClockFormat() {
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            MenuBarLabel.durationText(from: start, to: start.addingTimeInterval(65)),
            "01:05"
        )
        XCTAssertEqual(
            MenuBarLabel.durationText(from: start, to: start.addingTimeInterval(3_661)),
            "01:01:01"
        )
        XCTAssertEqual(
            MenuBarLabel.durationText(from: start, to: start.addingTimeInterval(-10)),
            "00:00"
        )
    }

    func testSittingReminderDefaultsToEnabledAndThirtyMinutes() {
        let suiteName = "SittingReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = SittingReminderService(
            defaults: defaults,
            notificationCenter: FakeReminderNotificationCenter()
        )

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.minutes, 30)
    }

    func testSittingReminderSchedulesAndCancelsWithSessionState() async throws {
        let suiteName = "SittingReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationCenter = FakeReminderNotificationCenter()
        let service = SittingReminderService(
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        let start = Date(timeIntervalSince1970: 50_000)
        let sitting = WorkSession(state: .sitting, startAt: start)

        service.activeSessionDidChange(to: sitting, now: start)
        await waitForMainActorTasks { !notificationCenter.requests.isEmpty }

        let request = try XCTUnwrap(notificationCenter.requests.first)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 30 * 60, accuracy: 0.1)
        XCTAssertTrue(request.content.body.contains("30 分钟"))

        let standing = WorkSession(state: .standing, startAt: start.addingTimeInterval(60))
        service.activeSessionDidChange(to: standing, now: standing.startAt)

        XCTAssertTrue(notificationCenter.requests.isEmpty)
        XCTAssertFalse(notificationCenter.removedIdentifiers.isEmpty)
    }

    func testChangingReminderMinutesReschedulesCurrentSittingSession() async throws {
        let suiteName = "SittingReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationCenter = FakeReminderNotificationCenter()
        let service = SittingReminderService(
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        let start = Date.now
        service.activeSessionDidChange(
            to: WorkSession(state: .sitting, startAt: start),
            now: start
        )
        await waitForMainActorTasks { !notificationCenter.requests.isEmpty }

        service.minutes = 45
        await waitForMainActorTasks {
            guard let trigger = notificationCenter.requests.first?.trigger
                as? UNTimeIntervalNotificationTrigger
            else { return false }
            return abs(trigger.timeInterval - 45 * 60) < 0.1
        }

        let trigger = try XCTUnwrap(
            notificationCenter.requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertEqual(trigger.timeInterval, 45 * 60, accuracy: 0.1)
        XCTAssertEqual(defaults.integer(forKey: "sittingReminderMinutes"), 45)
    }

    func testSittingReminderHandlesAuthorizationCallbackFromBackgroundQueue() async throws {
        let suiteName = "SittingReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationCenter = FakeReminderNotificationCenter()
        notificationCenter.deliversCallbacksOnBackgroundQueue = true
        let service = SittingReminderService(
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        let start = Date(timeIntervalSince1970: 70_000)

        service.activeSessionDidChange(
            to: WorkSession(state: .sitting, startAt: start),
            now: start
        )
        await waitForMainActorTasks { !notificationCenter.requests.isEmpty }

        let request = try XCTUnwrap(notificationCenter.requests.first)
        XCTAssertEqual(request.identifier, "sitting-reminder")
        XCTAssertNil(service.notificationStatusText)
    }

    private func waitForMainActorTasks(
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}
