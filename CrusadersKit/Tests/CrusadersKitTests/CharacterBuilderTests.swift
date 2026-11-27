import XCTest
@testable import CrusadersKit

final class CharacterBuilderTests: XCTestCase {
    private func draft(race: String, subrace: String? = nil, characterClass: String, level: Int = 1) -> CharacterDraft {
        var draft = CharacterDraft(name: "Hero", level: level)
        draft.selectRace(race)
        if let subrace { draft.selectSubrace(subrace) }
        draft.selectClass(characterClass)
        draft.useStandardArray()
        return draft
    }

    func testStarterIsAHumanFighterThatBuilds() throws {
        var starter = CharacterDraft.starter()
        XCTAssertEqual(starter.raceID, "human")
        XCTAssertEqual(starter.classID, "fighter")
        XCTAssertEqual(starter.baseAbilityScores.str, 15)
        starter.name = "  Aria "
        let character = try starter.build()
        XCTAssertEqual(character.name, "Aria")
        XCTAssertEqual(character.race, "Human")
        XCTAssertEqual(character.characterClass, "Fighter")
        XCTAssertEqual(character.summary, "Level 1 Human Fighter")
        XCTAssertEqual(character.experiencePoints, 0)
    }

    func testSelectingARacePicksItsFirstSubrace() {
        var draft = CharacterDraft()
        draft.selectRace("dwarf")
        XCTAssertEqual(draft.subraceID, "hill-dwarf")
        draft.selectRace("human")
        XCTAssertNil(draft.subraceID)
    }

    func testBuildUsesSubraceNameAndStartingXPForLevel() throws {
        let character = try draft(race: "dwarf", characterClass: "cleric", level: 5).build()
        XCTAssertEqual(character.race, "Hill Dwarf")
        XCTAssertEqual(character.raceID, "dwarf")
        XCTAssertEqual(character.subraceID, "hill-dwarf")
        XCTAssertEqual(character.experiencePoints, 6_500)
    }

    func testBuildRejectsBadChoices() {
        var noName = draft(race: "human", characterClass: "fighter")
        noName.name = " "
        XCTAssertThrowsError(try noName.build()) { XCTAssertEqual($0 as? CharacterError, .emptyName) }

        var noRace = CharacterDraft(name: "A")
        noRace.selectClass("fighter")
        XCTAssertThrowsError(try noRace.build()) { XCTAssertEqual($0 as? CharacterError, .missingRace) }

        var noClass = CharacterDraft(name: "A")
        noClass.selectRace("human")
        XCTAssertThrowsError(try noClass.build()) { XCTAssertEqual($0 as? CharacterError, .missingClass) }

        var badLevel = draft(race: "human", characterClass: "fighter")
        badLevel.level = 21
        XCTAssertThrowsError(try badLevel.build()) { XCTAssertEqual($0 as? CharacterError, .levelOutOfRange) }

        var badScore = draft(race: "human", characterClass: "fighter")
        badScore.baseAbilityScores.str = 19
        XCTAssertThrowsError(try badScore.build()) { XCTAssertEqual($0 as? CharacterError, .invalidAbilityScore) }

        var missingSubrace = draft(race: "elf", characterClass: "wizard")
        missingSubrace.selectSubrace(nil)
        XCTAssertThrowsError(try missingSubrace.build()) { XCTAssertEqual($0 as? CharacterError, .invalidSubrace) }

        var strayBonus = CharacterDraft(name: "A", raceID: "human", classID: "fighter", racialBonusChoices: [.str])
        strayBonus.useStandardArray()
        XCTAssertThrowsError(try strayBonus.build()) { XCTAssertEqual($0 as? CharacterError, .invalidRacialBonus) }

        let badSkill = CharacterDraft(name: "A", raceID: "human", classID: "fighter", skills: [.arcana])
        XCTAssertThrowsError(try badSkill.build()) { XCTAssertEqual($0 as? CharacterError, .invalidSkill) }

        let tooMany = CharacterDraft(name: "A", raceID: "human", classID: "fighter", skills: [.athletics, .history, .insight])
        XCTAssertThrowsError(try tooMany.build()) { XCTAssertEqual($0 as? CharacterError, .tooManySkills) }
    }

    func testSkillChoicesAreLimitedToTheClassList() {
        var fighter = draft(race: "human", characterClass: "fighter")
        XCTAssertEqual(fighter.skillChoiceCount(), 2)
        fighter.toggleSkill(.arcana)
        XCTAssertTrue(fighter.skills.isEmpty, "Arcana isn't a fighter skill")
        fighter.toggleSkill(.athletics)
        fighter.toggleSkill(.perception)
        fighter.toggleSkill(.survival)
        XCTAssertEqual(fighter.skills, [.athletics, .perception], "third pick is over the limit")
        fighter.toggleSkill(.athletics)
        XCTAssertEqual(fighter.skills, [.perception])
    }

    func testChangingClassDropsSkillsTheNewClassDoesntHave() {
        var draft = draft(race: "human", characterClass: "fighter")
        draft.toggleSkill(.athletics)
        draft.toggleSkill(.history)
        draft.selectClass("wizard")
        XCTAssertEqual(draft.skills, [.history])
    }

    func testRacialSkills() throws {
        let elf = try draft(race: "elf", characterClass: "wizard").build()
        XCTAssertTrue(elf.skillProficiencies.contains(.perception))
        XCTAssertFalse(draft(race: "elf", characterClass: "ranger").allowedSkills().contains(.perception))

        var halfElf = draft(race: "half-elf", characterClass: "fighter")
        XCTAssertEqual(halfElf.skillChoiceCount(), 4)
        XCTAssertEqual(halfElf.allowedSkills().count, 18)
        halfElf.toggleSkill(.arcana)
        XCTAssertEqual(halfElf.skills, [.arcana])
    }

    func testHalfElfBonusChoices() throws {
        var halfElf = draft(race: "half-elf", characterClass: "fighter")
        halfElf.toggleRacialBonus(.cha)
        XCTAssertTrue(halfElf.racialBonusChoices.isEmpty, "Charisma already gets +2")
        halfElf.toggleRacialBonus(.str)
        halfElf.toggleRacialBonus(.con)
        halfElf.toggleRacialBonus(.dex)
        XCTAssertEqual(halfElf.racialBonusChoices, [.str, .con])
        let sheet = CharacterSheet(character: try halfElf.build())
        XCTAssertEqual(sheet.abilityScores.str, 16)
        XCTAssertEqual(sheet.abilityScores.con, 15)
        XCTAssertEqual(sheet.abilityScores.cha, 12)
        halfElf.toggleRacialBonus(.str)
        XCTAssertEqual(halfElf.racialBonusChoices, [.con])
        halfElf.selectRace("human")
        XCTAssertTrue(halfElf.racialBonusChoices.isEmpty)
    }

    func testPreviewWorksBeforeTheDraftIsFinished() {
        XCTAssertEqual(CharacterDraft().preview().maxHitPoints, 8)
        var draft = CharacterDraft()
        draft.selectClass("barbarian")
        XCTAssertEqual(draft.preview().maxHitPoints, 12)
    }

    func testRosterAddsDraftsAndUpdatesCharacters() throws {
        var roster = CharacterRoster()
        let character = try roster.add(draft(race: "human", characterClass: "wizard"))
        XCTAssertEqual(roster.character(id: character.id), character)

        let gained = try roster.update(id: character.id) { try $0.addExperience(900) }
        XCTAssertEqual(gained, 2...3)
        XCTAssertEqual(roster.characters.first?.level, 3)

        XCTAssertThrowsError(try roster.update(id: UUID()) { $0.name = "x" }) {
            XCTAssertEqual($0 as? CharacterError, .characterNotFound)
        }
    }
}
