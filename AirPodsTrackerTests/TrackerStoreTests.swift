import XCTest
import SwiftData
import TrackerCore
@testable import AirPodsTracker

@MainActor
final class TrackerStoreTests: XCTestCase {
    func testExcludeAfterLateEndUsesCurrentAnchors() throws {
        let store = TrackerStore(persistence: try TrackerPersistence(inMemory: true), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try store.addDevice(name: "耳机", model: nil)
        try store.recordConnection(kind: .start, at: Date().addingTimeInterval(-600))
        try store.setExcluded(XCTUnwrap(store.sessions.first), excluded: true)
        try store.recordConnection(kind: .end)
        let changed = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(changed.status, .needsReview)
        try store.setExcluded(changed, excluded: true)
        XCTAssertEqual(store.sessions.first?.status, .excluded)
        XCTAssertTrue(store.reduction.unresolvedCorrections.isEmpty)
    }

    func testSavedEventsSurviveNewStoreInstance() throws {
        let persistence = try TrackerPersistence(inMemory: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TrackerStore(persistence: persistence, defaults: defaults)
        try store.addDevice(name: "测试耳机", model: nil)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try store.recordConnection(kind: .start, at: start)
        try store.recordConnection(kind: .end, at: start.addingTimeInterval(600))
        let reopened = TrackerStore(persistence: persistence, defaults: defaults)
        XCTAssertEqual(reopened.state.events.count, 2)
        XCTAssertEqual(reopened.sessions.filter { $0.status == .confirmed }.count, 1)
    }

    func testInvalidBatteryDoesNotChangePublishedOrPersistedState() throws {
        let persistence = try TrackerPersistence(inMemory: true)
        let store = TrackerStore(persistence: persistence, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try store.addDevice(name: "耳机", model: nil)
        let before = store.state
        XCTAssertThrowsError(try store.recordBattery(left: 101, right: nil, caseLevel: nil, measuredAt: nil, source: .manual))
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(try persistence.load(), before)
    }

    func testMalformedBackupDoesNotEraseExistingData() throws {
        let persistence = try TrackerPersistence(inMemory: true)
        let store = TrackerStore(persistence: persistence, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try store.addDevice(name: "保留", model: nil)
        let before = store.state
        XCTAssertThrowsError(try store.importBackup(data: Data("not json".utf8)))
        XCTAssertEqual(store.state, before)
        XCTAssertEqual(try persistence.load(), before)
    }
}
