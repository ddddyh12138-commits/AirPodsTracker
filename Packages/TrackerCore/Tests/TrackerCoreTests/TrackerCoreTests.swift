import XCTest
@testable import TrackerCore

final class TrackerCoreTests: XCTestCase {
    let device = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    func time(_ seconds: Double) -> Date { epoch.addingTimeInterval(seconds) }
    func event(_ kind: EventKind, _ seconds: Double, id: UUID = UUID()) -> ConnectionEvent {
        ConnectionEvent(id: id, deviceID: device, kind: kind, observedAt: time(seconds), savedAt: time(seconds), timeZoneID: "UTC")
    }
    func state() -> TrackerState { TrackerState(devices: [TrackedDevice(id: device, name: "耳机", createdAt: epoch)]) }
    func reduce(_ events: [ConnectionEvent], corrections: [SessionCorrection] = [], now: Double = 7_200) -> SessionReduction {
        SessionReducer.reduce(events: events, corrections: corrections, asOf: time(now))
    }

    func testOutOfOrderEventsCloseOneSession() {
        let a = event(.start, 0), b = event(.end, 3_600)
        let sessions = reduce([b, a]).sessions
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, a.id)
        XCTAssertEqual(sessions[0].status, .confirmed)
        XCTAssertEqual(IntervalMath.confirmedDuration(sessions: sessions, in: DateInterval(start: time(1_000), end: time(4_000))), 2_600)
    }

    func testDuplicateBurstUsesEarliestBoundaryWithoutDeletingEvidence() {
        let events = [event(.start, 0), event(.start, 40), event(.start, 80), event(.end, 600), event(.end, 630)]
        let sessions = reduce(events).sessions
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].start, time(0))
        XCTAssertEqual(sessions[0].end, time(600))
    }

    func testUnknownEndNeverBecomesNowAndTwelveHourThresholdIsInclusive() {
        let events = [event(.start, 0)]
        XCTAssertEqual(reduce(events, now: 43_200).sessions[0].status, .awaitingEnd)
        let old = reduce(events, now: 43_201).sessions
        XCTAssertEqual(old[0].status, .needsReview)
        XCTAssertNil(old[0].end)
        XCTAssertEqual(IntervalMath.confirmedDuration(sessions: old, in: DateInterval(start: time(0), end: time(86_400))), 0)
    }

    func testSecondStartDoesNotInventEndForPreviousStart() {
        let sessions = reduce([event(.start, 0), event(.start, 600), event(.end, 1_200)]).sessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].status, .needsReview)
        XCTAssertNil(sessions[0].end)
        XCTAssertEqual(sessions[1].status, .confirmed)
    }

    func testEqualTimestampOppositeEventsAreAmbiguousInBothInputOrders() {
        let a = event(.start, 0), b = event(.end, 0)
        let first = reduce([a, b]).sessions
        XCTAssertEqual(first, reduce([b, a]).sessions)
        XCTAssertTrue(first.allSatisfy { $0.status == .needsReview })
        XCTAssertEqual(first.count, 2)
    }

    func testLongClosedSessionRequiresExplicitConfirmation() {
        let a = event(.start, 0), b = event(.end, 50_000)
        XCTAssertEqual(reduce([a, b], now: 60_000).sessions[0].status, .needsReview)
        let correction = SessionCorrection(id: a.id, anchorEventIDs: [a.id, b.id], deviceID: device, longSpanConfirmed: true)
        XCTAssertEqual(reduce([a, b], corrections: [correction], now: 60_000).sessions[0].status, .confirmed)
    }

    func testLateEventPreservesOldDecisionAndBlocksChangedSegment() {
        let a = event(.start, 0), b = event(.end, 3_600), late = event(.start, 1_800)
        let correction = SessionCorrection(id: a.id, anchorEventIDs: [a.id, b.id], deviceID: device, endOverride: time(3_000), excluded: true)
        let result = reduce([a, b, late], corrections: [correction])
        XCTAssertEqual(result.unresolvedCorrections, [correction])
        XCTAssertTrue(result.sessions.allSatisfy { $0.status == .needsReview })
        XCTAssertTrue(result.sessions.allSatisfy { $0.issue == "原记录发生变化，请核对" })
    }

    func testManualEventsDoNotConsumeAutomaticEndpoints() throws {
        var value = state()
        value.events = [event(.start, 0), event(.end, 3_600)]
        try TrackerEngine.addManualSession(state: &value, deviceID: device, start: time(3_600), end: time(4_000), tag: "补录", note: nil, id: UUID())
        let sessions = reduce(value.events, corrections: value.corrections).sessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.status == .confirmed })
        XCTAssertEqual(sessions.filter { $0.source == .manual }.count, 1)
    }

    func testOverlappingManualRecordIsRejectedAtomically() throws {
        var value = state()
        value.events = [event(.start, 0), event(.end, 3_600)]
        let before = value
        XCTAssertThrowsError(try TrackerEngine.addManualSession(state: &value, deviceID: device, start: time(3_000), end: time(4_000), tag: nil, note: nil, id: UUID()))
        XCTAssertEqual(value, before)
    }

    func testImportedOverlapBlocksBothUntilOneExcluded() {
        let a = event(.start, 0), b = event(.end, 3_600), manual = UUID()
        let c = ConnectionEvent(deviceID: device, kind: .start, observedAt: time(2_000), source: .manual, manualSessionID: manual)
        let d = ConnectionEvent(deviceID: device, kind: .end, observedAt: time(4_000), source: .manual, manualSessionID: manual)
        XCTAssertTrue(reduce([a, b, c, d]).sessions.allSatisfy { $0.status == .needsReview })
        let exclusion = SessionCorrection(id: manual, anchorEventIDs: [c.id, d.id], deviceID: device, excluded: true)
        let resolved = reduce([a, b, c, d], corrections: [exclusion]).sessions
        XCTAssertEqual(resolved.first { $0.id == a.id }?.status, .confirmed)
        XCTAssertEqual(resolved.first { $0.id == manual }?.status, .excluded)
    }

    func testDurationUnionClipsOverlapsAndDoesNotCountTouchingBoundaryTwice() {
        let spans = [(0.0, 2_000.0), (1_000.0, 3_000.0), (3_000.0, 4_000.0)].map { a, b in
            UsageSession(id: UUID(), deviceID: device, start: time(a), end: time(b), status: .confirmed, source: .manual, anchorEventIDs: [])
        }
        XCTAssertEqual(IntervalMath.confirmedDuration(sessions: spans, in: DateInterval(start: time(500), end: time(3_500))), 3_000)
    }

    func testCalendarDayBucketsRespectDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let session = UsageSession(id: UUID(), deviceID: device, start: start, end: end, status: .confirmed, source: .manual, anchorEventIDs: [])
        let days = IntervalMath.dailyDurations(sessions: [session], in: DateInterval(start: start, end: end), calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].duration, 23 * 3_600)
    }

    func testConnectionIDRetryIgnoresSaveTimeButRejectsChangedContent() throws {
        var value = state(); let id = UUID()
        try TrackerEngine.recordConnection(state: &value, deviceID: device, kind: .start, at: epoch, id: id)
        try TrackerEngine.recordConnection(state: &value, deviceID: device, kind: .start, at: epoch, id: id)
        XCTAssertEqual(value.events.count, 1)
        XCTAssertThrowsError(try TrackerEngine.recordConnection(state: &value, deviceID: device, kind: .end, at: epoch, id: id))
        XCTAssertEqual(value.events[0].kind, .start)
    }

    func testBatteryUnknownDiffersFromZeroAndInvalidValueIsNotClamped() throws {
        var value = state()
        try TrackerEngine.saveBattery(state: &value, snapshot: BatterySnapshot(deviceID: device, caseLevel: 0, importedAt: epoch))
        XCTAssertNil(value.batteries[0].left)
        XCTAssertNil(value.batteries[0].measuredAt)
        XCTAssertEqual(value.batteries[0].caseLevel, 0)
        XCTAssertThrowsError(try TrackerEngine.saveBattery(state: &value, snapshot: BatterySnapshot(deviceID: device, left: 101)))
        XCTAssertThrowsError(try TrackerEngine.saveBattery(state: &value, snapshot: BatterySnapshot(deviceID: device, left: 50, userConfirmed: false)))
        XCTAssertEqual(value.batteries.count, 1)
    }

    func testFullChargeWritesOnlyCaseAndDuplicateRequestDoesNotCreateAgain() throws {
        var value = state(); let request = UUID()
        let first = try TrackerEngine.charge(state: &value, deviceID: device, action: .startFull, at: epoch, reason: nil, requestID: request)
        let second = try TrackerEngine.charge(state: &value, deviceID: device, action: .startFull, at: epoch, reason: nil, requestID: request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(value.observations.count, 1)
        XCTAssertEqual(value.batteries[0].caseLevel, 100)
        XCTAssertNil(value.batteries[0].left)
        XCTAssertNil(value.batteries[0].right)
    }

    func testTopUpIsAtomicAndUndoRestoresOldObservation() throws {
        var value = state()
        let old = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: UUID())
        let before = value
        XCTAssertThrowsError(try TrackerEngine.charge(state: &value, deviceID: device, action: .topUpAndRestart, at: time(-1), reason: nil, requestID: UUID()))
        XCTAssertEqual(value, before)
        let request = UUID()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .topUpAndRestart, at: time(3_600), reason: nil, requestID: request)
        XCTAssertEqual(value.observations.count, 2)
        XCTAssertEqual(value.observations.first { $0.id == old }?.endAt, time(3_600))
        try TrackerEngine.undoCharge(state: &value, requestID: request)
        XCTAssertEqual(value.observations, before.observations)
        XCTAssertEqual(value.receipts.last?.status, .undone)
        XCTAssertThrowsError(try TrackerEngine.charge(state: &value, deviceID: device, action: .topUpAndRestart, at: time(3_600), reason: nil, requestID: request))
    }

    func testExplicitFullRestartWritesCaseOnlyAndUndoRemovesItsSnapshot() throws {
        var value = state()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: UUID())
        let request = UUID()
        let observationID = try TrackerEngine.charge(state: &value, deviceID: device, action: .topUpAndRestart, at: time(600), reason: nil, requestID: request, fullOnRestart: true)
        let observation = value.observations.first { $0.id == observationID }!
        XCTAssertEqual(observation.startSnapshotID, value.batteries.first?.id)
        XCTAssertEqual(value.batteries.first?.caseLevel, 100)
        XCTAssertNil(value.batteries.first?.left)
        XCTAssertNil(value.batteries.first?.right)
        XCTAssertThrowsError(try TrackerEngine.charge(state: &value, deviceID: device, action: .topUpAndRestart, at: time(600), reason: nil, requestID: request, fullOnRestart: false))
        try TrackerEngine.undoCharge(state: &value, requestID: request)
        XCTAssertTrue(value.batteries.isEmpty)
        XCTAssertEqual(value.observations.count, 1)
        XCTAssertNil(value.observations[0].endAt)
    }

    func testEndEmptyCaseWritesZeroWithoutInventingEarbudLevels() throws {
        var value = state()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: UUID())
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .end, at: time(600), reason: "盒子没电", requestID: UUID())
        XCTAssertEqual(value.batteries.first?.caseLevel, 0)
        XCTAssertNil(value.batteries.first?.left)
        XCTAssertEqual(value.observations.first?.endSnapshotID, value.batteries.first?.id)
    }

    func testUndoRefusesRevisionChangeAndEarlierActions() throws {
        var value = state(); let first = UUID(), second = UUID()
        let id = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: first)
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .end, at: time(1_000), reason: "提前结束", requestID: second)
        XCTAssertThrowsError(try TrackerEngine.undoCharge(state: &value, requestID: first))
        var edited = value.observations.first { $0.id == id }!
        edited.note = "重新核对"
        try TrackerEngine.updateObservation(state: &value, observation: edited, expectedRevision: edited.revision)
        XCTAssertThrowsError(try TrackerEngine.undoCharge(state: &value, requestID: second))
    }

    func testDeletedReceiptSurvivesBackupWithoutObservationAndPreventsRecreation() throws {
        var value = state(); let request = UUID()
        let id = try TrackerEngine.charge(state: &value, deviceID: device, action: .startFull, at: epoch, reason: nil, requestID: request)
        try TrackerEngine.deleteObservation(state: &value, id: id)
        try TrackerEngine.validate(value)
        XCTAssertEqual(value.batteries.count, 1)
        XCTAssertEqual(value.receipts[0].status, .deleted)
        let decoded = try JSONDecoder().decode(TrackerState.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(try TrackerEngine.merge(local: state(), incoming: decoded), decoded)
        XCTAssertThrowsError(try TrackerEngine.charge(state: &value, deviceID: device, action: .startFull, at: epoch, reason: nil, requestID: request))
    }

    func testSplitExcludesOriginalAndCreatesTwoIndependentManualSegments() throws {
        var value = state(); let a = event(.start, 0), b = event(.end, 3_600)
        value.events = [a, b]
        try TrackerEngine.splitSession(state: &value, sessionID: a.id, at: time(1_800), asOf: time(4_000))
        let result = reduce(value.events, corrections: value.corrections)
        XCTAssertEqual(result.sessions.count, 3)
        XCTAssertEqual(result.sessions.first { $0.id == a.id }?.status, .excluded)
        XCTAssertEqual(result.sessions.filter { $0.status == .confirmed }.count, 2)
        XCTAssertEqual(IntervalMath.confirmedDuration(sessions: result.sessions, in: DateInterval(start: time(0), end: time(4_000))), 3_600)
    }

    func testMergeRetainsLocalConflictAndRejectsDanglingReferences() throws {
        let local = state(); var incoming = local
        incoming.devices[0].name = "备份名字"
        XCTAssertEqual(try TrackerEngine.merge(local: local, incoming: incoming).devices[0].name, "耳机")
        incoming.events = [ConnectionEvent(deviceID: UUID(), kind: .start, observedAt: epoch)]
        XCTAssertThrowsError(try TrackerEngine.merge(local: local, incoming: incoming))
    }

    func testOldBackupCannotResurrectLocallyUndoneCreation() throws {
        var value = state(); let request = UUID()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: request)
        let oldBackup = value
        try TrackerEngine.undoCharge(state: &value, requestID: request)
        let merged = try TrackerEngine.merge(local: value, incoming: oldBackup)
        XCTAssertTrue(merged.observations.isEmpty)
        XCTAssertEqual(merged.receipts[0].status, .undone)
    }

    func testOldBackupCannotRestoreFullBatterySnapshotRemovedByUndo() throws {
        var value = state(); let request = UUID()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .startFull, at: epoch, reason: nil, requestID: request)
        let oldBackup = value
        let snapshotID = try XCTUnwrap(value.batteries.first?.id)
        try TrackerEngine.undoCharge(state: &value, requestID: request)
        XCTAssertEqual(value.receipts[0].removedSnapshotIDs, [snapshotID])
        XCTAssertNil(value.receipts[0].undoState)
        let restoredLocal = try JSONDecoder().decode(TrackerState.self, from: JSONEncoder().encode(value))
        let merged = try TrackerEngine.merge(local: restoredLocal, incoming: oldBackup)
        XCTAssertTrue(merged.batteries.isEmpty)
        XCTAssertTrue(merged.observations.isEmpty)
        try TrackerEngine.validate(merged)
    }

    func testOldBackupCannotRestoreEmptyBatterySnapshotAfterEndUndo() throws {
        var value = state()
        let observationID = try TrackerEngine.charge(state: &value, deviceID: device, action: .startNow, at: epoch, reason: nil, requestID: UUID())
        let request = UUID()
        _ = try TrackerEngine.charge(state: &value, deviceID: device, action: .end, at: time(600), reason: "盒子没电", requestID: request)
        let oldBackup = value
        let snapshotID = try XCTUnwrap(value.batteries.first?.id)
        try TrackerEngine.undoCharge(state: &value, requestID: request)
        XCTAssertEqual(value.receipts.last?.removedSnapshotIDs, [snapshotID])
        let merged = try TrackerEngine.merge(local: value, incoming: oldBackup)
        XCTAssertTrue(merged.batteries.isEmpty)
        let observation = try XCTUnwrap(merged.observations.first { $0.id == observationID })
        XCTAssertNil(observation.endAt)
        XCTAssertNil(observation.endSnapshotID)
        try TrackerEngine.validate(merged)
    }

    func testObservationBoundarySplitsOnlyDurationAndAssignsReviewByKnownEndpoint() {
        let sessions = reduce([event(.start, 0), event(.end, 3_600), event(.start, 4_000), event(.start, 5_000)], now: 6_000).sessions
        let first = ChargeObservation(deviceID: device, startAt: time(0), endAt: time(1_800), startReason: "从现在观察", endReason: "补电")
        let second = ChargeObservation(deviceID: device, startAt: time(1_800), endAt: time(6_000), startReason: "补电后重新观察", endReason: "提前结束")
        let a = IntervalMath.observationSummary(observation: first, sessions: sessions, batteries: [], asOf: time(6_000))
        let b = IntervalMath.observationSummary(observation: second, sessions: sessions, batteries: [], asOf: time(6_000))
        XCTAssertEqual(a.confirmedDuration, 1_800)
        XCTAssertEqual(b.confirmedDuration, 1_800)
        XCTAssertEqual(a.needsReviewCount, 0)
        XCTAssertEqual(b.needsReviewCount, 1)
        XCTAssertEqual(sessions.filter { $0.status == .confirmed }.count, 1)
    }

    func testCSVLeavesUnknownDurationBlankAndQuotesUserText() {
        let session = UsageSession(id: UUID(), deviceID: device, start: epoch, end: nil, status: .awaitingEnd, source: .shortcut, anchorEventIDs: [], tag: "=1+1", note: "逗号,引号\"换行\n结束")
        let csv = CSVExporter.sessions([session], timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(csv.contains("\"等待断开\",\"\",\"'=1+1\""))
        XCTAssertTrue(csv.contains("逗号,引号\"\"换行\n结束"))
    }
}
