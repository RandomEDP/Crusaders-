import XCTest
@testable import CrusadersKit

final class CreatureCatalogTests: XCTestCase {
    private var srd: [Creature]!

    override func setUpWithError() throws {
        srd = try SRDCreatures.load()
    }

    // MARK: SRD data

    func testShipsEverySRDCreatureWithUniqueIds() {
        XCTAssertEqual(srd.count, 334)
        XCTAssertEqual(Set(srd.map(\.id)).count, srd.count)
        XCTAssertFalse(srd.contains { $0.isCustom })
    }

    func testGoblinStatBlock() throws {
        let goblin = try XCTUnwrap(srd.first { $0.id == "goblin" })
        XCTAssertEqual(goblin.name, "Goblin")
        XCTAssertEqual(goblin.size, .small)
        XCTAssertEqual(goblin.type, .humanoid)
        XCTAssertEqual(goblin.typeLine, "Small humanoid (goblinoid), neutral evil")
        XCTAssertEqual(goblin.armorClassText, "15 (leather armor, shield)")
        XCTAssertEqual(goblin.hitPointsText, "7 (2d6)")
        XCTAssertEqual(goblin.abilityText(.dex), "14 (+2)")
        XCTAssertEqual(goblin.abilityText(.str), "8 (-1)")
        XCTAssertEqual(goblin.skills, "Stealth +6")
        XCTAssertEqual(goblin.challengeRatingText, "1/4")
        XCTAssertEqual(goblin.experience, 50)
        XCTAssertEqual(goblin.summary, "Small humanoid · CR 1/4")
        XCTAssertEqual(goblin.traits.map(\.name), ["Nimble Escape"])
        XCTAssertEqual(goblin.actions.map(\.name), ["Scimitar", "Shortbow"])
    }

    func testDragonHasLegendaryActionsRechargeAndImmunities() throws {
        let dragon = try XCTUnwrap(srd.first { $0.id == "adult-red-dragon" })
        XCTAssertEqual(dragon.size, .huge)
        XCTAssertEqual(dragon.challengeRating, 17)
        XCTAssertEqual(dragon.experience, 18000)
        XCTAssertEqual(dragon.proficiencyBonus, 6)
        XCTAssertEqual(dragon.hitPointsText, "256 (19d12 + 133)")
        XCTAssertEqual(dragon.damageImmunities, "fire")
        XCTAssertTrue(dragon.actions.contains { $0.name == "Fire Breath (Recharge 5–6)" })
        XCTAssertFalse(dragon.legendaryActions.isEmpty)
        XCTAssertTrue(dragon.speed.contains("fly 80 ft."))
    }

    func testSwarmsHaveTheirOwnType() throws {
        let rats = try XCTUnwrap(srd.first { $0.id == "swarm-of-rats" })
        XCTAssertEqual(rats.type, .swarm)
        XCTAssertEqual(rats.typeLine, "Medium swarm of Tiny beasts, unaligned")
    }

    func testEverySRDCreaturePassesValidationUnchanged() throws {
        for creature in srd {
            XCTAssertEqual(try CreatureValidator.validated(creature), creature, creature.id)
        }
    }

    func testEveryTypeHasCreatures() {
        let types = Set(srd.map(\.type))
        XCTAssertEqual(types, Set(CreatureType.allCases))
    }

    // MARK: Challenge rating

    func testChallengeRatingTextXPAndProficiency() {
        XCTAssertEqual(ChallengeRating.text(0.125), "1/8")
        XCTAssertEqual(ChallengeRating.text(0.5), "1/2")
        XCTAssertEqual(ChallengeRating.text(0), "0")
        XCTAssertEqual(ChallengeRating.text(30), "30")
        XCTAssertEqual(ChallengeRating.experience(0), 10)
        XCTAssertEqual(ChallengeRating.experience(1), 200)
        XCTAssertEqual(ChallengeRating.experience(5), 1800)
        XCTAssertEqual(ChallengeRating.experience(30), 155000)
        XCTAssertEqual(ChallengeRating.proficiencyBonus(4), 2)
        XCTAssertEqual(ChallengeRating.proficiencyBonus(5), 3)
        XCTAssertEqual(ChallengeRating.proficiencyBonus(9), 4)
        XCTAssertEqual(ChallengeRating.proficiencyBonus(30), 9)
        XCTAssertEqual(ChallengeRating.all.count, 34)
        XCTAssertFalse(ChallengeRating.isValid(0.3))
    }

    // MARK: Catalog

    func testSectionsGroupByTypeInNameOrder() throws {
        let catalog = CreatureCatalog(baseCreatures: srd)
        let sections = catalog.sections()
        XCTAssertEqual(sections.map(\.type), CreatureType.allCases)
        let dragons = try XCTUnwrap(sections.first { $0.type == .dragon })
        XCTAssertEqual(dragons.creatures.map(\.name), dragons.creatures.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(sections.reduce(0) { $0 + $1.creatures.count }, 334)
    }

    func testSearchByNameTypeSubtypeAndCR() {
        let catalog = CreatureCatalog(baseCreatures: srd)
        let byName = catalog.sections(matching: "owlbear").flatMap(\.creatures).map(\.id)
        XCTAssertEqual(byName, ["owlbear"])
        XCTAssertTrue(catalog.sections(matching: "goblinoid").flatMap(\.creatures).contains { $0.id == "hobgoblin" })
        XCTAssertEqual(catalog.sections(matching: "ooze").map(\.type), [.ooze])
        let quarter = catalog.sections(matching: "CR 1/4").flatMap(\.creatures)
        XCTAssertFalse(quarter.isEmpty)
        XCTAssertTrue(quarter.allSatisfy { $0.challengeRating == 0.25 })
        XCTAssertTrue(catalog.sections(matching: "zzzz").isEmpty)
    }

    func testEditsOverlayAndRemoveRestoresSRD() throws {
        var catalog = CreatureCatalog(baseCreatures: srd)
        var goblin = try XCTUnwrap(catalog.creature(id: "goblin"))
        goblin.hitPoints = 12
        catalog.apply(goblin)
        XCTAssertEqual(catalog.creature(id: "goblin")?.hitPoints, 12)
        XCTAssertTrue(catalog.isEdited("goblin"))
        XCTAssertFalse(catalog.isCustom("goblin"))
        XCTAssertEqual(catalog.count, 334)

        catalog.remove(id: "goblin")
        XCTAssertEqual(catalog.creature(id: "goblin")?.hitPoints, 7)
        XCTAssertFalse(catalog.isEdited("goblin"))
    }

    func testCustomCreaturesAreAddedInNameOrder() throws {
        var catalog = CreatureCatalog(baseCreatures: srd)
        var wyrm = Creature.newCustom(id: "custom-ash-wyrm")
        wyrm.name = "Ash Wyrm"
        wyrm.type = .dragon
        catalog.apply(wyrm)
        XCTAssertEqual(catalog.count, 335)
        XCTAssertTrue(catalog.isCustom("custom-ash-wyrm"))
        XCTAssertFalse(catalog.isEdited("custom-ash-wyrm"))
        XCTAssertEqual(catalog.customCreatures.map(\.id), ["custom-ash-wyrm"])
        let dragons = try XCTUnwrap(catalog.sections().first { $0.type == .dragon }).creatures.map(\.name)
        XCTAssertEqual(dragons.first, "Adult Black Dragon")
        XCTAssertTrue(dragons.contains("Ash Wyrm"))

        catalog.remove(id: "custom-ash-wyrm")
        XCTAssertNil(catalog.creature(id: "custom-ash-wyrm"))
        XCTAssertEqual(catalog.count, 334)
    }

    func testNewCustomCreaturesGetUniqueCustomIds() {
        let a = Creature.newCustom()
        let b = Creature.newCustom()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(a.isCustom)
        XCTAssertTrue(a.id.hasPrefix("custom-"))
    }

    func testCreatureRoundTripsThroughJSON() throws {
        let dragon = try XCTUnwrap(srd.first { $0.id == "adult-red-dragon" })
        let data = try JSONEncoder().encode(dragon)
        XCTAssertEqual(try JSONDecoder().decode(Creature.self, from: data), dragon)
    }

    // MARK: Validation

    func testValidationTidiesText() throws {
        var c = Creature.newCustom(id: "custom-x")
        c.name = "  Bog Hag  "
        c.skills = "   "
        c.alignment = ""
        c.languages = " "
        c.traits = [CreatureFeature(name: "", description: ""), CreatureFeature(name: " Mimicry ", description: " Copies voices. ")]
        let tidy = try CreatureValidator.validated(c)
        XCTAssertEqual(tidy.name, "Bog Hag")
        XCTAssertNil(tidy.skills)
        XCTAssertEqual(tidy.alignment, "unaligned")
        XCTAssertEqual(tidy.languages, "—")
        XCTAssertEqual(tidy.traits, [CreatureFeature(name: "Mimicry", description: "Copies voices.")])
    }

    func testValidationRejectsBadValues() {
        var base = Creature.newCustom(id: "custom-x")
        base.name = "Thing"
        func check(_ error: CreatureValidationError, _ change: (inout Creature) -> Void) {
            var c = base
            change(&c)
            XCTAssertThrowsError(try CreatureValidator.validated(c)) { XCTAssertEqual($0 as? CreatureValidationError, error) }
        }
        check(.emptyName) { $0.name = "   " }
        check(.armorClassOutOfRange) { $0.armorClass = 0 }
        check(.armorClassOutOfRange) { $0.armorClass = 31 }
        check(.hitPointsOutOfRange) { $0.hitPoints = 0 }
        check(.invalidHitDice("lots")) { $0.hitDice = "lots" }
        check(.abilityOutOfRange(.wis)) { $0.abilities.wis = 31 }
        check(.invalidChallengeRating) { $0.challengeRating = 0.3 }
        check(.emptySpeed) { $0.speed = "" }
        check(.unnamedFeature) { $0.actions = [CreatureFeature(name: " ", description: "Bites.")] }
        XCTAssertNoThrow(try CreatureValidator.validated(base))
    }

    func testHitDiceFormats() {
        for ok in ["2d6", "19d12 + 133", "7d8 - 7", "1D4"] { XCTAssertTrue(CreatureValidator.isValidHitDice(ok), ok) }
        for bad in ["d6", "2d", "abc", "2d6 + x"] { XCTAssertFalse(CreatureValidator.isValidHitDice(bad), bad) }
    }
}
