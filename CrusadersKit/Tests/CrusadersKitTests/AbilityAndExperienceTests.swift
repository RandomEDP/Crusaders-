import XCTest
@testable import CrusadersKit

final class AbilityAndExperienceTests: XCTestCase {
    func testModifierRoundsDown() {
        let expected = [1: -5, 3: -4, 8: -1, 9: -1, 10: 0, 11: 0, 12: 1, 15: 2, 18: 4, 20: 5, 30: 10]
        for (score, modifier) in expected {
            XCTAssertEqual(AbilityScores.modifier(for: score), modifier, "score \(score)")
        }
    }

    func testSignedFormatting() {
        XCTAssertEqual(AbilityScores.signed(3), "+3")
        XCTAssertEqual(AbilityScores.signed(0), "+0")
        XCTAssertEqual(AbilityScores.signed(-1), "-1")
    }

    func testSubscriptReadsAndWrites() {
        var scores = AbilityScores()
        for (offset, ability) in Ability.allCases.enumerated() {
            scores[ability] = 10 + offset
        }
        XCTAssertEqual(scores, AbilityScores(str: 10, dex: 11, con: 12, int: 13, wis: 14, cha: 15))
        XCTAssertEqual(scores.modifier(.cha), 2)
    }

    func testAddingBonuses() {
        let scores = AbilityScores().adding([.str: 2, .cha: 1])
        XCTAssertEqual(scores.str, 12)
        XCTAssertEqual(scores.cha, 11)
        XCTAssertEqual(scores.dex, 10)
    }

    func testStandardArrayFollowsOrderAndFillsTheRest() {
        let scores = AbilityScores.standardArray(order: [.int, .con])
        XCTAssertEqual(scores.int, 15)
        XCTAssertEqual(scores.con, 14)
        XCTAssertEqual(scores.str, 13)
        XCTAssertEqual(scores.dex, 12)
        XCTAssertEqual(scores.wis, 10)
        XCTAssertEqual(scores.cha, 8)
    }

    func testAbilityNames() {
        XCTAssertEqual(Ability.str.name, "Strength")
        XCTAssertEqual(Ability.wis.abbreviation, "WIS")
    }

    func testSkillsMapToAbilities() {
        XCTAssertEqual(Skill.allCases.count, 18)
        XCTAssertEqual(Skill.athletics.ability, .str)
        XCTAssertEqual(Skill.stealth.ability, .dex)
        XCTAssertEqual(Skill.arcana.ability, .int)
        XCTAssertEqual(Skill.perception.ability, .wis)
        XCTAssertEqual(Skill.persuasion.ability, .cha)
        XCTAssertEqual(Skill.animalHandling.name, "Animal Handling")
        XCTAssertEqual(Skill.sleightOfHand.name, "Sleight of Hand")
        XCTAssertEqual(Skill.history.name, "History")
    }

    func testLevelForXP() {
        XCTAssertEqual(Experience.level(forXP: 0), 1)
        XCTAssertEqual(Experience.level(forXP: 299), 1)
        XCTAssertEqual(Experience.level(forXP: 300), 2)
        XCTAssertEqual(Experience.level(forXP: 6_500), 5)
        XCTAssertEqual(Experience.level(forXP: 354_999), 19)
        XCTAssertEqual(Experience.level(forXP: 355_000), 20)
        XCTAssertEqual(Experience.level(forXP: 9_999_999), 20)
        XCTAssertEqual(Experience.level(forXP: -5), 1)
    }

    func testMinimumAndNextLevelXP() {
        XCTAssertEqual(Experience.minimumXP(forLevel: 1), 0)
        XCTAssertEqual(Experience.minimumXP(forLevel: 5), 6_500)
        XCTAssertEqual(Experience.minimumXP(forLevel: 20), 355_000)
        XCTAssertEqual(Experience.minimumXP(forLevel: 99), 355_000)
        XCTAssertEqual(Experience.nextLevelXP(afterLevel: 1), 300)
        XCTAssertEqual(Experience.nextLevelXP(afterLevel: 19), 355_000)
        XCTAssertNil(Experience.nextLevelXP(afterLevel: 20))
    }

    func testThresholdsMatchEveryLevel() {
        for level in PlayerCharacter.levelRange {
            XCTAssertEqual(Experience.level(forXP: Experience.minimumXP(forLevel: level)), level)
        }
    }
}
