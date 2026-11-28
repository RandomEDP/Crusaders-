import Foundation

/// A class or subclass feature with the level it arrives at.
public struct LevelFeature: Hashable, Sendable {
    public let level: Int
    /// "Fighter" or "Champion"
    public let source: String
    public let rule: RuleText

    public init(level: Int, source: String, rule: RuleText) {
        self.level = level
        self.source = source
        self.rule = rule
    }
}

/// Everything the character sheet shows, worked out from a character and the rules.
public struct CharacterSheet: Sendable {
    public let character: PlayerCharacter
    public let race: Race?
    public let subrace: Subrace?
    public let characterClass: CharacterClass?
    private let catalog: RulesCatalog

    public init(character: PlayerCharacter, catalog: RulesCatalog = .srd) {
        self.character = character
        self.catalog = catalog
        let race = catalog.race(id: character.raceID)
        self.race = race
        self.subrace = race?.subrace(id: character.subraceID)
        self.characterClass = catalog.characterClass(id: character.classID)
    }

    public var level: Int { character.level }

    public var classLevel: ClassLevel? { characterClass?.level(level) }

    // MARK: Abilities

    /// Bonuses from race, subrace and the race's "choose your bonus" rule.
    public var racialBonuses: [Ability: Int] {
        var bonuses = race?.abilityBonuses ?? [:]
        for (ability, bonus) in subrace?.abilityBonuses ?? [:] {
            bonuses[ability, default: 0] += bonus
        }
        let choiceBonus = race?.abilityBonusChoice?.bonus ?? 0
        for ability in character.racialBonusChoices {
            bonuses[ability, default: 0] += choiceBonus
        }
        return bonuses
    }

    /// Final scores: base + racial bonuses + Ability Score Improvements.
    public var abilityScores: AbilityScores {
        var improvements: [Ability: Int] = [:]
        for ability in character.improvementPoints {
            improvements[ability, default: 0] += 1
        }
        return character.baseAbilityScores.adding(racialBonuses).adding(improvements)
    }

    public func modifier(_ ability: Ability) -> Int {
        abilityScores.modifier(ability)
    }

    public var proficiencyBonus: Int {
        classLevel?.proficiencyBonus ?? (2 + (level - 1) / 4)
    }

    /// Ability Score Improvement points earned so far (2 per improvement level).
    public var improvementPointsEarned: Int {
        (characterClass?.levels ?? []).filter { $0.level <= level && $0.abilityScoreImprovement }.count * 2
    }

    public var unspentImprovementPoints: Int {
        max(0, improvementPointsEarned - character.improvementPoints.count)
    }

    // MARK: Combat

    public var speed: Int { race?.speed ?? 30 }

    public var initiative: Int { modifier(.dex) }

    public var hitDie: Int { characterClass?.hitDie ?? 8 }

    /// Max hit points using the fixed value for each level after the first.
    public var maxHitPoints: Int {
        hitPoints(atLevel: level)
    }

    /// Max hit points the character would have at a level, with today's Constitution.
    public func hitPoints(atLevel targetLevel: Int) -> Int {
        let constitution = modifier(.con)
        let first = max(1, hitDie + constitution)
        var later = 0
        if targetLevel >= 2 {
            for level in 2...targetLevel {
                if let roll = hitPointRoll(forLevel: level) {
                    later += max(1, roll + constitution)
                } else {
                    later += max(1, hitDie / 2 + 1 + constitution)
                }
            }
        }
        return first + later + extraHitPointsPerLevel(atLevel: targetLevel) * targetLevel
    }

    /// The hit die roll for a level, when hit points are rolled and that level has a roll.
    public func hitPointRoll(forLevel level: Int) -> Int? {
        guard character.hitPointMethod == .rolled, level >= 2 else { return nil }
        let index = level - 2
        return index < character.hitPointRolls.count ? character.hitPointRolls[index] : nil
    }

    /// Hill Dwarf's Dwarven Toughness and the Draconic Bloodline's Draconic Resilience.
    func extraHitPointsPerLevel(atLevel targetLevel: Int) -> Int {
        var extra = 0
        if subrace?.id == "hill-dwarf" { extra += 1 }
        if let characterClass, characterClass.subclass.id == "draconic", targetLevel >= characterClass.subclassLevel { extra += 1 }
        return extra
    }

    public func isProficient(save ability: Ability) -> Bool {
        characterClass?.savingThrows.contains(ability) ?? false
    }

    public func savingThrow(_ ability: Ability) -> Int {
        modifier(ability) + (isProficient(save: ability) ? proficiencyBonus : 0)
    }

    public func isProficient(_ skill: Skill) -> Bool {
        character.skillProficiencies.contains(skill)
    }

    public func skillModifier(_ skill: Skill) -> Int {
        modifier(skill.ability) + (isProficient(skill) ? proficiencyBonus : 0)
    }

    public var passivePerception: Int { 10 + skillModifier(.perception) }

    // MARK: Traits and features

    public var traits: [RuleText] {
        (race?.traits ?? []) + (subrace?.traits ?? [])
    }

    public var hasSubclass: Bool {
        guard let characterClass else { return false }
        return level >= characterClass.subclassLevel
    }

    /// Class and subclass features, from level 1 up to the character's level.
    public var features: [LevelFeature] {
        features(in: 1...max(1, level))
    }

    public func features(in levels: ClosedRange<Int>) -> [LevelFeature] {
        guard let characterClass else { return [] }
        return levels.flatMap { number -> [LevelFeature] in
            let classFeatures = (characterClass.level(number)?.features ?? []).map {
                LevelFeature(level: number, source: characterClass.name, rule: $0)
            }
            let subclassFeatures = characterClass.subclass.features(atLevel: number).map {
                LevelFeature(level: number, source: characterClass.subclass.name, rule: $0)
            }
            return classFeatures + subclassFeatures
        }
    }

    /// Class counters in use, such as "Rage count: 3", sorted by name.
    public var counters: [(name: String, value: String)] {
        (classLevel?.activeCounters ?? [:]).sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
    }

    // MARK: Spellcasting

    public var spellcastingAbility: Ability? { characterClass?.spellcastingAbility }

    /// True once the class has cantrips or spell slots (Paladins and Rangers start at level 2).
    public var canCastSpells: Bool {
        spellcastingAbility != nil && (highestSpellLevel > 0 || (cantripLimit ?? 0) > 0)
    }

    /// Slots for spell levels 1 to 9.
    public var spellSlots: [Int] { classLevel?.spellSlots ?? Array(repeating: 0, count: 9) }

    public var highestSpellLevel: Int { classLevel?.highestSpellLevel ?? 0 }

    public var cantripLimit: Int? { classLevel?.cantripsKnown }

    /// How many leveled spells the class knows (Bard, Ranger, Sorcerer, Warlock). Nil for classes that prepare.
    public var spellsKnownLimit: Int? { classLevel?.spellsKnown }

    public var spellSaveDC: Int? {
        spellcastingAbility.map { 8 + proficiencyBonus + modifier($0) }
    }

    public var spellAttackBonus: Int? {
        spellcastingAbility.map { proficiencyBonus + modifier($0) }
    }

    public var knownSpells: [Spell] {
        catalog.spells.filter { character.spellIDs.contains($0.id) }
    }

    public var knownCantripCount: Int { knownSpells.filter(\.isCantrip).count }

    public var knownLeveledSpellCount: Int { knownSpells.filter { !$0.isCantrip }.count }

    /// Spells the subclass adds at the character's level, such as a Cleric's domain spells.
    public var subclassSpells: [Spell] {
        guard let characterClass, hasSubclass else { return [] }
        return catalog.spells(ids: characterClass.subclass.bonusSpellIDs(upToLevel: level))
    }

    /// Spells on the class list the character can cast right now.
    public var learnableSpells: [Spell] {
        guard let characterClass, canCastSpells else { return [] }
        let lowest = (cantripLimit ?? 0) > 0 ? 0 : 1
        let highest = max(lowest, highestSpellLevel)
        return catalog.spells(forClass: characterClass.id, levels: lowest...highest)
    }

    // MARK: Experience

    public var nextLevelXP: Int? { Experience.nextLevelXP(afterLevel: level) }

    /// 0 to 1: progress from this level's XP to the next.
    public var levelProgress: Double {
        guard let next = nextLevelXP else { return 1 }
        let start = Experience.minimumXP(forLevel: level)
        let span = Double(next - start)
        return min(1, max(0, Double(character.experiencePoints - start) / span))
    }
}
