import Foundation

/// A change to a number, such as spell slots or a class counter.
public struct LevelUpChange: Hashable, Sendable {
    public let name: String
    public let from: String?
    public let to: String

    public init(name: String, from: String?, to: String) {
        self.name = name
        self.from = from
        self.to = to
    }
}

/// What a character gains at one new level.
public struct LevelUnlocks: Hashable, Sendable {
    public let level: Int
    public let hitPointIncrease: Int
    /// The hit die roll behind the increase, when hit points are rolled.
    public let hitPointRoll: Int?
    /// Set when the proficiency bonus goes up at this level.
    public let proficiencyBonus: Int?
    public let abilityScoreImprovement: Bool
    /// Set at the level the subclass is gained.
    public let subclass: Subclass?
    public let features: [LevelFeature]
    public let spellSlotChanges: [LevelUpChange]
    public let cantripsGained: Int
    public let spellsKnownGained: Int
    /// Set when the character can cast a higher spell level for the first time.
    public let newSpellLevel: Int?
    /// Class spells of the new spell level.
    public let newlyAvailableSpells: [Spell]
    /// Subclass spells gained at this level, such as domain spells.
    public let subclassSpells: [Spell]
    public let counterChanges: [LevelUpChange]

    /// True when nothing but hit points changed.
    public var isHitPointsOnly: Bool {
        proficiencyBonus == nil && !abilityScoreImprovement && subclass == nil && features.isEmpty
            && spellSlotChanges.isEmpty && cantripsGained == 0 && spellsKnownGained == 0
            && newSpellLevel == nil && subclassSpells.isEmpty && counterChanges.isEmpty
    }
}

/// Everything unlocked by going from one level to a higher one.
public struct LevelUpSummary: Hashable, Identifiable, Sendable {
    public var id: String { "\(characterName)-\(fromLevel)-\(toLevel)" }
    public let characterName: String
    public let fromLevel: Int
    public let toLevel: Int
    public let levels: [LevelUnlocks]

    /// Works out what each level from `fromLevel + 1` to the character's current level unlocks.
    public init(character: PlayerCharacter, fromLevel: Int, catalog: RulesCatalog = .srd) {
        let sheet = CharacterSheet(character: character, catalog: catalog)
        self.characterName = character.name
        self.fromLevel = fromLevel
        self.toLevel = character.level
        guard character.level > fromLevel else {
            self.levels = []
            return
        }
        self.levels = ((fromLevel + 1)...character.level).map { level in
            LevelUpSummary.unlocks(at: level, sheet: sheet, catalog: catalog)
        }
    }

    private static func unlocks(at level: Int, sheet: CharacterSheet, catalog: RulesCatalog) -> LevelUnlocks {
        let hitPointIncrease = sheet.hitPoints(atLevel: level) - sheet.hitPoints(atLevel: level - 1)
        guard let characterClass = sheet.characterClass,
              let current = characterClass.level(level) else {
            let bonus = 2 + (level - 1) / 4
            let previousBonus = 2 + (level - 2) / 4
            return LevelUnlocks(
                level: level, hitPointIncrease: hitPointIncrease, hitPointRoll: sheet.hitPointRoll(forLevel: level),
                proficiencyBonus: bonus > previousBonus ? bonus : nil,
                abilityScoreImprovement: false, subclass: nil, features: [], spellSlotChanges: [],
                cantripsGained: 0, spellsKnownGained: 0, newSpellLevel: nil,
                newlyAvailableSpells: [], subclassSpells: [], counterChanges: []
            )
        }
        let previous = characterClass.level(level - 1)

        let slots = current.spellSlots ?? []
        let previousSlots = previous?.spellSlots ?? []
        let slotChanges: [LevelUpChange] = slots.indices.compactMap { index in
            let before = index < previousSlots.count ? previousSlots[index] : 0
            guard slots[index] != before else { return nil }
            return LevelUpChange(name: "\(Spell.ordinal(index + 1))-level slots", from: String(before), to: String(slots[index]))
        }

        let previousHighest = previous?.highestSpellLevel ?? 0
        let newSpellLevel = current.highestSpellLevel > previousHighest ? current.highestSpellLevel : nil
        var available: [Spell] = []
        if let newSpellLevel {
            available = catalog.spells(forClass: characterClass.id, levels: (previousHighest + 1)...newSpellLevel)
        }
        let cantripsGained = (current.cantripsKnown ?? 0) - (previous?.cantripsKnown ?? 0)
        if cantripsGained > 0, (previous?.cantripsKnown ?? 0) == 0 {
            available = catalog.spells(forClass: characterClass.id, levels: 0...0) + available
        }

        let counterChanges: [LevelUpChange] = current.activeCounters.sorted { $0.key < $1.key }.compactMap { entry in
            let before = previous?.activeCounters[entry.key]
            guard before != entry.value else { return nil }
            return LevelUpChange(name: entry.key, from: before, to: entry.value)
        }

        let previousBonus = previous?.proficiencyBonus ?? current.proficiencyBonus
        let gainsSubclass = level == characterClass.subclassLevel
        return LevelUnlocks(
            level: level,
            hitPointIncrease: hitPointIncrease,
            hitPointRoll: sheet.hitPointRoll(forLevel: level),
            proficiencyBonus: current.proficiencyBonus > previousBonus ? current.proficiencyBonus : nil,
            abilityScoreImprovement: current.abilityScoreImprovement,
            subclass: gainsSubclass ? characterClass.subclass : nil,
            features: sheet.features(in: level...level),
            spellSlotChanges: slotChanges,
            cantripsGained: max(0, cantripsGained),
            spellsKnownGained: max(0, (current.spellsKnown ?? 0) - (previous?.spellsKnown ?? 0)),
            newSpellLevel: newSpellLevel,
            newlyAvailableSpells: available,
            subclassSpells: catalog.spells(ids: characterClass.subclass.bonusSpellIDs(atLevel: level)),
            counterChanges: counterChanges
        )
    }
}
