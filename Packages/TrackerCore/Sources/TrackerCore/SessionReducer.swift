import Foundation

public enum SessionReducer {
    public static let duplicateWindow: TimeInterval = 60
    public static let reviewThreshold: TimeInterval = 12 * 3_600

    public static func reduce(events: [ConnectionEvent], corrections: [SessionCorrection], asOf: Date) -> SessionReduction {
        var sessions: [UsageSession] = []
        let devices = Set(events.map(\.deviceID))
        for deviceID in devices.sorted(by: { $0.uuidString < $1.uuidString }) {
            let deviceEvents = events.filter { $0.deviceID == deviceID }
            sessions += automaticSessions(deviceEvents.filter { $0.source == .shortcut }, asOf: asOf)
            let manualEvents = deviceEvents.filter { $0.source == .manual }
            let manualGroups = Dictionary(grouping: manualEvents, by: { $0.manualSessionID ?? $0.id })
            for (id, group) in manualGroups {
                let starts = group.filter { $0.kind == .start }, ends = group.filter { $0.kind == .end }
                let start = starts.sorted(by: eventOrder).first?.observedAt
                let end = ends.sorted(by: eventOrder).first?.observedAt
                let validPair = starts.count == 1 && ends.count == 1 && group.allSatisfy { $0.manualSessionID != nil }
                let status = validPair ? closedStatus(start: start, end: end, longSpanConfirmed: false) : SessionStatus.needsReview
                let issue = validPair ? boundaryIssue(start: start, end: end, longSpanConfirmed: false) : "手动记录端点不完整，请核对"
                sessions.append(UsageSession(id: id, deviceID: deviceID, start: start, end: end, status: status, source: .manual, anchorEventIDs: group.map(\.id).sorted(by: uuidOrder), issue: issue))
            }
        }

        var unresolved: [SessionCorrection] = []
        for correction in corrections.sorted(by: { uuidOrder($0.id, $1.id) }) {
            guard let index = sessions.firstIndex(where: {
                $0.id == correction.id && $0.deviceID == correction.deviceID && Set($0.anchorEventIDs) == Set(correction.anchorEventIDs)
            }) else { unresolved.append(correction); continue }
            sessions[index].start = correction.startOverride ?? sessions[index].start
            sessions[index].end = correction.endOverride ?? sessions[index].end
            sessions[index].tag = correction.tag
            sessions[index].note = correction.note
            if correction.excluded {
                sessions[index].status = .excluded
                sessions[index].issue = nil
            } else if sessions[index].start != nil && sessions[index].end != nil {
                sessions[index].status = closedStatus(start: sessions[index].start, end: sessions[index].end, longSpanConfirmed: correction.longSpanConfirmed)
                sessions[index].issue = boundaryIssue(start: sessions[index].start, end: sessions[index].end, longSpanConfirmed: correction.longSpanConfirmed)
            }
        }
        for correction in unresolved {
            let anchors = Set(correction.anchorEventIDs)
            for index in sessions.indices where sessions[index].deviceID == correction.deviceID && !anchors.isDisjoint(with: sessions[index].anchorEventIDs) && sessions[index].status != .excluded {
                sessions[index].status = .needsReview
                sessions[index].issue = "原记录发生变化，请核对"
            }
        }

        // Only known positive intervals can conflict. Unknown ends are never extrapolated.
        for i in sessions.indices {
            guard sessions[i].status != .excluded, let start = sessions[i].start, let end = sessions[i].end, start < end else { continue }
            for j in sessions.indices where j > i && sessions[j].deviceID == sessions[i].deviceID && sessions[j].status != .excluded {
                guard let otherStart = sessions[j].start, let otherEnd = sessions[j].end, otherStart < otherEnd, start < otherEnd, otherStart < end else { continue }
                sessions[i].status = .needsReview; sessions[j].status = .needsReview
                if sessions[i].issue == nil { sessions[i].issue = "与另一段记录重叠，请编辑或排除" }
                if sessions[j].issue == nil { sessions[j].issue = "与另一段记录重叠，请编辑或排除" }
            }
        }
        sessions.sort {
            let lhs = $0.start ?? $0.end ?? .distantPast, rhs = $1.start ?? $1.end ?? .distantPast
            return lhs == rhs ? uuidOrder($0.id, $1.id) : lhs < rhs
        }
        return SessionReduction(sessions: sessions, unresolvedCorrections: unresolved)
    }

    private static func automaticSessions(_ events: [ConnectionEvent], asOf: Date) -> [UsageSession] {
        var result: [UsageSession] = []
        let sorted = events.sorted(by: eventOrder)
        var pending: ConnectionEvent?
        var previousRaw: ConnectionEvent?
        var cursor = 0
        while cursor < sorted.count {
            let date = sorted[cursor].observedAt
            var next = cursor + 1
            while next < sorted.count && sorted[next].observedAt == date { next += 1 }
            let batch = Array(sorted[cursor..<next])
            if Set(batch.map(\.kind)).count > 1 {
                if let old = pending { result.append(makeSession(start: old, end: nil, status: .needsReview, issue: "后续记录顺序不明确，结束时间待核对")) }
                for kind in EventKind.allCases {
                    if let event = batch.first(where: { $0.kind == kind }) {
                        result.append(makeSession(start: kind == .start ? event : nil, end: kind == .end ? event : nil, status: .needsReview, issue: "同一时刻收到连接与断开，顺序待核对"))
                    }
                }
                pending = nil; previousRaw = nil
            } else {
                for event in batch {
                    let duplicate = previousRaw.map { $0.kind == event.kind && event.observedAt.timeIntervalSince($0.observedAt) <= duplicateWindow } ?? false
                    previousRaw = event
                    if duplicate { continue }
                    switch event.kind {
                    case .start:
                        if let old = pending { result.append(makeSession(start: old, end: nil, status: .needsReview, issue: "再次收到连接，上一段结束时间缺失")) }
                        pending = event
                    case .end:
                        if let start = pending {
                            result.append(makeSession(start: start, end: event, status: closedStatus(start: start.observedAt, end: event.observedAt, longSpanConfirmed: false), issue: boundaryIssue(start: start.observedAt, end: event.observedAt, longSpanConfirmed: false)))
                            pending = nil
                        } else {
                            result.append(makeSession(start: nil, end: event, status: .needsReview, issue: "开始时间缺失，请补录"))
                        }
                    }
                }
            }
            cursor = next
        }
        if let start = pending {
            let span = asOf.timeIntervalSince(start.observedAt)
            let needsReview = span > reviewThreshold || span < 0
            result.append(makeSession(start: start, end: nil, status: needsReview ? .needsReview : .awaitingEnd, issue: needsReview ? "结束时间待核对" : nil))
        }
        return result
    }

    private static func makeSession(start: ConnectionEvent?, end: ConnectionEvent?, status: SessionStatus, issue: String?) -> UsageSession {
        let anchor = start ?? end!
        return UsageSession(id: anchor.id, deviceID: anchor.deviceID, start: start?.observedAt, end: end?.observedAt, status: status, source: anchor.source, anchorEventIDs: [start?.id, end?.id].compactMap { $0 }.sorted(by: uuidOrder), issue: issue)
    }
    private static func closedStatus(start: Date?, end: Date?, longSpanConfirmed: Bool) -> SessionStatus {
        boundaryIssue(start: start, end: end, longSpanConfirmed: longSpanConfirmed) == nil ? .confirmed : .needsReview
    }
    private static func boundaryIssue(start: Date?, end: Date?, longSpanConfirmed: Bool) -> String? {
        guard let start, let end else { return "记录端点不完整，请核对" }
        guard end > start else { return "结束必须晚于开始，请核对" }
        if end.timeIntervalSince(start) > reviewThreshold && !longSpanConfirmed { return "记录跨度超过 12 小时，请确认或拆分" }
        return nil
    }
    private static func eventOrder(_ lhs: ConnectionEvent, _ rhs: ConnectionEvent) -> Bool { lhs.observedAt == rhs.observedAt ? uuidOrder(lhs.id, rhs.id) : lhs.observedAt < rhs.observedAt }
    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool { lhs.uuidString < rhs.uuidString }
}
