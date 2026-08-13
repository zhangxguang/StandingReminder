import Foundation

struct TimelineSlice: Identifiable, Equatable {
    let sessionID: UUID
    let state: WorkState
    let start: Date
    let end: Date
    let isActive: Bool

    var id: UUID { sessionID }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct TimelineDomain: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct HourGridRow: Identifiable, Equatable {
    let startHour: Int
    let start: Date
    let end: Date
    let slices: [TimelineSlice]

    var id: Int { startHour }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

enum TimelineCalculator {
    static func dayInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 24 * 60 * 60)
    }

    static func slices(
        for sessions: [WorkSession],
        on date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TimelineSlice] {
        let day = dayInterval(containing: date, calendar: calendar)

        return sessions.compactMap { session in
            let effectiveEnd = session.endAt ?? now
            let start = max(session.startAt, day.start)
            let end = min(effectiveEnd, day.end)
            guard end > start else { return nil }

            return TimelineSlice(
                sessionID: session.id,
                state: session.state,
                start: start,
                end: end,
                isActive: session.endAt == nil
            )
        }
        .sorted { $0.start < $1.start }
    }

    static func totals(for slices: [TimelineSlice]) -> [WorkState: TimeInterval] {
        Dictionary(grouping: slices, by: \.state)
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分 \(seconds) 秒"
        }
        if minutes > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        }
        return "\(seconds) 秒"
    }

    static func hourGridRows(
        for slices: [TimelineSlice],
        on date: Date,
        calendar: Calendar = .current
    ) -> [HourGridRow] {
        let day = dayInterval(containing: date, calendar: calendar)

        return stride(from: 0, to: 24, by: 6).map { startHour in
            let rowStart = dateAtHour(
                startHour,
                in: day,
                calendar: calendar
            )
            let rowEnd = dateAtHour(
                startHour + 6,
                in: day,
                calendar: calendar
            )
            let rowSlices = slices.compactMap { slice -> TimelineSlice? in
                let start = max(slice.start, rowStart)
                let end = min(slice.end, rowEnd)
                guard end > start else { return nil }

                return TimelineSlice(
                    sessionID: slice.sessionID,
                    state: slice.state,
                    start: start,
                    end: end,
                    isActive: slice.isActive
                )
            }

            return HourGridRow(
                startHour: startHour,
                start: rowStart,
                end: rowEnd,
                slices: rowSlices
            )
        }
    }

    static func domain(
        for slices: [TimelineSlice],
        on date: Date,
        calendar: Calendar = .current
    ) -> TimelineDomain {
        let day = dayInterval(containing: date, calendar: calendar)
        guard let earliest = slices.map(\.start).min(),
              let latest = slices.map(\.end).max()
        else {
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day.start) ?? day.start
            let end = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day.start)
                ?? start.addingTimeInterval(9 * 60 * 60)
            return TimelineDomain(start: start, end: end)
        }

        var start = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        var end = calendar.dateInterval(of: .hour, for: latest)?.end ?? latest
        let minimumDuration: TimeInterval = 8 * 60 * 60

        if end.timeIntervalSince(start) < minimumDuration {
            end = min(day.end, start.addingTimeInterval(minimumDuration))
            if end.timeIntervalSince(start) < minimumDuration {
                start = max(day.start, end.addingTimeInterval(-minimumDuration))
            }
        }

        return TimelineDomain(start: max(start, day.start), end: min(end, day.end))
    }

    static func overlaps(
        start: Date,
        end: Date,
        excluding sessionID: UUID,
        sessions: [WorkSession]
    ) -> Bool {
        sessions.contains { session in
            guard session.id != sessionID else { return false }
            let otherEnd = session.endAt ?? .distantFuture
            return session.startAt < end && otherEnd > start
        }
    }

    static func hourGridFraction(
        for date: Date,
        in row: HourGridRow,
        calendar: Calendar = .current
    ) -> Double {
        guard date > row.start else { return 0 }
        guard date < row.end else { return 1 }

        let timeZone = calendar.timeZone
        let startOffset = timeZone.secondsFromGMT(for: row.start)
        let dateOffset = timeZone.secondsFromGMT(for: date)
        let wallClockElapsed = date.timeIntervalSince(row.start)
            + Double(dateOffset - startOffset)
        var displayedElapsed = wallClockElapsed

        // A fall-back transition repeats a wall-clock hour. Compress the two
        // occurrences into the same hour cell while keeping positions monotonic.
        if let transition = timeZone.nextDaylightSavingTimeTransition(
            after: row.start.addingTimeInterval(-1)
        ), transition > row.start, transition < row.end {
            let offsetBefore = timeZone.secondsFromGMT(
                for: transition.addingTimeInterval(-1)
            )
            let offsetAfter = timeZone.secondsFromGMT(for: transition)
            let repeatedDuration = TimeInterval(offsetBefore - offsetAfter)

            if repeatedDuration > 0 {
                let repeatedStart = transition.timeIntervalSince(row.start)
                    + Double(offsetAfter - startOffset)
                let repeatedEnd = repeatedStart + repeatedDuration

                if date < transition, wallClockElapsed >= repeatedStart {
                    displayedElapsed = repeatedStart
                        + (wallClockElapsed - repeatedStart) / 2
                } else if date >= transition, wallClockElapsed < repeatedEnd {
                    displayedElapsed = repeatedStart
                        + repeatedDuration / 2
                        + (wallClockElapsed - repeatedStart) / 2
                }
            }
        }

        return min(max(displayedElapsed / (6 * 3_600), 0), 1)
    }

    private static func dateAtHour(
        _ hour: Int,
        in day: DateInterval,
        calendar: Calendar
    ) -> Date {
        guard hour > 0 else { return day.start }
        guard hour < 24 else { return day.end }

        return calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: day.start
        ) ?? calendar.date(byAdding: .hour, value: hour, to: day.start)
            ?? day.start.addingTimeInterval(TimeInterval(hour * 3_600))
    }
}
