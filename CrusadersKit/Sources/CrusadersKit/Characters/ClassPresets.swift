import Foundation

/// A suggested build for a class: which abilities matter most and which skills to take.
public struct ClassPreset: Hashable, Identifiable, Sendable {
    public let name: String
    public let summary: String
    /// Abilities from most to least important. The best score goes first.
    public let abilityOrder: [Ability]
    public let skills: [Skill]

    public var id: String { name }

    public init(name: String, summary: String, abilityOrder: [Ability], skills: [Skill]) {
        self.name = name
        self.summary = summary
        self.abilityOrder = abilityOrder
        self.skills = skills
    }
}

extension CharacterClass {
    /// Three builds for different play styles.
    public var presets: [ClassPreset] {
        ClassPreset.all[id] ?? []
    }
}

extension ClassPreset {
    static let all: [String: [ClassPreset]] = [
        "barbarian": [
            ClassPreset(name: "Juggernaut", summary: "Charges in first, hits hardest and shrugs off the damage.",
                        abilityOrder: [.str, .con, .dex, .wis, .cha, .int], skills: [.athletics, .intimidation]),
            ClassPreset(name: "Wilderness Scout", summary: "A tough tracker who spots danger before anyone else.",
                        abilityOrder: [.str, .con, .wis, .dex, .int, .cha], skills: [.perception, .survival]),
            ClassPreset(name: "Agile Brawler", summary: "Quick on their feet, with Dex adding to unarmoured defence.",
                        abilityOrder: [.str, .dex, .con, .wis, .cha, .int], skills: [.athletics, .perception])
        ],
        "bard": [
            ClassPreset(name: "Silver Tongue", summary: "The party's face: talks their way in, out and around.",
                        abilityOrder: [.cha, .dex, .con, .int, .wis, .str], skills: [.persuasion, .deception, .insight]),
            ClassPreset(name: "Blade Dancer", summary: "Fights with finesse and puts on a show while doing it.",
                        abilityOrder: [.dex, .cha, .con, .wis, .int, .str], skills: [.acrobatics, .performance, .stealth]),
            ClassPreset(name: "Loremaster", summary: "Knows a song, a story or a secret about everything.",
                        abilityOrder: [.cha, .int, .con, .dex, .wis, .str], skills: [.arcana, .history, .investigation])
        ],
        "cleric": [
            ClassPreset(name: "Battle Priest", summary: "Heavy armour, a mace and a prayer on the front line.",
                        abilityOrder: [.wis, .str, .con, .dex, .cha, .int], skills: [.religion, .medicine]),
            ClassPreset(name: "Healer", summary: "Keeps everyone standing from the second rank.",
                        abilityOrder: [.wis, .con, .dex, .cha, .str, .int], skills: [.medicine, .insight]),
            ClassPreset(name: "Preacher", summary: "Inspires allies and speaks for their god.",
                        abilityOrder: [.wis, .cha, .con, .dex, .int, .str], skills: [.persuasion, .religion])
        ],
        "druid": [
            ClassPreset(name: "Shapeshifter", summary: "Spends fights in beast form, soaking up hits.",
                        abilityOrder: [.wis, .con, .dex, .str, .int, .cha], skills: [.animalHandling, .survival]),
            ClassPreset(name: "Storm Caller", summary: "Hangs back and calls down nature's fury.",
                        abilityOrder: [.wis, .dex, .con, .int, .cha, .str], skills: [.nature, .arcana]),
            ClassPreset(name: "Herbalist", summary: "Knows every plant and how to heal with it.",
                        abilityOrder: [.wis, .con, .int, .dex, .cha, .str], skills: [.medicine, .nature])
        ],
        "fighter": [
            ClassPreset(name: "Tank", summary: "Heavy armour and a shield, holding the line.",
                        abilityOrder: [.str, .con, .dex, .wis, .cha, .int], skills: [.athletics, .intimidation]),
            ClassPreset(name: "Archer", summary: "Picks enemies off from range with a longbow.",
                        abilityOrder: [.dex, .con, .wis, .str, .int, .cha], skills: [.perception, .survival]),
            ClassPreset(name: "Duelist", summary: "One finesse blade, quick reflexes, reads opponents.",
                        abilityOrder: [.dex, .con, .str, .wis, .cha, .int], skills: [.acrobatics, .insight])
        ],
        "monk": [
            ClassPreset(name: "Striker", summary: "A flurry of fists that never stops moving.",
                        abilityOrder: [.dex, .wis, .con, .str, .int, .cha], skills: [.acrobatics, .athletics]),
            ClassPreset(name: "Shadow", summary: "Slips past guards and strikes unseen.",
                        abilityOrder: [.dex, .wis, .con, .int, .cha, .str], skills: [.stealth, .acrobatics]),
            ClassPreset(name: "Ascetic", summary: "Calm, wise and hard to fool.",
                        abilityOrder: [.wis, .dex, .con, .int, .str, .cha], skills: [.insight, .religion])
        ],
        "paladin": [
            ClassPreset(name: "Shield Knight", summary: "Protects allies with plate, shield and auras.",
                        abilityOrder: [.str, .con, .cha, .wis, .dex, .int], skills: [.athletics, .intimidation]),
            ClassPreset(name: "Smiter", summary: "Big two-handed hits charged with Divine Smite.",
                        abilityOrder: [.str, .cha, .con, .wis, .dex, .int], skills: [.athletics, .persuasion]),
            ClassPreset(name: "Crusader", summary: "A holy leader whose words carry as far as their sword.",
                        abilityOrder: [.cha, .str, .con, .wis, .dex, .int], skills: [.persuasion, .religion])
        ],
        "ranger": [
            ClassPreset(name: "Sharpshooter", summary: "Never misses with a bow, never seen first.",
                        abilityOrder: [.dex, .wis, .con, .str, .int, .cha], skills: [.perception, .stealth, .survival]),
            ClassPreset(name: "Twin Blades", summary: "Two weapons, up close and relentless.",
                        abilityOrder: [.dex, .con, .wis, .str, .int, .cha], skills: [.athletics, .perception, .survival]),
            ClassPreset(name: "Beast Friend", summary: "At home in the wild, with animals as allies.",
                        abilityOrder: [.dex, .wis, .con, .int, .cha, .str], skills: [.animalHandling, .nature, .survival])
        ],
        "rogue": [
            ClassPreset(name: "Thief", summary: "Locks, pockets and shadows: nothing is safe.",
                        abilityOrder: [.dex, .con, .int, .wis, .cha, .str], skills: [.stealth, .sleightOfHand, .acrobatics, .perception]),
            ClassPreset(name: "Con Artist", summary: "Lies smoothly and stabs from behind a smile.",
                        abilityOrder: [.dex, .cha, .con, .wis, .int, .str], skills: [.deception, .persuasion, .insight, .stealth]),
            ClassPreset(name: "Investigator", summary: "Finds every clue, trap and hidden door.",
                        abilityOrder: [.dex, .int, .wis, .con, .cha, .str], skills: [.investigation, .perception, .insight, .stealth])
        ],
        "sorcerer": [
            ClassPreset(name: "Blaster", summary: "Raw magic, maximum damage.",
                        abilityOrder: [.cha, .con, .dex, .wis, .int, .str], skills: [.arcana, .intimidation]),
            ClassPreset(name: "Charmer", summary: "Magic in the blood and charm in every word.",
                        abilityOrder: [.cha, .dex, .con, .wis, .int, .str], skills: [.persuasion, .deception]),
            ClassPreset(name: "Mystic", summary: "Feels the source of their power and reads people well.",
                        abilityOrder: [.cha, .con, .wis, .dex, .int, .str], skills: [.insight, .religion])
        ],
        "warlock": [
            ClassPreset(name: "Hexblaster", summary: "Eldritch blasts and curses from a safe distance.",
                        abilityOrder: [.cha, .con, .dex, .wis, .int, .str], skills: [.arcana, .intimidation]),
            ClassPreset(name: "Schemer", summary: "Plays every side and keeps the pact a secret.",
                        abilityOrder: [.cha, .dex, .int, .con, .wis, .str], skills: [.deception, .investigation]),
            ClassPreset(name: "Occultist", summary: "Studies forbidden lore to understand their patron.",
                        abilityOrder: [.cha, .int, .con, .dex, .wis, .str], skills: [.arcana, .history])
        ],
        "wizard": [
            ClassPreset(name: "Battle Mage", summary: "Fireballs first, questions later.",
                        abilityOrder: [.int, .con, .dex, .wis, .cha, .str], skills: [.arcana, .investigation]),
            ClassPreset(name: "Scholar", summary: "Knows the history and the theory behind every spell.",
                        abilityOrder: [.int, .wis, .con, .dex, .cha, .str], skills: [.history, .arcana]),
            ClassPreset(name: "Escape Artist", summary: "Quick, careful and always has a way out.",
                        abilityOrder: [.int, .dex, .con, .wis, .cha, .str], skills: [.arcana, .insight])
        ]
    ]
}
