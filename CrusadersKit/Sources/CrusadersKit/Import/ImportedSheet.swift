import Foundation

/// Everything read from a character sheet made by another app (D&D Beyond), as printed.
///
/// The numbers here are the ones the other app printed, with its feats, species traits and items already
/// applied. The app doesn't work them out again. Kept inside the character's saved JSON, so it syncs
/// with the character and needs no change to the stored record.
public struct ImportedSheet: Codable, Hashable, Sendable {
    /// e.g. "D&D Beyond"
    public var source: String
    public var importedAt: Date
    /// "2024" when the sheet says SPECIES (PHB-2024 rules), "2014" when it says RACE.
    public var rulesEdition: String?

    // MARK: Identity
    public var playerName: String?
    public var classes: [ClassEntry]
    public var species: String?
    /// e.g. "Black Dragon" for a Dragonborn's Draconic Ancestry.
    public var ancestry: String?
    public var background: String?
    public var alignment: String?
    public var size: String?
    public var experiencePoints: Int?

    // MARK: Numbers as printed
    public var abilities: [AbilityEntry]
    public var savingThrows: [SavingThrowEntry]
    public var skills: [SkillEntry]
    public var armorClass: Int?
    public var initiative: Int?
    public var speeds: [SpeedEntry]
    public var maxHitPoints: Int?
    /// e.g. "4d6", or "4d6 + 1d8" for a multiclass.
    public var hitDice: String?
    public var proficiencyBonus: Int?
    public var passivePerception: Int?
    public var passiveInsight: Int?
    public var passiveInvestigation: Int?

    // MARK: Traits
    /// e.g. "Darkvision 60 ft."
    public var senses: [String]
    /// e.g. "Acid"
    public var resistances: [String]
    public var immunities: [String]
    public var vulnerabilities: [String]
    public var languages: [String]
    public var armorProficiencies: [String]
    public var weaponProficiencies: [String]
    public var toolProficiencies: [String]

    // MARK: Gear
    public var attacks: [AttackEntry]
    public var coins: [CoinEntry]
    public var equipment: [EquipmentEntry]

    // MARK: Spells
    public var spellcasting: [SpellcastingEntry]
    public var spellSlots: [SpellSlotEntry]
    public var spells: [SpellEntry]

    // MARK: Features
    public var resources: [ResourceEntry]
    public var feats: [String]
    public var metamagic: [String]
    public var features: [FeatureEntry]

    // MARK: Details
    public var personalityTraits: String?
    public var ideals: String?
    public var bonds: String?
    public var flaws: String?
    public var backstory: String?
    /// Gender, age, height, eyes, faith, appearance, allies, notes and so on, by the sheet's label.
    public var otherDetails: [DetailEntry]

    /// Everything read from the PDF, so a better parser can read it again later.
    public var rawText: String

    public init(source: String = "D&D Beyond", importedAt: Date = Date()) {
        self.source = source
        self.importedAt = importedAt
        classes = []
        abilities = []
        savingThrows = []
        skills = []
        speeds = []
        senses = []
        resistances = []
        immunities = []
        vulnerabilities = []
        languages = []
        armorProficiencies = []
        weaponProficiencies = []
        toolProficiencies = []
        attacks = []
        coins = []
        equipment = []
        spellcasting = []
        spellSlots = []
        spells = []
        resources = []
        feats = []
        metamagic = []
        features = []
        otherDetails = []
        rawText = ""
    }

    // MARK: Entries

    public struct ClassEntry: Codable, Hashable, Sendable {
        public var name: String
        public var level: Int
        /// e.g. "Draconic Sorcery"
        public var subclass: String?

        public init(name: String, level: Int, subclass: String? = nil) {
            self.name = name
            self.level = level
            self.subclass = subclass
        }
    }

    public struct AbilityEntry: Codable, Hashable, Sendable {
        public var ability: Ability
        public var score: Int
        public var modifier: Int

        public init(ability: Ability, score: Int, modifier: Int) {
            self.ability = ability
            self.score = score
            self.modifier = modifier
        }
    }

    public struct SavingThrowEntry: Codable, Hashable, Sendable {
        public var ability: Ability
        public var bonus: Int
        public var proficient: Bool

        public init(ability: Ability, bonus: Int, proficient: Bool) {
            self.ability = ability
            self.bonus = bonus
            self.proficient = proficient
        }
    }

    public enum Proficiency: String, Codable, Hashable, Sendable {
        case none, proficient, expertise
    }

    public struct SkillEntry: Codable, Hashable, Sendable {
        public var skill: Skill
        public var bonus: Int
        public var proficiency: Proficiency

        public init(skill: Skill, bonus: Int, proficiency: Proficiency) {
            self.skill = skill
            self.bonus = bonus
            self.proficiency = proficiency
        }
    }

    public struct SpeedEntry: Codable, Hashable, Sendable {
        public var feet: Int
        /// e.g. "Walking"
        public var mode: String

        public init(feet: Int, mode: String) {
            self.feet = feet
            self.mode = mode
        }
    }

    public struct AttackEntry: Codable, Hashable, Sendable {
        public var name: String
        public var attackBonus: Int?
        /// e.g. "DC 12" when the attack forces a save instead of rolling to hit.
        public var saveText: String?
        /// e.g. "1d4+1"
        public var damage: String?
        /// e.g. "Piercing"
        public var damageType: String?
        public var notes: String?

        public init(name: String, attackBonus: Int? = nil, saveText: String? = nil, damage: String? = nil,
                    damageType: String? = nil, notes: String? = nil) {
            self.name = name
            self.attackBonus = attackBonus
            self.saveText = saveText
            self.damage = damage
            self.damageType = damageType
            self.notes = notes
        }
    }

    public struct CoinEntry: Codable, Hashable, Sendable {
        public var coin: Coin
        public var count: Int

        public init(coin: Coin, count: Int) {
            self.coin = coin
            self.count = count
        }
    }

    public struct EquipmentEntry: Codable, Hashable, Sendable {
        public var name: String
        public var quantity: Int
        /// As printed, e.g. "1 lb." for one of them.
        public var weight: String?

        public init(name: String, quantity: Int, weight: String? = nil) {
            self.name = name
            self.quantity = quantity
            self.weight = weight
        }
    }

    public struct SpellcastingEntry: Codable, Hashable, Sendable {
        public var className: String?
        public var ability: Ability?
        public var saveDC: Int?
        public var attackBonus: Int?

        public init(className: String? = nil, ability: Ability? = nil, saveDC: Int? = nil, attackBonus: Int? = nil) {
            self.className = className
            self.ability = ability
            self.saveDC = saveDC
            self.attackBonus = attackBonus
        }
    }

    public struct SpellSlotEntry: Codable, Hashable, Sendable {
        public var level: Int
        public var slots: Int

        public init(level: Int, slots: Int) {
            self.level = level
            self.slots = slots
        }
    }

    public struct SpellEntry: Codable, Hashable, Sendable {
        public var name: String
        /// 0 for cantrips.
        public var level: Int
        /// e.g. "Sorcerer" or "Draconic Spells (Always Prepared)"
        public var source: String?
        public var alwaysPrepared: Bool
        /// e.g. "DEX 12", "+4" or "DEX 12 / +4"
        public var saveOrAttack: String?
        public var castingTime: String?
        public var range: String?
        public var components: String?
        public var duration: String?
        public var pageReference: String?
        public var notes: String?
        /// The SRD spell with the same name, when there is one.
        public var srdID: String?

        public init(name: String, level: Int, source: String? = nil, alwaysPrepared: Bool = false,
                    saveOrAttack: String? = nil, castingTime: String? = nil, range: String? = nil,
                    components: String? = nil, duration: String? = nil, pageReference: String? = nil,
                    notes: String? = nil, srdID: String? = nil) {
            self.name = name
            self.level = level
            self.source = source
            self.alwaysPrepared = alwaysPrepared
            self.saveOrAttack = saveOrAttack
            self.castingTime = castingTime
            self.range = range
            self.components = components
            self.duration = duration
            self.pageReference = pageReference
            self.notes = notes
            self.srdID = srdID
        }
    }

    /// Something with limited uses, such as "Sorcery Points 4 / Long Rest".
    public struct ResourceEntry: Codable, Hashable, Sendable {
        public var name: String
        public var uses: Int
        /// e.g. "Long Rest"
        public var recharge: String
        public var saveDC: Int?
        /// e.g. "Dex"
        public var saveAbility: String?
        /// e.g. "1d10"
        public var damage: String?
        /// e.g. "Acid"
        public var damageType: String?

        public init(name: String, uses: Int, recharge: String, saveDC: Int? = nil, saveAbility: String? = nil,
                    damage: String? = nil, damageType: String? = nil) {
            self.name = name
            self.uses = uses
            self.recharge = recharge
            self.saveDC = saveDC
            self.saveAbility = saveAbility
            self.damage = damage
            self.damageType = damageType
        }

        /// e.g. "DC 12 Dex, 1d10 Acid"
        public var detailText: String? {
            var parts: [String] = []
            if let saveDC { parts.append(["DC \(saveDC)", saveAbility].compactMap { $0 }.joined(separator: " ")) }
            if let damage { parts.append([damage, damageType].compactMap { $0 }.joined(separator: " ")) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    public struct FeatureEntry: Codable, Hashable, Sendable {
        /// e.g. "Sorcerer Features", "Feats"
        public var section: String
        public var name: String
        /// e.g. "PHB-2024 140"
        public var source: String?
        public var text: String
        /// Choices and options under the feature, such as metamagic options.
        public var options: [String]

        public init(section: String, name: String, source: String? = nil, text: String = "", options: [String] = []) {
            self.section = section
            self.name = name
            self.source = source
            self.text = text
            self.options = options
        }
    }

    public struct DetailEntry: Codable, Hashable, Sendable {
        public var label: String
        public var text: String

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    // MARK: Lookups

    public var totalLevel: Int { classes.reduce(0) { $0 + $1.level } }

    /// e.g. "Sorcerer 4 / Warlock 1"
    public var classSummary: String {
        classes.map { "\($0.name) \($0.level)" }.joined(separator: " / ")
    }

    public func ability(_ ability: Ability) -> AbilityEntry? {
        abilities.first { $0.ability == ability }
    }

    public func savingThrow(_ ability: Ability) -> SavingThrowEntry? {
        savingThrows.first { $0.ability == ability }
    }

    public func skill(_ skill: Skill) -> SkillEntry? {
        skills.first { $0.skill == skill }
    }

    public func coins(_ coin: Coin) -> Int {
        coins.first { $0.coin == coin }?.count ?? 0
    }

    public func resource(named name: String) -> ResourceEntry? {
        resources.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func equipment(named name: String) -> EquipmentEntry? {
        equipment.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func spells(atLevel level: Int) -> [SpellEntry] {
        spells.filter { $0.level == level }
    }

    public func slots(atLevel level: Int) -> Int {
        spellSlots.first { $0.level == level }?.slots ?? 0
    }

    public var coinPurse: CoinPurse {
        CoinPurse(Dictionary(coins.map { ($0.coin, $0.count) }, uniquingKeysWith: +))
    }
}
