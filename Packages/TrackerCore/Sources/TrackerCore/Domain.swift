import Foundation

public enum EventKind: String, Codable, Hashable, Sendable, CaseIterable { case start, end }
public enum EventSource: String, Codable, Hashable, Sendable { case shortcut, manual }
public enum SessionStatus: String, Codable, Hashable, Sendable { case confirmed, awaitingEnd, needsReview, excluded }
public enum BatterySource: String, Codable, Hashable, Sendable, CaseIterable { case manual, screenshot, companion }
public enum ChargeAction: String, Codable, Hashable, Sendable, CaseIterable { case startFull, startNow, topUpAndRestart, end }
public enum ReceiptStatus: String, Codable, Hashable, Sendable { case applied, undone, deleted }

public struct TrackedDevice: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var model: String?
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, model: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.model = model; self.createdAt = createdAt
    }
}

public struct ConnectionEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceID: UUID
    public var kind: EventKind
    public var observedAt: Date
    public var savedAt: Date
    public var source: EventSource
    public var manualSessionID: UUID?
    public var timeZoneID: String
    public init(id: UUID = UUID(), deviceID: UUID, kind: EventKind, observedAt: Date, savedAt: Date = Date(), source: EventSource = .shortcut, manualSessionID: UUID? = nil, timeZoneID: String = TimeZone.current.identifier) {
        self.id = id; self.deviceID = deviceID; self.kind = kind; self.observedAt = observedAt; self.savedAt = savedAt; self.source = source; self.manualSessionID = manualSessionID; self.timeZoneID = timeZoneID
    }
}

public struct SessionCorrection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var anchorEventIDs: [UUID]
    public var deviceID: UUID
    public var startOverride: Date?
    public var endOverride: Date?
    public var excluded: Bool
    public var longSpanConfirmed: Bool
    public var tag: String?
    public var note: String?
    public var updatedAt: Date
    public init(id: UUID, anchorEventIDs: [UUID], deviceID: UUID, startOverride: Date? = nil, endOverride: Date? = nil, excluded: Bool = false, longSpanConfirmed: Bool = false, tag: String? = nil, note: String? = nil, updatedAt: Date = Date()) {
        self.id = id; self.anchorEventIDs = anchorEventIDs; self.deviceID = deviceID; self.startOverride = startOverride; self.endOverride = endOverride; self.excluded = excluded; self.longSpanConfirmed = longSpanConfirmed; self.tag = tag; self.note = note; self.updatedAt = updatedAt
    }
}

public struct UsageSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceID: UUID
    public var start: Date?
    public var end: Date?
    public var status: SessionStatus
    public var source: EventSource
    public var anchorEventIDs: [UUID]
    public var tag: String?
    public var note: String?
    public var issue: String?
    public init(id: UUID, deviceID: UUID, start: Date?, end: Date?, status: SessionStatus, source: EventSource, anchorEventIDs: [UUID], tag: String? = nil, note: String? = nil, issue: String? = nil) {
        self.id = id; self.deviceID = deviceID; self.start = start; self.end = end; self.status = status; self.source = source; self.anchorEventIDs = anchorEventIDs; self.tag = tag; self.note = note; self.issue = issue
    }
}

public struct SessionReduction: Equatable, Sendable {
    public var sessions: [UsageSession]
    public var unresolvedCorrections: [SessionCorrection]
    public init(sessions: [UsageSession], unresolvedCorrections: [SessionCorrection] = []) { self.sessions = sessions; self.unresolvedCorrections = unresolvedCorrections }
}

public struct BatterySnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceID: UUID
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var measuredAt: Date?
    public var importedAt: Date
    public var source: BatterySource
    public var userConfirmed: Bool
    public init(id: UUID = UUID(), deviceID: UUID, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, measuredAt: Date? = nil, importedAt: Date = Date(), source: BatterySource = .manual, userConfirmed: Bool = true) {
        self.id = id; self.deviceID = deviceID; self.left = left; self.right = right; self.caseLevel = caseLevel; self.measuredAt = measuredAt; self.importedAt = importedAt; self.source = source; self.userConfirmed = userConfirmed
    }
}

public struct ChargeObservation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceID: UUID
    public var startAt: Date
    public var endAt: Date?
    public var startReason: String
    public var endReason: String?
    public var startSnapshotID: UUID?
    public var endSnapshotID: UUID?
    public var note: String?
    public var revision: Int
    public init(id: UUID = UUID(), deviceID: UUID, startAt: Date, endAt: Date? = nil, startReason: String, endReason: String? = nil, startSnapshotID: UUID? = nil, endSnapshotID: UUID? = nil, note: String? = nil, revision: Int = 1) {
        self.id = id; self.deviceID = deviceID; self.startAt = startAt; self.endAt = endAt; self.startReason = startReason; self.endReason = endReason; self.startSnapshotID = startSnapshotID; self.endSnapshotID = endSnapshotID; self.note = note; self.revision = revision
    }
}

public struct ChargeRequest: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var action: ChargeAction
    public var at: Date
    public var reason: String?
    public var fullOnRestart: Bool
    public init(deviceID: UUID, action: ChargeAction, at: Date, reason: String?, fullOnRestart: Bool = false) { self.deviceID = deviceID; self.action = action; self.at = at; self.reason = reason; self.fullOnRestart = fullOnRestart }
}

public struct ChargeUndoState: Codable, Equatable, Sendable {
    public var previousObservations: [ChargeObservation]
    public var createdObservationIDs: [UUID]
    public var createdSnapshotIDs: [UUID]
    public var expectedRevisions: [UUID: Int]
    public init(previousObservations: [ChargeObservation], createdObservationIDs: [UUID], createdSnapshotIDs: [UUID], expectedRevisions: [UUID: Int]) {
        self.previousObservations = previousObservations; self.createdObservationIDs = createdObservationIDs; self.createdSnapshotIDs = createdSnapshotIDs; self.expectedRevisions = expectedRevisions
    }
}

public struct ChargeActionReceipt: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceID: UUID
    public var observationID: UUID
    public var requestInput: ChargeRequest
    public var savedAt: Date
    public var status: ReceiptStatus
    public var undoState: ChargeUndoState?
    public var removedSnapshotIDs: [UUID]
    public init(id: UUID, deviceID: UUID, observationID: UUID, requestInput: ChargeRequest, savedAt: Date, status: ReceiptStatus = .applied, undoState: ChargeUndoState? = nil, removedSnapshotIDs: [UUID] = []) {
        self.id = id; self.deviceID = deviceID; self.observationID = observationID; self.requestInput = requestInput; self.savedAt = savedAt; self.status = status; self.undoState = undoState; self.removedSnapshotIDs = removedSnapshotIDs
    }
    private enum CodingKeys: String, CodingKey { case id, deviceID, observationID, requestInput, savedAt, status, undoState, removedSnapshotIDs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        deviceID = try values.decode(UUID.self, forKey: .deviceID)
        observationID = try values.decode(UUID.self, forKey: .observationID)
        requestInput = try values.decode(ChargeRequest.self, forKey: .requestInput)
        savedAt = try values.decode(Date.self, forKey: .savedAt)
        status = try values.decode(ReceiptStatus.self, forKey: .status)
        undoState = try values.decodeIfPresent(ChargeUndoState.self, forKey: .undoState)
        removedSnapshotIDs = try values.decodeIfPresent([UUID].self, forKey: .removedSnapshotIDs) ?? []
    }
}

public struct TrackerState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var devices: [TrackedDevice]
    public var events: [ConnectionEvent]
    public var corrections: [SessionCorrection]
    public var batteries: [BatterySnapshot]
    public var observations: [ChargeObservation]
    public var receipts: [ChargeActionReceipt]
    public init(schemaVersion: Int = 1, devices: [TrackedDevice] = [], events: [ConnectionEvent] = [], corrections: [SessionCorrection] = [], batteries: [BatterySnapshot] = [], observations: [ChargeObservation] = [], receipts: [ChargeActionReceipt] = []) {
        self.schemaVersion = schemaVersion; self.devices = devices; self.events = events; self.corrections = corrections; self.batteries = batteries; self.observations = observations; self.receipts = receipts
    }
}

public struct TrackerError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
