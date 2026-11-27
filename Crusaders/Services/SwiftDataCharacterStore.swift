import Foundation
import SwiftData
import CrusadersKit

/// One saved character. The character itself is stored as JSON, so new character fields
/// never need a database migration.
///
/// Every property has a default and nothing is unique, as CloudKit sync requires.
@Model
final class StoredCharacter {
    var characterID: UUID = UUID()
    var payload: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(characterID: UUID, payload: Data, createdAt: Date = Date()) {
        self.characterID = characterID
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

/// Keeps characters in SwiftData. With iCloud on, SwiftData mirrors them to the user's
/// private CloudKit database, so they sync to every device signed in to the same Apple ID.
@MainActor
final class SwiftDataCharacterStore: CharacterStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func loadCharacters() throws -> [PlayerCharacter] {
        let descriptor = FetchDescriptor<StoredCharacter>(sortBy: [SortDescriptor(\.createdAt)])
        let records = try context.fetch(descriptor)
        // Two devices can create a record for the same character before they sync. Keep the newest.
        var newest: [UUID: StoredCharacter] = [:]
        for record in records {
            if let existing = newest[record.characterID], existing.updatedAt >= record.updatedAt { continue }
            newest[record.characterID] = record
        }
        var seen = Set<UUID>()
        var characters: [PlayerCharacter] = []
        for record in records where !seen.contains(record.characterID) {
            seen.insert(record.characterID)
            guard let chosen = newest[record.characterID],
                  let character = try? CharacterCoding.decode(chosen.payload) else { continue }
            characters.append(character)
        }
        return characters
    }

    func save(_ character: PlayerCharacter) throws {
        let payload = try CharacterCoding.encode(character)
        let records = try records(for: character.id)
        if records.isEmpty {
            context.insert(StoredCharacter(characterID: character.id, payload: payload))
        } else {
            for record in records where record.payload != payload {
                record.payload = payload
                record.updatedAt = Date()
            }
        }
        try context.save()
    }

    func delete(id: PlayerCharacter.ID) throws {
        for record in try records(for: id) {
            context.delete(record)
        }
        try context.save()
    }

    private func records(for id: UUID) throws -> [StoredCharacter] {
        let descriptor = FetchDescriptor<StoredCharacter>(predicate: #Predicate { $0.characterID == id })
        return try context.fetch(descriptor)
    }
}

/// Picks where characters are saved when the app starts.
@MainActor
enum CharacterPersistence {
    /// How characters are being kept, for the note on the Characters screen.
    enum Mode: Equatable {
        /// Saved on this device and synced through iCloud.
        case iCloud
        /// Saved on this device only, because iCloud isn't set up for this build yet.
        case device
        /// Not saved at all, for UI tests or when the database couldn't open.
        case memory(reason: String?)
    }

    struct Setup {
        let store: CharacterStore
        let mode: Mode
    }

    /// Launch argument that keeps characters in memory, for UI tests.
    static let inMemoryArgument = "-inMemoryCharacters"
    /// Launch argument that deletes saved characters on start, for UI tests.
    static let resetArgument = "-resetCharacters"

    static func makeDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        cloudKitEnabled: Bool = ItemLibrary.cloudKitEnabledInBuild
    ) -> Setup {
        if arguments.contains(inMemoryArgument), let setup = try? inMemory(reason: nil) {
            return setup
        }
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        // Debug builds only touch CloudKit when asked, same rule as the item library.
        let useCloudKit = cloudKitEnabled && (!isDebug || arguments.contains("-useCloudKit"))
        let setups: [() throws -> Setup] = [
            { try onDisk(cloudKit: useCloudKit) },
            { try onDisk(cloudKit: false) },
            { try inMemory(reason: "Characters couldn't be saved on this device. They'll be lost when the app closes.") }
        ]
        for makeSetup in (useCloudKit ? setups : Array(setups.dropFirst())) {
            if let setup = try? makeSetup() {
                if arguments.contains(resetArgument) { reset(setup.store) }
                return setup
            }
        }
        fatalError("Couldn't create even an in-memory character store")
    }

    static func onDisk(cloudKit: Bool) throws -> Setup {
        let configuration = ModelConfiguration(
            "Characters",
            schema: Schema([StoredCharacter.self]),
            cloudKitDatabase: cloudKit ? ModelConfiguration.CloudKitDatabase.private(CloudConfig.containerID) : ModelConfiguration.CloudKitDatabase.none
        )
        let container = try ModelContainer(for: StoredCharacter.self, configurations: configuration)
        return Setup(store: SwiftDataCharacterStore(container: container), mode: cloudKit ? .iCloud : .device)
    }

    static func inMemory(reason: String?) throws -> Setup {
        let configuration = ModelConfiguration("CharactersInMemory-\(UUID().uuidString)", isStoredInMemoryOnly: true, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        let container = try ModelContainer(for: StoredCharacter.self, configurations: configuration)
        return Setup(store: SwiftDataCharacterStore(container: container), mode: .memory(reason: reason))
    }

    private static func reset(_ store: CharacterStore) {
        for character in (try? store.loadCharacters()) ?? [] {
            try? store.delete(id: character.id)
        }
    }
}
