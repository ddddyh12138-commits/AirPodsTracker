import Foundation
import SwiftData
import TrackerCore

/// One versioned document makes related edits atomic; domain models remain testable without iOS.
@Model
final class TrackerDocument {
    @Attribute(.unique) var id: String
    var payload: Data
    var modifiedAt: Date

    init(payload: Data) {
        id = "local"
        self.payload = payload
        modifiedAt = Date()
    }
}

@MainActor
final class TrackerPersistence {
    let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) throws {
        let schema = Schema([TrackerDocument.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
                .appendingPathComponent("AirPodsTracker", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration("AirPodsTracker", schema: schema,
                                               url: directory.appendingPathComponent("tracker.store"), cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws -> TrackerState {
        let documents = try context.fetch(FetchDescriptor<TrackerDocument>())
        guard documents.count <= 1 else { throw TrackerError("发现重复的数据文件，请先保留备份再处理。") }
        guard let document = documents.first else { return TrackerState() }
        let state = try JSONDecoder().decode(TrackerState.self, from: document.payload)
        try TrackerEngine.validate(state)
        return state
    }

    func save(_ state: TrackerState) throws {
        try TrackerEngine.validate(state)
        let data = try JSONEncoder().encode(state)
        do {
            let documents = try context.fetch(FetchDescriptor<TrackerDocument>())
            guard documents.count <= 1 else { throw TrackerError("数据文件状态异常，未覆盖现有数据。") }
            if let document = documents.first {
                document.payload = data
                document.modifiedAt = Date()
            } else {
                context.insert(TrackerDocument(payload: data))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
