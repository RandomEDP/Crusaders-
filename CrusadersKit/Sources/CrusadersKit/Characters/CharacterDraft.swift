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
    /// How ability scores are being set. Changing scores outside the method's rules fails `build`.
    public private(set) var abilityMethod: AbilityMethod
    /// The six 4d6 rolls when `abilityMethod` is `.rolled`.
    public private(set) var abilityRolls: [AbilityRoll]
    public private(set) var hitPointMethod: HitPointMethod
    /// Hit die rolls for levels 2 and up when `hitPointMethod` is `.rolled`.
    public private(set) var hitPointRolls: [Int]

    public init(
        name: String = "",
        raceID: String? = nil,
        subraceID: String? = nil,
        classID: String? = nil,
        level: Int = 1,
        baseAbilityScores: AbilityScores = AbilityScores(),
        racialBonusChoices: [Ability] = [],
        skills: Set<Skill> = [],
        abilityMethod: AbilityMethod = .custom
    ) {
        self.name = name
        self.raceID = raceID
        self.subraceID = subraceID
        self.classID = classID
        self.level = level
        self.baseAbilityScores = baseAbilityScores
        self.racialBonusChoices = racialBonusChoices
        self.skills = skills
        self.abilityMethod = abilityMethod
        self.abilityRolls = []
        self.hitPointMethod = .fixed
        self.hitPointRolls = []
    }

    /// A ready-to-go starting point: a Human Fighter with the standard array and fixed hit points.
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

    public mutating func selectClass(_ id: String?, catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        let oldDie = catalog.characterClass(id: classID)?.hitDie
        classID = id
        dropDisallowedSkills(catalog: catalog)
        if hitPointMethod == .rolled, catalog.characterClass(id: id)?.hitDie != oldDie {
            hitPointRolls = []
            syncHitPointRolls(catalog: catalog, roller: roller)
        }
    }

    // MARK: Ability scores

    /// Places the standard array to suit the chosen class.
    public mutating func useStandardArray(catalog: RulesCatalog = .srd) {
        let order = catalog.characterClass(id: classID)?.suggestedAbilityOrder ?? Ability.allCases
        baseAbilityScores = AbilityScores.standardArray(order: order)
        abilityMethod = .standardArray
    }

    /// Switches how scores are set and gives a valid starting point for that method.
    public mutating func selectAbilityMethod(_ method: AbilityMethod, catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        switch method {
        case .standardArray:
            useStandardArray(catalog: catalog)
        case .pointBuy:
            baseAbilityScores = AbilityScores(str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8)
            abilityMethod = .pointBuy
        case .rolled:
            rollAbilityScores(catalog: catalog, roller: roller)
        case .custom:
            for ability in Ability.allCases {
                baseAbilityScores[ability] = min(max(baseAbilityScores[ability], AbilityScores.baseRange.lowerBound), AbilityScores.baseRange.upperBound)
            }
            abilityMethod = .custom
        }
    }

    /// Rolls 4d6 six times, dropping the lowest die each time, and places the results to suit the class.
    public mutating func rollAbilityScores(catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        abilityRolls = (0..<6).map { _ in AbilityRoll.roll(using: roller) }
        abilityMethod = .rolled
        let order = catalog.characterClass(id: classID)?.suggestedAbilityOrder ?? Ability.allCases
        place(abilityRolls.map(\.total).sorted(by: >), order: order)
    }

    /// The score values the current method lets the player place, highest first.
    /// Nil for point buy and custom, where each score is set on its own.
    public var placeableScores: [Int]? {
        switch abilityMethod {
        case .standardArray: return AbilityScores.standardArray
        case .rolled: return abilityRolls.map(\.total).sorted(by: >)
        case .pointBuy, .custom: return nil
        }
    }

    /// Swaps two abilities' scores. Works with every method.
    public mutating func swapScores(_ first: Ability, _ second: Ability) {
        let value = baseAbilityScores[first]
        baseAbilityScores[first] = baseAbilityScores[second]
        baseAbilityScores[second] = value
    }

    /// Whether the score can go up or down by one under the current method.
    public func canAdjust(_ ability: Ability, by delta: Int) -> Bool {
        switch abilityMethod {
        case .pointBuy:
            return delta > 0 ? PointBuy.canIncrease(ability, in: baseAbilityScores) : PointBuy.canDecrease(ability, in: baseAbilityScores)
        case .custom:
            return AbilityScores.baseRange.contains(baseAbilityScores[ability] + delta)
        case .standardArray, .rolled:
            return false
        }
    }

    /// Raises or lowers a score by one for point buy and custom scores.
    public mutating func adjust(_ ability: Ability, by delta: Int) {
        guard delta != 0, canAdjust(ability, by: delta.signum()) else { return }
        baseAbilityScores[ability] += delta.signum()
    }

    /// Points left to spend, for point buy.
    public var pointBuyRemaining: Int? {
        abilityMethod == .pointBuy ? PointBuy.remaining(for: baseAbilityScores) : nil
    }

    /// Uses a class preset: places the best scores where the build needs them and picks its skills.
    public mutating func apply(_ preset: ClassPreset, catalog: RulesCatalog = .srd) {
        let values: [Int]
        if abilityMethod == .rolled, abilityRolls.count == 6 {
            values = abilityRolls.map(\.total).sorted(by: >)
        } else {
            values = AbilityScores.standardArray
            if abilityMethod == .custom { abilityMethod = .standardArray }
        }
        place(values, order: preset.abilityOrder)
        let allowed = Set(allowedSkills(catalog: catalog))
        let limit = skillChoiceCount(catalog: catalog)
        skills = []
        for skill in preset.skills where allowed.contains(skill) && skills.count < limit {
            skills.insert(skill)
        }
    }

    private mutating func place(_ values: [Int], order: [Ability]) {
        let fullOrder = order + Ability.allCases.filter { !order.contains($0) }
        for (ability, value) in zip(fullOrder, values) {
            baseAbilityScores[ability] = value
        }
    }

    // MARK: Hit points

    public mutating func selectHitPointMethod(_ method: HitPointMethod, catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        hitPointMethod = method
        hitPointRolls = []
        syncHitPointRolls(catalog: catalog, roller: roller)
    }

    /// Rolls the hit die again for every level after the first.
    public mutating func rerollHitPoints(catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        guard hitPointMethod == .rolled else { return }
        hitPointRolls = []
        syncHitPointRolls(catalog: catalog, roller: roller)
    }

    /// Keeps one roll per level after the first: drops extras when the level goes down, rolls more when it goes up.
    public mutating func syncHitPointRolls(catalog: RulesCatalog = .srd, roller: DiceRoller = .random) {
        guard hitPointMethod == .rolled else {
            hitPointRolls = []
            return
        }
        let needed = max(0, min(level, PlayerCharacter.levelRange.upperBound) - 1)
        if hitPointRolls.count > needed {
            hitPointRolls.removeLast(hitPointRolls.count - needed)
        }
        let die = catalog.characterClass(id: classID)?.hitDie ?? 8
        while hitPointRolls.count < needed {
            hitPointRolls.append(roller.roll(die))
        }
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

        guard scoresFollowMethod else { throw CharacterError.invalidAbilityScore }

        if hitPointMethod == .rolled {
            guard hitPointRolls.count >= level - 1,
                  hitPointRolls.prefix(level - 1).allSatisfy({ (1...characterClass.hitDie).contains($0) }) else {
                throw CharacterError.invalidHitPointRolls
            }
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
            skillProficiencies: skills.union(race.grantedSkills),
            hitPointMethod: hitPointMethod,
            hitPointRolls: hitPointMethod == .rolled ? Array(hitPointRolls.prefix(level - 1)) : []
        )
    }

    /// Whether the scores are ones the chosen method allows.
    public var scoresFollowMethod: Bool {
        let values = Ability.allCases.map { baseAbilityScores[$0] }
        switch abilityMethod {
        case .standardArray:
            return values.sorted() == AbilityScores.standardArray.sorted()
        case .rolled:
            return abilityRolls.count == 6 && values.sorted() == abilityRolls.map(\.total).sorted()
        case .pointBuy:
            return (PointBuy.spent(on: baseAbilityScores) ?? .max) <= PointBuy.budget
        case .custom:
            return values.allSatisfy { AbilityScores.baseRange.contains($0) }
        }
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
            skillProficiencies: skills.union(race?.grantedSkills ?? []),
            hitPointMethod: hitPointMethod,
            hitPointRolls: hitPointRolls
        )
        return CharacterSheet(character: character, catalog: catalog)
    }
}
