import Foundation

/// Where characters are kept between launches.
///
/// Changes are saved one character at a time, never as a whole list, so a character
/// synced from another device that hasn't been loaded yet is never deleted by mistake.
@MainActor
public protocol CharacterStore: AnyObject {
    /// Every saved character, oldest first.
    func loadCharacters() throws -> [PlayerCharacter]
    /// Adds the character, or replaces the saved one with the same id.
    func save(_ character: PlayerCharacter) throws
    func delete(id: PlayerCharacter.ID) throws
}

/// Keeps characters in memory only. For previews and tests.
@MainActor
public final class InMemoryCharacterStore: CharacterStore {
    public private(set) var characters: [PlayerCharacter]
    /// When set, every call throws this error.
    public var failure: Error?

    public init(characters: [PlayerCharacter] = []) {
        self.characters = characters
    }

    public func loadCharacters() throws -> [PlayerCharacter] {
        if let failure { throw failure }
        return characters
    }

    public func save(_ character: PlayerCharacter) throws {
        if let failure { throw failure }
        if let index = characters.firstIndex(where: { $0.id == character.id }) {
            characters[index] = character
        } else {
            characters.append(character)
        }
    }

    public func delete(id: PlayerCharacter.ID) throws {
        if let failure { throw failure }
        characters.removeAll { $0.id == id }
    }
}

/// Turns characters into the JSON that stores keep, and back.
public enum CharacterCoding {
    public static func encode(_ character: PlayerCharacter) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(character)
    }

    public static func decode(_ data: Data) throws -> PlayerCharacter {
        try JSONDecoder().decode(PlayerCharacter.self, from: data)
    }
}
