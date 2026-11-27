import Foundation

/// The character creation form: the player's choices before the character exists.
public struct CharacterDraft: Equatable, Sendable {
    public var name: String
    public private(set) var raceID: String?
    public private(set) var subraceID: String?
    public private(set) var classID: String?
    public var level: Int
    public var baseAbilityScores: AbilityScores
    public private(set) var racialBonusChoices: [Ability]
    public private(set) var skills: Set<Skill>

    public init(
        name: String = "",
        raceID: String? = nil,
        subraceID: String? = nil,
        classID: String? = nil,
        level: Int = 1,
        baseAbilityScores: AbilityScores = AbilityScores(),
        racialBonusChoices: [Ability] = [],
        skills: Set<Skill> = []
    ) {
        self.name = name
        self.raceID = raceID
        self.subraceID = subraceID
        self.classID = classID
        self.level = level
        self.baseAbilityScores = baseAbilityScores
        self.racialBonusChoices = racialBonusChoices
        self.skills = skills
    }

    /// A ready-to-go starting point: a Human Fighter with the standard array.
    public static func starter(catalog: RulesCatalog = .srd) -> CharacterDraft {
        var draft = CharacterDraft()
        draft.selectRace(catalog.race(id: "human")?.id ?? catalog.races.first?.id, catalog: catalog)
        draft.selectClass(catalog.characterClass(id: "fighter")?.id ?? catalog.classes.first?.id, catalog: catalog)
        draft.useStandardArray(catalog: catalog)
        return draft
    }

    // MARK: Choices

    /// Picks a race and its first subrace, and clears choices the new race doesn't allow.
    public mutating func selectRace(_ id: String?, catalog: RulesCatalog = .srd) {
        raceID = id
        subraceID = catalog.race(id: id)?.subraces.first?.id
        racialBonusChoices = []
        dropDisallowedSkills(catalog: catalog)
    }

    public mutating func selectSubrace(_ id: String?) {
        subraceID = id
    }

    public mutating func selectClass(_ id: String?, catalog: RulesCatalog = .srd) {
        classID = id
        dropDisallowedSkills(catalog: catalog)
    }

    /// Places the standard array to suit the chosen class.
    public mutating func useStandardArray(catalog: RulesCatalog = .srd) {
        let order = catalog.characterClass(id: classID)?.suggestedAbilityOrder ?? Ability.allCases
        baseAbilityScores = AbilityScores.standardArray(order: order)
    }

    /// Adds or removes an ability from the race's "choose your bonus" rule, up to its limit.
    public mutating func toggleRacialBonus(_ ability: Ability, catalog: RulesCatalog = .srd) {
        if let index = racialBonusChoices.firstIndex(of: ability) {
            racialBonusChoices.remove(at: index)
            return
        }
        guard let choice = catalog.race(id: raceID)?.abilityBonusChoice,
              choice.from.contains(ability),
              racialBonusChoices.count < choice.count else { return }
        racialBonusChoices.append(ability)
    }

    /// Adds or removes a skill, up to the number the class and race allow.
    public mutating func toggleSkill(_ skill: Skill, catalog: RulesCatalog = .srd) {
        if skills.contains(skill) {
            skills.remove(skill)
            return
        }
        guard allowedSkills(catalog: catalog).contains(skill), skills.count < skillChoiceCount(catalog: catalog) else { return }
        skills.insert(skill)
    }

    // MARK: Rules for the form

    /// Skills the player may pick (granted racial skills are left out because they're automatic).
    public func allowedSkills(catalog: RulesCatalog = .srd) -> [Skill] {
        guard let characterClass = catalog.characterClass(id: classID) else { return [] }
        let race = catalog.race(id: raceID)
        let granted = race?.grantedSkills ?? []
        let pool = (race?.extraSkillChoices ?? 0) > 0 ? Skill.allCases : characterClass.skillChoices.from
        return pool.filter { !granted.contains($0) }
    }

    public func skillChoiceCount(catalog: RulesCatalog = .srd) -> Int {
        (catalog.characterClass(id: classID)?.skillChoices.count ?? 0) + (catalog.race(id: raceID)?.extraSkillChoices ?? 0)
    }

    private mutating func dropDisallowedSkills(catalog: RulesCatalog) {
        let allowed = Set(allowedSkills(catalog: catalog))
        skills = skills.intersection(allowed)
        let limit = skillChoiceCount(catalog: catalog)
        while skills.count > limit, let extra = skills.sorted(by: { $0.rawValue < $1.rawValue }).last {
            skills.remove(extra)
        }
    }

    // MARK: Building

    /// Checks every choice and returns the finished character.
    public func build(catalog: RulesCatalog = .srd) throws -> PlayerCharacter {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CharacterError.emptyName }
        guard PlayerCharacter.levelRange.contains(level) else { throw CharacterError.levelOutOfRange }
        guard let race = catalog.race(id: raceID) else { throw CharacterError.missingRace }
        guard let characterClass = catalog.characterClass(id: classID) else { throw CharacterError.missingClass }

        let subrace = race.subrace(id: subraceID)
        if race.subraces.isEmpty {
            guard subraceID == nil else { throw CharacterError.invalidSubrace }
        } else {
            guard subrace != nil else { throw CharacterError.invalidSubrace }
        }

        guard Ability.allCases.allSatisfy({ AbilityScores.baseRange.contains(baseAbilityScores[$0]) }) else {
            throw CharacterError.invalidAbilityScore
        }

        if let choice = race.abilityBonusChoice {
            guard racialBonusChoices.count <= choice.count,
                  Set(racialBonusChoices).count == racialBonusChoices.count,
                  racialBonusChoices.allSatisfy({ choice.from.contains($0) }) else { throw CharacterError.invalidRacialBonus }
        } else {
            guard racialBonusChoices.isEmpty else { throw CharacterError.invalidRacialBonus }
        }

        let allowed = Set(allowedSkills(catalog: catalog))
        guard skills.isSubset(of: allowed) else { throw CharacterError.invalidSkill }
        guard skills.count <= skillChoiceCount(catalog: catalog) else { throw CharacterError.tooManySkills }

        return PlayerCharacter(
            name: trimmedName,
            race: subrace?.name ?? race.name,
            characterClass: characterClass.name,
            level: level,
            raceID: race.id,
            subraceID: subrace?.id,
            classID: characterClass.id,
            baseAbilityScores: baseAbilityScores,
            racialBonusChoices: racialBonusChoices,
            skillProficiencies: skills.union(race.grantedSkills)
        )
    }

    /// A sheet for the summary at the bottom of the form, whether or not the draft is finished.
    public func preview(catalog: RulesCatalog = .srd) -> CharacterSheet {
        let race = catalog.race(id: raceID)
        let character = PlayerCharacter(
            name: name,
            race: race?.subrace(id: subraceID)?.name ?? race?.name ?? "",
            characterClass: catalog.characterClass(id: classID)?.name ?? "",
            level: min(max(level, 1), 20),
            raceID: raceID,
            subraceID: subraceID,
            classID: classID,
            baseAbilityScores: baseAbilityScores,
            racialBonusChoices: racialBonusChoices,
            skillProficiencies: skills.union(race?.grantedSkills ?? [])
        )
        return CharacterSheet(character: character, catalog: catalog)
    }
}
