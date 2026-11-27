import Foundation

/// A player character owned by the signed-in user.
public struct PlayerCharacter: Identifiable, Hashable, Codable, Sendable {
    public static let levelRange = 1...20

    public let id: UUID
    public var name: String
    public var race: String
    public var characterClass: String
    public var level: Int

    public init(id: UUID = UUID(), name: String, race: String, characterClass: String, level: Int = 1) {
        self.id = id
        self.name = name
        self.race = race
        self.characterClass = characterClass
        self.level = level
    }

    /// e.g. "Level 3 Elf Wizard"
    public var summary: String {
        let parts = [race, characterClass].filter { !$0.isEmpty }
        return (["Level \(level)"] + parts).joined(separator: " ")
    }
}

public enum CharacterError: Error, Equatable, Sendable {
    case emptyName
    case levelOutOfRange
}

/// The user's list of characters plus the rules for adding and removing them.
public struct CharacterRoster: Equatable, Sendable {
    public private(set) var characters: [PlayerCharacter]

    public init(characters: [PlayerCharacter] = []) {
        self.characters = characters
    }

    @discardableResult
    public mutating func add(name: String, race: String, characterClass: String, level: Int) throws -> PlayerCharacter {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CharacterError.emptyName }
        guard PlayerCharacter.levelRange.contains(level) else { throw CharacterError.levelOutOfRange }
        let character = PlayerCharacter(
            name: trimmedName,
            race: race.trimmingCharacters(in: .whitespacesAndNewlines),
            characterClass: characterClass.trimmingCharacters(in: .whitespacesAndNewlines),
            level: level
        )
        characters.append(character)
        return character
    }

    public mutating func remove(id: PlayerCharacter.ID) {
        characters.removeAll { $0.id == id }
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where characters.indices.contains(index) {
            characters.remove(at: index)
        }
    }
}
