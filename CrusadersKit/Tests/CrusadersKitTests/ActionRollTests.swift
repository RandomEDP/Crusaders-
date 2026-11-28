import XCTest
@testable import CrusadersKit

private let srdItems: ItemCatalog = {
    ItemCatalog(baseItems: (try? SRDItems.load()) ?? [])
}()

private func hero(_ classID: String?, level: Int = 1, str: Int = 10, dex: Int = 10, int: Int = 10,
                  wis: Int = 10, cha: Int = 10) -> PlayerCharacter {
    PlayerCharacter(name: "Hero", race: "", characterClass: "", level: level, classID: classID,
                    baseAbilityScores: AbilityScores(str: str, dex: dex, con: 10, int: int, wis: wis, cha: cha))
}

private func holding(_ character: PlayerCharacter, _ itemID: String) throws -> CharacterSheet {
    let inventory = [InventoryEntry(itemID: itemID, name: itemID, quantity: 1)]
    var loadout = Loadout()
    try loadout.equip(itemID, in: .mainHand, inventory: inventory, catalog: srdItems)
    return CharacterSheet(character: character, gear: EquippedGear(loadout: loadout, inventory: inventory, catalog: srdItems))
}

private func spell(_ id: String) throws -> Spell {
    try XCTUnwrap(RulesCatalog.srd.spells(ids: [id]).first, "SRD spell \(id)")
}

final class DamageDiceTests: XCTestCase {
    func testReadsWeaponAndSheetDamage() {
        XCTAssertEqual(DamageDice("1d8 + 3 slashing"), DamageDice(count: 1, sides: 8, bonus: 3))
        XCTAssertEqual(DamageDice("1d4+1"), DamageDice(count: 1, sides: 4, bonus: 1))
        XCTAssertEqual(DamageDice("1d6-1"), DamageDice(count: 1, sides: 6, bonus: -1))
        XCTAssertEqual(DamageDice("1d4 − 1 piercing"), DamageDice(count: 1, sides: 4, bonus: -1))
        XCTAssertEqual(DamageDice("2d6"), DamageDice(count: 2, sides: 6))
        XCTAssertEqual(DamageDice("1d8 + 1d6 + 2"),
                       DamageDice(terms: [.init(count: 1, sides: 8), .init(count: 1, sides: 6)], bonus: 2))
        XCTAssertEqual(DamageDice("1"), DamageDice(terms: [], bonus: 1))
        XCTAssertEqual(DamageDice("0")?.isZero, true)
        XCTAssertNil(DamageDice("DC 12"))
        XCTAssertNil(DamageDice(""))
    }

    func testTextDoublingAndRolling() throws {
        let dice = DamageDice(count: 2, sides: 6, bonus: 3)
        XCTAssertEqual(dice.text, "2d6 + 3")
        XCTAssertEqual(dice.doubled.text, "4d6 + 3", "A critical doubles the dice, not the bonus")
        let rolled = dice.roll(using: .sequence([4, 2]))
        XCTAssertEqual(rolled.faces, [4, 2])
        XCTAssertEqual(rolled.total, 9)
        XCTAssertEqual(rolled.breakdown, "2d6: [4, 2] + 3")
        XCTAssertEqual(DamageDice(count: 1, sides: 4, bonus: -3).roll(using: .sequence([1])).total, 0, "Never below zero")
        XCTAssertEqual(DamageDice(count: 1, sides: 6).adding(DamageDice(count: 2, sides: 6, bonus: 1)).text, "3d6 + 1")
    }

    func testAdvantageKeepsTheHigherDieAndDisadvantageTheLower() {
        let advantage = D20Roll.roll(bonus: 5, mode: .advantage, using: .sequence([7, 15]))
        XCTAssertEqual(advantage.natural, 15)
        XCTAssertEqual(advantage.total, 20)
        XCTAssertEqual(advantage.breakdown, "20 (advantage 7, 15, kept 15 + 5)")
        let disadvantage = D20Roll.roll(bonus: 5, mode: .disadvantage, using: .sequence([7, 15]))
        XCTAssertEqual(disadvantage.total, 12)
        let normal = D20Roll.roll(bonus: -1, mode: .normal, using: .sequence([20]))
        XCTAssertTrue(normal.isCritical)
        XCTAssertEqual(normal.breakdown, "19 (d20: 20 − 1)")
    }
}

final class AttackRollTests: XCTestCase {
    func testWeaponAttacksCarryTheirDiceAndAmmunition() throws {
        let ranger = hero("ranger", dex: 16)
        let longbow = try XCTUnwrap(try holding(ranger, "longbow").attacks.first)
        XCTAssertEqual(longbow.damageDice, DamageDice(count: 1, sides: 8, bonus: 3))
        XCTAssertEqual(longbow.damageType, .piercing)
        XCTAssertEqual(longbow.ammunition, .arrow)
        XCTAssertTrue(longbow.notes.contains("Uses 1 of your arrows each attack"))

        XCTAssertEqual(try holding(ranger, "light-crossbow").attacks.first?.ammunition, .bolt)
        XCTAssertEqual(try holding(ranger, "sling").attacks.first?.ammunition, .bullet)
        XCTAssertEqual(try holding(ranger, "blowgun").attacks.first?.ammunition, .needle)
        XCTAssertNil(try holding(ranger, "longsword").attacks.first?.ammunition)
        XCTAssertNil(try holding(ranger, "dagger").attacks.first?.ammunition, "Thrown weapons don't use ammunition")

        let unarmed = try XCTUnwrap(CharacterSheet(character: hero("fighter", str: 14)).attacks.first)
        XCTAssertEqual(unarmed.damageDice, DamageDice(terms: [], bonus: 3), "1 + Strength")
    }

    func testRollingAHit() throws {
        let attack = AttackOption(try XCTUnwrap(try holding(hero("ranger", dex: 16), "longbow").attacks.first))
        let result = attack.roll(using: .sequence([12, 6]))
        XCTAssertEqual(result.toHit?.total, 17, "12 + Dex 3 + proficiency 2")
        XCTAssertEqual(result.damage?.total, 9)
        XCTAssertEqual(result.chatText(characterName: "Thalia", ammoName: "Arrows", ammoLeft: 19), """
        ⚔️ Thalia attacks with Longbow
        To hit: 17 (d20: 12 + 5)
        Damage: 9 piercing (1d8: [6] + 3)
        Arrows: 19 left
        """)
    }

    func testANatural20DoublesTheDiceAndANatural1Misses() throws {
        let attack = AttackOption(id: "a", name: "Greatsword", attackBonus: 5, damage: DamageDice(count: 2, sides: 6, bonus: 3),
                                  damageType: "slashing")
        let critical = attack.roll(using: .sequence([20, 1, 2, 3, 4]))
        XCTAssertTrue(critical.toHit?.isCritical ?? false)
        XCTAssertEqual(critical.damage?.faces, [1, 2, 3, 4])
        XCTAssertEqual(critical.damage?.total, 13)
        XCTAssertTrue(critical.chatText(characterName: "Bo").contains("Critical hit!"))

        let fumble = attack.roll(using: .sequence([1, 6, 6]))
        XCTAssertNil(fumble.damage)
        XCTAssertTrue(fumble.chatText(characterName: "Bo").contains("Natural 1: a miss."))
    }

    func testMagicAmmunitionAddsToHitAndDamage() {
        let attack = AttackOption(id: "a", name: "Longbow", attackBonus: 5, damage: DamageDice(count: 1, sides: 8, bonus: 3),
                                  damageType: "piercing", ammunition: .arrow)
        let result = attack.roll(extraBonus: 2, using: .sequence([10, 4]))
        XCTAssertEqual(result.toHit?.total, 17)
        XCTAssertEqual(result.damage?.total, 9)
    }

    func testImportedAttacksRollFromTheirPrintedNumbers() throws {
        var sheet = ImportedSheet()
        sheet.attacks = [
            .init(name: "Dagger", attackBonus: 3, damage: "1d4+1", damageType: "Piercing"),
            .init(name: "Shortbow", attackBonus: 4, damage: "1d6+2", damageType: "Piercing"),
            .init(name: "Breath", saveText: "DC 12", damage: "1d10", damageType: "Acid")
        ]
        var character = hero(nil)
        character.importedSheet = sheet
        let options = CharacterSheet(character: character).attackOptions
        XCTAssertEqual(options.map(\.name), ["Dagger", "Shortbow", "Breath"])
        XCTAssertEqual(options[0].damage, DamageDice(count: 1, sides: 4, bonus: 1))
        XCTAssertEqual(options[0].damageType, "piercing")
        XCTAssertNil(options[0].ammunition)
        XCTAssertEqual(options[1].ammunition, .arrow)

        let save = options[2].roll(using: .sequence([7]))
        XCTAssertNil(save.toHit)
        XCTAssertEqual(save.chatText(characterName: "Omi"), "⚔️ Omi attacks with Breath\nSave: DC 12\nDamage: 7 acid (1d10: [7])")
    }
}

final class AmmunitionTests: XCTestCase {
    func testWeaponsAndAmmunitionMatchByKind() {
        XCTAssertEqual(AmmoKind.fired(byWeaponNamed: "Longbow"), .arrow)
        XCTAssertEqual(AmmoKind.fired(byWeaponNamed: "Shortbow, +1"), .arrow)
        XCTAssertEqual(AmmoKind.fired(byWeaponNamed: "Hand Crossbow"), .bolt)
        XCTAssertEqual(AmmoKind.fired(byWeaponNamed: "Sling"), .bullet)
        XCTAssertEqual(AmmoKind.fired(byWeaponNamed: "Blowgun"), .needle)
        XCTAssertNil(AmmoKind.fired(byWeaponNamed: "Rainbow Staff"))
        XCTAssertNil(AmmoKind.fired(byWeaponNamed: "Dagger"))
        XCTAssertEqual(AmmoKind.of(itemNamed: "Arrows"), .arrow)
        XCTAssertEqual(AmmoKind.of(itemNamed: "Crossbow Bolts"), .bolt)
        XCTAssertEqual(AmmoKind.of(itemNamed: "Arrow of Slaying"), .arrow)
    }

    func testStacksThatFitAWeaponOrdinaryFirst() {
        let inventory = [
            InventoryEntry(itemID: "ammunition-plus-1", name: "Ammunition, +1", quantity: 5),
            InventoryEntry(itemID: "arrows", name: "Arrows", quantity: 20),
            InventoryEntry(itemID: "crossbow-bolts", name: "Crossbow Bolts", quantity: 10),
            InventoryEntry(itemID: "arrow-catching-shield", name: "Arrow-Catching Shield", quantity: 1)
        ]
        let stacks = AmmoStack.stacks(for: .arrow, in: inventory, catalog: srdItems)
        XCTAssertEqual(stacks.map(\.itemID), ["arrows", "ammunition-plus-1"])
        XCTAssertEqual(stacks.map(\.bonus), [0, 1])
        XCTAssertEqual(AmmoStack.stacks(for: .bolt, in: inventory, catalog: srdItems).map(\.itemID),
                       ["crossbow-bolts", "ammunition-plus-1"])
        XCTAssertEqual(AmmoStack.stacks(for: .bullet, in: inventory, catalog: srdItems).map(\.itemID), ["ammunition-plus-1"])
        XCTAssertTrue(AmmoStack.stacks(for: .needle, in: [inventory[1]], catalog: srdItems).isEmpty)
    }

    func testBundlesGoIntoTheInventoryAsSinglePieces() throws {
        let arrows = try XCTUnwrap(srdItems.item(id: "arrows"))
        XCTAssertEqual(arrows.ammunitionBundleSize, 20)
        XCTAssertEqual(arrows.inventoryName, "Arrows")
        XCTAssertEqual(arrows.inventoryQuantity(for: 2), 40)
        let needles = try XCTUnwrap(srdItems.item(id: "blowgun-needles"))
        XCTAssertEqual(needles.inventoryQuantity(for: 1), 50)
        let longbow = try XCTUnwrap(srdItems.item(id: "longbow"))
        XCTAssertNil(longbow.ammunitionBundleSize)
        XCTAssertEqual(longbow.inventoryQuantity(for: 1), 1)
        XCTAssertEqual(longbow.inventoryName, "Longbow")
    }
}

final class SpellCastingTests: XCTestCase {
    func testReadsAttackSaveDamageAndHealingFromSpellText() throws {
        let fireBolt = SpellDice(spell: try spell("fire-bolt"))
        XCTAssertEqual(fireBolt.attack, .ranged)
        XCTAssertEqual(fireBolt.damage, DamageDice(count: 1, sides: 10))
        XCTAssertEqual(fireBolt.damageType, "fire")
        XCTAssertTrue(fireBolt.cantripScales)

        let fireball = SpellDice(spell: try spell("fireball"))
        XCTAssertNil(fireball.attack)
        XCTAssertEqual(fireball.save, .dex)
        XCTAssertEqual(fireball.damage, DamageDice(count: 8, sides: 6))
        XCTAssertEqual(fireball.perSlotAbove, DamageDice(count: 1, sides: 6))

        let cure = SpellDice(spell: try spell("cure-wounds"))
        XCTAssertEqual(cure.healing, DamageDice(count: 1, sides: 8))
        XCTAssertTrue(cure.healingAddsModifier)
        XCTAssertEqual(cure.perSlotAbove, DamageDice(count: 1, sides: 8))

        XCTAssertEqual(SpellDice(spell: try spell("magic-missile")).damage, DamageDice(count: 1, sides: 4, bonus: 1))
        XCTAssertEqual(SpellDice(spell: try spell("shocking-grasp")).attack, .melee)
        XCTAssertEqual(SpellDice(spell: try spell("sacred-flame")).save, .dex)
    }

    func testCantripsGrowWithLevelAndUpcastingAddsDice() throws {
        let wizard = CharacterSheet(character: hero("wizard", level: 5, int: 16))
        let fireBolt = wizard.cast(try spell("fire-bolt"), slotLevel: nil)
        XCTAssertNil(fireBolt.slotLevel)
        XCTAssertEqual(fireBolt.damage, DamageDice(count: 2, sides: 10), "2d10 at 5th level")
        XCTAssertEqual(fireBolt.attackBonus, 6, "Int 3 + proficiency 3")

        let fireball = wizard.cast(try spell("fireball"), slotLevel: 4)
        XCTAssertEqual(fireball.damage, DamageDice(count: 9, sides: 6))
        XCTAssertEqual(fireball.saveText, "DC 14 Dexterity save")
        XCTAssertNil(fireball.attackBonus, "Fireball has no attack roll")

        let cleric = CharacterSheet(character: hero("cleric", level: 3, wis: 16))
        let cure = cleric.cast(try spell("cure-wounds"), slotLevel: 2)
        XCTAssertEqual(cure.healing, DamageDice(count: 2, sides: 8, bonus: 3))
        let result = cure.roll(using: .sequence([5, 4]))
        XCTAssertEqual(result.healing?.total, 12)
        XCTAssertEqual(result.chatText(characterName: "Brother Tam", slotsLeft: 1), """
        ✨ Brother Tam casts Cure Wounds (2nd-level slot, 1 left)
        Healing: 12 HP (2d8: [5, 4] + 3)
        """)
    }

    func testSpendingSlotsStopsAtTheMaximumAndRestsBringThemBack() throws {
        var wizard = hero("wizard", level: 3, int: 16)
        let sheet = CharacterSheet(character: wizard)
        XCTAssertEqual(Array(sheet.spellSlotMaximums.prefix(3)), [4, 2, 0])
        XCTAssertEqual(sheet.castingLevels(forSpellLevel: 1), [SlotLevel(level: 1, left: 4), SlotLevel(level: 2, left: 2)])

        try wizard.spendSpellSlot(level: 2, maximum: 2)
        try wizard.spendSpellSlot(level: 2, maximum: 2)
        XCTAssertThrowsError(try wizard.spendSpellSlot(level: 2, maximum: 2)) { error in
            XCTAssertEqual(error as? ActionError, .noSpellSlot(level: 2))
        }
        XCTAssertEqual(CharacterSheet(character: wizard).spellSlotsLeft(atLevel: 2), 0)
        XCTAssertEqual(CharacterSheet(character: wizard).castingLevels(forSpellLevel: 2), [SlotLevel(level: 2, left: 0)])

        wizard.restoreSpellSlot(level: 2)
        XCTAssertEqual(wizard.spellSlotsUsed(atLevel: 2), 1)
        wizard.rest(long: false)
        XCTAssertEqual(wizard.spellSlotsUsed(atLevel: 2), 1, "A short rest doesn't bring a wizard's slots back")
        wizard.rest(long: true)
        XCTAssertEqual(wizard.spellSlotsUsed(atLevel: 2), 0)

        var warlock = hero("warlock", level: 2, cha: 16)
        XCTAssertTrue(warlock.usesPactMagic)
        let pact = try XCTUnwrap(CharacterSheet(character: warlock).castingLevels(forSpellLevel: 1).first)
        try warlock.spendSpellSlot(level: pact.level, maximum: pact.left)
        warlock.rest(long: false)
        XCTAssertEqual(warlock.spellSlotsUsed(atLevel: pact.level), 0, "Pact Magic comes back on a short rest")
    }

    func testImportedSheetsUseTheirPrintedSlotsAndNumbers() throws {
        var sheet = ImportedSheet()
        sheet.classes = [.init(name: "Sorcerer", level: 4)]
        sheet.spellSlots = [.init(level: 1, slots: 4), .init(level: 2, slots: 3)]
        sheet.spellcasting = [.init(className: "Sorcerer", ability: .cha, saveDC: 12, attackBonus: 4)]
        sheet.abilities = [.init(ability: .cha, score: 14, modifier: 2)]
        var character = hero(nil)
        character.importedSheet = sheet
        let caster = CharacterSheet(character: character)
        XCTAssertEqual(Array(caster.spellSlotMaximums.prefix(3)), [4, 3, 0])
        XCTAssertEqual(caster.casterLevel, 4)
        XCTAssertFalse(character.usesPactMagic)

        let ray = caster.cast(try spell("ray-of-frost"), slotLevel: nil)
        XCTAssertEqual(ray.attackBonus, 4)
        XCTAssertEqual(ray.damage, DamageDice(count: 1, sides: 8))

        let homebrew = caster.cast(imported: .init(name: "Witch Bolt", level: 1, saveOrAttack: "+4"), slotLevel: nil)
        XCTAssertEqual(homebrew.slotLevel, 1)
        XCTAssertEqual(homebrew.attackBonus, 4)
        let saving = caster.cast(imported: .init(name: "Charm", level: 1, saveOrAttack: "WIS 12"), slotLevel: 2)
        XCTAssertEqual(saving.saveText, "DC 12 WIS save")
        XCTAssertEqual(saving.slotLevel, 2)
    }

    func testSpentSlotsAreSavedWithTheCharacter() throws {
        var wizard = hero("wizard", level: 3)
        try wizard.spendSpellSlot(level: 1, maximum: 4)
        let decoded = try JSONDecoder().decode(PlayerCharacter.self, from: JSONEncoder().encode(wizard))
        XCTAssertEqual(decoded.spellSlotsUsed(atLevel: 1), 1)

        // Characters saved before slots were tracked load with nothing spent.
        let old = #"{"id":"\#(UUID().uuidString)","name":"Old","race":"","characterClass":"","level":1}"#
        let legacy = try JSONDecoder().decode(PlayerCharacter.self, from: Data(old.utf8))
        XCTAssertEqual(legacy.spellSlotsUsed, Array(repeating: 0, count: 9))
    }
}

final class AbilityUseTests: XCTestCase {
    func testUsingAnAbilityRollsTheDiceInItsDetail() throws {
        let breath = CharacterResource(name: "Breath Weapon", uses: 2, recharge: "Long Rest", detail: "DC 12 Dex, 1d10 Acid")
        XCTAssertEqual(breath.detailDice, DamageDice(count: 1, sides: 10))
        XCTAssertEqual(breath.useText(characterName: "Omi", remaining: 1, roller: .sequence([7])), """
        🔥 Omi uses Breath Weapon (1 of 2 left)
        DC 12 Dex, 1d10 Acid
        Roll: 7 acid (1d10: [7])
        """)
        let points = CharacterResource(name: "Sorcery Points", uses: 4)
        XCTAssertEqual(points.useText(characterName: "Omi", remaining: 3, roller: .sequence([1])),
                       "🔥 Omi uses Sorcery Points (3 of 4 left)")
    }

    func testAbilitiesCantBeUsedWithNoUsesLeft() throws {
        var character = hero(nil)
        let breath = CharacterResource(name: "Breath Weapon", uses: 1)
        character.resources = [breath]
        let used = try character.spendResource(breath.id)
        XCTAssertEqual(used.remaining, 0)
        XCTAssertThrowsError(try character.spendResource(breath.id)) { error in
            XCTAssertEqual(error as? ActionError, .noUsesLeft(name: "Breath Weapon"))
        }
        character.rest(long: true)
        XCTAssertEqual(character.resources.first?.remaining, 1)
    }
}
