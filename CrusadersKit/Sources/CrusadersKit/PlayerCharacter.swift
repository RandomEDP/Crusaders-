import Foundation

/// A player character owned by the signed-in user.
public struct PlayerCharacter: Identifiable, Hashable, Codable, Sendable {
    public static let levelRange = 1...20

    public let id: UUID
    public var name: String
    /// Display name of the race, e.g. "Hill Dwarf".
    public var race: String
    /// Display name of the class, e.g. "Wizard".
    public var characterClass: String
    public var level: Int

    /// SRD ids. Nil for characters made before the character builder existed.
    public var raceID: String?
    public var subraceID: String?
    public var classID: String?
    /// Scores before racial bonuses and level-up improvements.
    public var baseAbilityScores: AbilityScores
    /// Abilities picked for a race's "choose your bonus" rule (Half-Elf).
    public var racialBonusChoices: [Ability]
    /// Points spent from Ability Score Improvements, one entry per point.
    public var improvementPoints: [Ability]
    public var skillProficiencies: Set<Skill>
    public var experiencePoints: Int
    /// Spells the character knows or has prepared.
    public var spellIDs: Set<String>
    /// Whether hit points use the fixed value per level or rolled hit dice.
    public var hitPointMethod: HitPointMethod
    /// Hit die rolls for levels 2, 3, 4… when `hitPointMethod` is `.rolled`. Level 1 always takes the full die.
    public var hitPointRolls: [Int]

    public init(
        id: UUID = UUID(),
        name: String,
        race: String,
        characterClass: String,
        level: Int = 1,
        raceID: String? = nil,
        subraceID: String? = nil,
        classID: String? = nil,
        baseAbilityScores: AbilityScores = AbilityScores(),
        racialBonusChoices: [Ability] = [],
        improvementPoints: [Ability] = [],
        skillProficiencies: Set<Skill> = [],
        experiencePoints: Int? = nil,
        spellIDs: Set<String> = [],
        hitPointMethod: HitPointMethod = .fixed,
        hitPointRolls: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.race = race
        self.characterClass = characterClass
        self.level = level
        self.raceID = raceID
        self.subraceID = subraceID
        self.classID = classID
        self.baseAbilityScores = baseAbilityScores
        self.racialBonusChoices = racialBonusChoices
        self.improvementPoints = improvementPoints
        self.skillProficiencies = skillProficiencies
        self.experiencePoints = experiencePoints ?? Experience.minimumXP(forLevel: level)
        self.spellIDs = spellIDs
        self.hitPointMethod = hitPointMethod
        self.hitPointRolls = hitPointRolls
    }

    enum CodingKeys: String, CodingKey {
        case id, name, race, characterClass, level
        case raceID, subraceID, classID, baseAbilityScores, racialBonusChoices
        case improvementPoints, skillProficiencies, experiencePoints, spellIDs
        case hitPointMethod, hitPointRolls
    }

    /// Reads saved characters. Anything missing gets a default, so characters saved by
    /// older versions of the app still load after new fields are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            race: try container.decodeIfPresent(String.self, forKey: .race) ?? "",
            characterClass: try container.decodeIfPresent(String.self, forKey: .characterClass) ?? "",
            level: min(max(level, PlayerCharacter.levelRange.lowerBound), PlayerCharacter.levelRange.upperBound),
            raceID: try container.decodeIfPresent(String.self, forKey: .raceID),
            subraceID: try container.decodeIfPresent(String.self, forKey: .subraceID),
            classID: try container.decodeIfPresent(String.self, forKey: .classID),
            baseAbilityScores: try container.decodeIfPresent(AbilityScores.self, forKey: .baseAbilityScores) ?? AbilityScores(),
            racialBonusChoices: try container.decodeIfPresent([Ability].self, forKey: .racialBonusChoices) ?? [],
            improvementPoints: try container.decodeIfPresent([Ability].self, forKey: .improvementPoints) ?? [],
            skillProficiencies: try container.decodeIfPresent(Set<Skill>.self, forKey: .skillProficiencies) ?? [],
            experiencePoints: try container.decodeIfPresent(Int.self, forKey: .experiencePoints),
            spellIDs: try container.decodeIfPresent(Set<String>.self, forKey: .spellIDs) ?? [],
            hitPointMethod: try container.decodeIfPresent(HitPointMethod.self, forKey: .hitPointMethod) ?? .fixed,
            hitPointRolls: try container.decodeIfPresent([Int].self, forKey: .hitPointRolls) ?? []
        )
    }

    /// e.g. "Level 3 Elf Wizard"
    public var summary: String {
        let parts = [race, characterClass].filter { !$0.isEmpty }
        return (["Level \(level)"] + parts).joined(separator: " ")
    }

    /// Adds XP and raises the level to match. Returns the levels gained, or nil if none.
    @discardableResult
    public mutating func addExperience(_ amount: Int) throws -> ClosedRange<Int>? {
        guard amount > 0 else { throw CharacterError.invalidExperience }
        experiencePoints += amount
        let newLevel = max(level, Experience.level(forXP: experiencePoints))
        guard newLevel > level else { return nil }
        let gained = (level + 1)...newLevel
        level = newLevel
        return gained
    }

    /// With rolled hit points, rolls the hit die for any level that doesn't have a roll yet.
    /// Returns the new rolls, oldest level first.
    @discardableResult
    public mutating func rollMissingHitPoints(hitDie: Int, roller: DiceRoller = .random) -> [Int] {
        guard hitPointMethod == .rolled else { return [] }
        var added: [Int] = []
        while hitPointRolls.count < level - 1 {
            let roll = roller.roll(hitDie)
            hitPointRolls.append(roll)
            added.append(roll)
        }
        return added
    }

    /// Spends one Ability Score Improvement point. Abilities can't go above 20.
    public mutating func spendImprovementPoint(on ability: Ability, catalog: RulesCatalog = .srd) throws {
        let sheet = CharacterSheet(character: self, catalog: catalog)
        guard sheet.unspentImprovementPoints > 0 else { throw CharacterError.noImprovementPoints }
        guard sheet.abilityScores[ability] < AbilityScores.maximum else { throw CharacterError.abilityAtMaximum }
        improvementPoints.append(ability)
    }

    /// Learns the spell if unknown, forgets it if known.
    public mutating func toggleSpell(_ spellID: String) {
        if spellIDs.contains(spellID) {
            spellIDs.remove(spellID)
        } else {
            spellIDs.insert(spellID)
        }
    }
}

public enum CharacterError: Error, Equatable, Sendable {
    case emptyName
    case levelOutOfRange
    case missingRace
    case missingClass
    case invalidSubrace
    case invalidAbilityScore
    case invalidRacialBonus
    case tooManySkills
    case invalidSkill
    case invalidExperience
    case noImprovementPoints
    case abilityAtMaximum
    case characterNotFound
    case invalidHitPointRolls
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

    /// Builds a character from the creation form and adds it.
    @discardableResult
    public mutating func add(_ draft: CharacterDraft, catalog: RulesCatalog = .srd) throws -> PlayerCharacter {
        let character = try draft.build(catalog: catalog)
        characters.append(character)
        return character
    }

    public func character(id: PlayerCharacter.ID) -> PlayerCharacter? {
        characters.first { $0.id == id }
    }

    /// Runs a change on one character and stores the result.
    @discardableResult
    public mutating func update<T>(
        id: PlayerCharacter.ID,
        _ change: (inout PlayerCharacter) throws -> T
    ) throws -> T {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { throw CharacterError.characterNotFound }
        var copy = characters[index]
        let result = try change(&copy)
        characters[index] = copy
        return result
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
