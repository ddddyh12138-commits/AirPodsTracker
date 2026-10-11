import Foundation

public struct DayDuration: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public var day: Date
    public var duration: TimeInterval
    public init(day: Date, duration: TimeInterval) { self.day = day; self.duration = duration }
}

public struct ObservationSummary: Equatable, Sendable {
    public var confirmedDuration: TimeInterval
    public var sessionCount: Int
    public var needsReviewCount: Int
    public var conditionLabels: [String]
    public init(confirmedDuration: TimeInterval, sessionCount: Int, needsReviewCount: Int, conditionLabels: [String]) {
        self.confirmedDuration = confirmedDuration; self.sessionCount = sessionCount; self.needsReviewCount = needsReviewCount; self.conditionLabels = conditionLabels
    }
}

public enum IntervalMath {
    public static func confirmedDuration(sessions: [UsageSession], in range: DateInterval) -> TimeInterval {
        let intervals: [(Date, Date)] = sessions.compactMap { session -> (Date, Date)? in
            guard session.status == .confirmed, let start = session.start, let end = session.end else { return nil }
            let clippedStart = max(start, range.start), clippedEnd = min(end, range.end)
            return clippedStart < clippedEnd ? (clippedStart, clippedEnd) : nil
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        guard var active = intervals.first else { return 0 }
        var duration: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.0 <= active.1 { active.1 = max(active.1, interval.1) }
            else { duration += active.1.timeIntervalSince(active.0); active = interval }
        }
        return duration + active.1.timeIntervalSince(active.0)
    }

    public static func dailyDurations(sessions: [UsageSession], in range: DateInterval, calendar: Calendar) -> [DayDuration] {
        var day = calendar.startOfDay(for: range.start)
        var values: [DayDuration] = []
        while day < range.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            let start = max(day, range.start), end = min(next, range.end)
            if start < end { values.append(DayDuration(day: day, duration: confirmedDuration(sessions: sessions, in: DateInterval(start: start, end: end)))) }
            day = next
        }
        return values
    }

    public static func observationSummary(observation: ChargeObservation, sessions: [UsageSession], batteries: [BatterySnapshot], asOf: Date) -> ObservationSummary {
        let end = observation.endAt ?? asOf
        guard end > observation.startAt else { return ObservationSummary(confirmedDuration: 0, sessionCount: 0, needsReviewCount: 0, conditionLabels: ["电量条件不全"]) }
        let range = DateInterval(start: observation.startAt, end: end)
        let deviceSessions = sessions.filter { $0.deviceID == observation.deviceID }
        let confirmed = deviceSessions.filter { session in
            guard session.status == .confirmed, let start = session.start, let end = session.end else { return false }
            return start < range.end && end > range.start
        }
        let pending = deviceSessions.filter { session in
            guard session.status == .needsReview, let known = session.start ?? session.end else { return false }
            return known >= range.start && known < range.end
        }
        let startBattery = batteries.first { $0.id == observation.startSnapshotID }
        let endBattery = batteries.first { $0.id == observation.endSnapshotID }
        var labels: [String] = []
        if observation.endAt != nil && startBattery?.caseLevel != nil && endBattery?.caseLevel != nil { labels.append("起止齐全") }
        else { labels.append("电量条件不全") }
        if !pending.isEmpty { labels.append("存在待确认") }
        if observation.startReason.contains("补电") || (observation.endReason?.contains("补电") ?? false) { labels.append("有补电") }
        return ObservationSummary(confirmedDuration: confirmedDuration(sessions: deviceSessions, in: range), sessionCount: Set(confirmed.map(\.id)).count, needsReviewCount: pending.count, conditionLabels: labels)
    }
}
