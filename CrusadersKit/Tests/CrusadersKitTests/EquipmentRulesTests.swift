import XCTest
@testable import CrusadersKit

/// The SRD items, loaded once.
private let srdCatalog: ItemCatalog = {
    ItemCatalog(baseItems: (try? SRDItems.load()) ?? [])
}()

private func bag(_ items: [String: Int]) -> [InventoryEntry] {
    items.sorted { $0.key < $1.key }.map { InventoryEntry(itemID: $0.key, name: $0.key, quantity: $0.value) }
}

private func hero(_ classID: String?, race: String? = nil, subrace: String? = nil, level: Int = 1,
                  str: Int = 10, dex: Int = 10, con: Int = 10, int: Int = 10, wis: Int = 10, cha: Int = 10) -> PlayerCharacter {
    PlayerCharacter(name: "Hero", race: "", characterClass: "", level: level, raceID: race, subraceID: subrace,
                    classID: classID,
                    baseAbilityScores: AbilityScores(str: str, dex: dex, con: con, int: int, wis: wis, cha: cha))
}

/// A sheet for a character holding `items`, after `setup` equips some of them.
private func sheet(_ character: PlayerCharacter, items: [String: Int],
                   _ setup: (inout Loadout, [InventoryEntry]) throws -> Void) rethrows -> CharacterSheet {
    let inventory = bag(items)
    var loadout = Loadout()
    try setup(&loadout, inventory)
    return CharacterSheet(character: character,
                          gear: EquippedGear(loadout: loadout, inventory: inventory, catalog: srdCatalog))
}

/// A sheet for a character carrying `items` with nothing equipped.
private func sheet(_ character: PlayerCharacter, items: [String: Int]) -> CharacterSheet {
    CharacterSheet(character: character,
                   gear: EquippedGear(loadout: Loadout(), inventory: bag(items), catalog: srdCatalog))
}

final class LoadoutRulesTests: XCTestCase {
    private let catalog = srdCatalog

    func testCatalogHasTheItemsTheseTestsUse() {
        for id in ["chain-mail", "plate", "shield", "longsword", "greatsword", "dagger", "armor-plus-1", "holy-avenger"] {
            XCTAssertNotNil(catalog.item(id: id), id)
        }
    }

    func testOneSuitOfArmourAtATimeAndWearingNewArmourSwapsIt() throws {
        let inventory = bag(["leather": 1, "chain-mail": 1])
        var loadout = Loadout()
        try loadout.equip("leather", in: .armour, inventory: inventory, catalog: catalog)
        try loadout.equip("chain-mail", in: .armour, inventory: inventory, catalog: catalog)
        XCTAssertEqual(loadout.armourID, "chain-mail")
        XCTAssertFalse(loadout.isEquipped("leather"))
    }

    func testItemsGoOnlyInTheirSlot() {
        let inventory = bag(["chain-mail": 1, "shield": 1, "potion-of-healing": 1, "longsword": 1])
        var loadout = Loadout()
        XCTAssertThrowsError(try loadout.equip("chain-mail", in: .mainHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .wrongSlot)
        }
        XCTAssertThrowsError(try loadout.equip("shield", in: .armour, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .wrongSlot)
        }
        XCTAssertThrowsError(try loadout.equip("longsword", in: .shield, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .wrongSlot)
        }
        XCTAssertThrowsError(try loadout.equip("potion-of-healing", in: .mainHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .notEquippable)
        }
        XCTAssertThrowsError(try loadout.equip("plate", in: .armour, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .notInInventory)
        }
    }

    func testTwoHandedWeaponsAndShieldsDontMix() throws {
        let inventory = bag(["greatsword": 1, "shield": 1, "dagger": 1])
        var loadout = Loadout()
        try loadout.equip("greatsword", in: .mainHand, inventory: inventory, catalog: catalog)
        XCTAssertThrowsError(try loadout.equip("shield", in: .shield, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .handsFull(blockedBy: "Greatsword"))
        }
        XCTAssertThrowsError(try loadout.equip("dagger", in: .offHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .handsFull(blockedBy: "Greatsword"))
        }
        XCTAssertThrowsError(try loadout.equip("greatsword", in: .offHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .wrongSlot, "two-handed weapons only go in the main hand")
        }

        var shielded = Loadout()
        try shielded.equip("shield", in: .shield, inventory: inventory, catalog: catalog)
        XCTAssertThrowsError(try shielded.equip("greatsword", in: .mainHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .needsBothHands(blockedBy: "Shield"))
        }
        XCTAssertThrowsError(try shielded.equip("dagger", in: .offHand, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .handsFull(blockedBy: "Shield"))
        }
        try shielded.equip("dagger", in: .mainHand, inventory: inventory, catalog: catalog)
        XCTAssertEqual(shielded.mainHandID, "dagger")
        XCTAssertEqual(shielded.shieldID, "shield")
    }

    func testOneDaggerMovesBetweenHandsButTwoFillBoth() throws {
        var loadout = Loadout()
        let one = bag(["dagger": 1])
        try loadout.equip("dagger", in: .mainHand, inventory: one, catalog: catalog)
        try loadout.equip("dagger", in: .offHand, inventory: one, catalog: catalog)
        XCTAssertNil(loadout.mainHandID)
        XCTAssertEqual(loadout.offHandID, "dagger")

        var pair = Loadout()
        let two = bag(["dagger": 2])
        try pair.equip("dagger", in: .mainHand, inventory: two, catalog: catalog)
        try pair.equip("dagger", in: .offHand, inventory: two, catalog: catalog)
        XCTAssertEqual(pair.slots(of: "dagger"), [.mainHand, .offHand])
    }

    func testVersatileWeaponsSwitchToBothHandsOnlyWithAFreeHand() throws {
        let inventory = bag(["longsword": 1, "shield": 1, "dagger": 1])
        var loadout = Loadout()
        try loadout.equip("longsword", in: .mainHand, inventory: inventory, catalog: catalog)
        try loadout.setUsesBothHands(true, catalog: catalog)
        XCTAssertTrue(loadout.usesBothHands)
        XCTAssertThrowsError(try loadout.equip("shield", in: .shield, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .handsFull(blockedBy: "Longsword"))
        }
        try loadout.setUsesBothHands(false, catalog: catalog)
        try loadout.equip("shield", in: .shield, inventory: inventory, catalog: catalog)
        XCTAssertThrowsError(try loadout.setUsesBothHands(true, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .needsBothHands(blockedBy: "Shield"))
        }

        var daggerOnly = Loadout()
        try daggerOnly.equip("dagger", in: .mainHand, inventory: inventory, catalog: catalog)
        XCTAssertThrowsError(try daggerOnly.setUsesBothHands(true, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .notVersatile)
        }
    }

    func testUnequipFreesTheSlot() throws {
        let inventory = bag(["longsword": 1])
        var loadout = Loadout()
        try loadout.equip("longsword", in: .mainHand, inventory: inventory, catalog: catalog)
        try loadout.setUsesBothHands(true, catalog: catalog)
        loadout.unequip("longsword")
        XCTAssertNil(loadout.mainHandID)
        XCTAssertFalse(loadout.usesBothHands)
    }

    func testMagicArmourAsksWhichArmourItIs() throws {
        let inventory = bag(["armor-plus-1": 1, "dwarven-plate": 1, "mithral-armor": 1])
        var loadout = Loadout()
        XCTAssertThrowsError(try loadout.equip("armor-plus-1", in: .armour, inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .needsBaseItem)
        }
        XCTAssertThrowsError(try loadout.equip("armor-plus-1", in: .armour, base: "longsword", inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .invalidBaseItem)
        }
        try loadout.equip("armor-plus-1", in: .armour, base: "chain-mail", inventory: inventory, catalog: catalog)
        XCTAssertEqual(loadout.baseItemIDs["armor-plus-1"], "chain-mail")
        XCTAssertEqual(loadout.gear("armor-plus-1", catalog: catalog)?.name, "Armor, +1 (Chain Mail)")

        // Items made from exactly one thing pick it themselves.
        try loadout.equip("dwarven-plate", in: .armour, inventory: inventory, catalog: catalog)
        XCTAssertEqual(loadout.gear("dwarven-plate", catalog: catalog)?.base?.id, "plate")

        let mithralOptions = GearItem.baseOptions(for: try XCTUnwrap(catalog.item(id: "mithral-armor")), in: catalog).map(\.id)
        XCTAssertFalse(mithralOptions.contains("hide"))
        XCTAssertFalse(mithralOptions.contains("leather"))
        XCTAssertTrue(mithralOptions.contains("half-plate"))
        XCTAssertTrue(mithralOptions.contains("plate"))
    }

    func testMagicSwordsOnlyComeAsSwords() throws {
        let options = GearItem.baseOptions(for: try XCTUnwrap(catalog.item(id: "vorpal-sword")), in: catalog).map(\.id)
        XCTAssertEqual(Set(options), ["longsword", "greatsword", "scimitar"])
        XCTAssertEqual(GearItem.baseOptions(for: try XCTUnwrap(catalog.item(id: "longsword")), in: catalog), [])
    }

    func testAtMostThreeAttunedItems() throws {
        let inventory = bag(["holy-avenger": 1, "luck-blade": 1, "berserker-axe": 1, "flame-tongue": 1, "potion-of-healing": 1])
        var loadout = Loadout()
        try loadout.attune("holy-avenger", inventory: inventory, catalog: catalog)
        try loadout.attune("luck-blade", inventory: inventory, catalog: catalog)
        try loadout.attune("berserker-axe", inventory: inventory, catalog: catalog)
        XCTAssertThrowsError(try loadout.attune("flame-tongue", inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .attunementFull)
        }
        XCTAssertThrowsError(try loadout.attune("potion-of-healing", inventory: inventory, catalog: catalog)) {
            XCTAssertEqual($0 as? EquipError, .noAttunementNeeded)
        }
        loadout.endAttunement("luck-blade")
        try loadout.attune("flame-tongue", inventory: inventory, catalog: catalog)
        XCTAssertEqual(loadout.attunedIDs, ["holy-avenger", "berserker-axe", "flame-tongue"])
    }

    func testItemsNoLongerInTheInventoryDropOff() throws {
        var loadout = Loadout()
        let full = bag(["chain-mail": 1, "shield": 1, "holy-avenger": 1])
        try loadout.equip("chain-mail", in: .armour, inventory: full, catalog: catalog)
        try loadout.equip("shield", in: .shield, inventory: full, catalog: catalog)
        try loadout.equip("holy-avenger", in: .mainHand, base: "longsword", inventory: full, catalog: catalog)
        try loadout.attune("holy-avenger", inventory: full, catalog: catalog)

        let clean = loadout.sanitized(inventory: bag(["shield": 1]), catalog: catalog)
        XCTAssertNil(clean.armourID)
        XCTAssertNil(clean.mainHandID)
        XCTAssertEqual(clean.shieldID, "shield")
        XCTAssertEqual(clean.attunedIDs, [])
        XCTAssertEqual(clean.baseItemIDs, [:])
    }

    func testLoadoutJSONFromAnOlderAppStillLoads() throws {
        let loadout = try JSONDecoder().decode(Loadout.self, from: Data(#"{"armourID":"leather"}"#.utf8))
        XCTAssertEqual(loadout, Loadout(armourID: "leather"))
    }
}

final class EquippedCharacterSheetTests: XCTestCase {
    // MARK: Armor Class

    func testUnarmouredACIsTenPlusDex() {
        XCTAssertEqual(sheet(hero("fighter", dex: 14), items: [:]).armorClass, 12)
    }

    func testChainMailAndShield() throws {
        let fighter = hero("fighter", str: 15, dex: 14)
        let armoured = try sheet(fighter, items: ["chain-mail": 1, "shield": 1]) { loadout, inventory in
            try loadout.equip("chain-mail", in: .armour, inventory: inventory, catalog: srdCatalog)
            try loadout.equip("shield", in: .shield, inventory: inventory, catalog: srdCatalog)
        }
        XCTAssertEqual(armoured.armorClass, 18, "chain mail 16 ignores Dex, shield +2")
        XCTAssertEqual(armoured.armorClassParts.map(\.name), ["Chain Mail", "Shield"])
        XCTAssertTrue(armoured.hasStealthDisadvantage)
        XCTAssertEqual(armoured.speed, 30)
        XCTAssertEqual(armoured.equipmentWarnings, [])
    }

    func testLightArmourAddsDexAndMediumCapsItAtTwo() throws {
        let nimble = hero("fighter", dex: 16)
        let leather = try sheet(nimble, items: ["leather": 1]) {
            try $0.equip("leather", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(leather.armorClass, 14)
        XCTAssertFalse(leather.hasStealthDisadvantage)
        let halfPlate = try sheet(nimble, items: ["half-plate": 1]) {
            try $0.equip("half-plate", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(halfPlate.armorClass, 17, "15 + Dex capped at 2")
        XCTAssertTrue(halfPlate.hasStealthDisadvantage)
    }

    func testUnarmoredDefense() throws {
        let barbarian = hero("barbarian", dex: 14, con: 16)
        XCTAssertEqual(sheet(barbarian, items: [:]).armorClass, 15)
        let shielded = try sheet(barbarian, items: ["shield": 1]) {
            try $0.equip("shield", in: .shield, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(shielded.armorClass, 17, "barbarians keep Unarmored Defense with a shield")

        let monk = hero("monk", dex: 16, wis: 14)
        XCTAssertEqual(sheet(monk, items: [:]).armorClass, 15)
        let monkWithShield = try sheet(monk, items: ["shield": 1]) {
            try $0.equip("shield", in: .shield, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(monkWithShield.armorClass, 15, "monks lose Unarmored Defense with a shield: 10 + 3 + 2")

        let sorcerer = hero("sorcerer", dex: 14)
        XCTAssertEqual(sheet(sorcerer, items: [:]).armorClass, 15, "Draconic Resilience: 13 + Dex")
    }

    func testMagicArmourAndShieldBonuses() throws {
        let fighter = hero("fighter", str: 15)
        let magic = try sheet(fighter, items: ["armor-plus-2": 1, "shield-plus-1": 1]) {
            try $0.equip("armor-plus-2", in: .armour, base: "plate", inventory: $1, catalog: srdCatalog)
            try $0.equip("shield-plus-1", in: .shield, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(magic.armorClass, 18 + 2 + 2 + 1)
    }

    // MARK: Strength, Stealth and proficiency

    func testHeavyArmourWithoutTheStrengthSlowsYouDown() throws {
        let weak = hero("fighter", str: 13)
        let plate = try sheet(weak, items: ["plate": 1]) {
            try $0.equip("plate", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(plate.armourSpeedPenalty, 10)
        XCTAssertEqual(plate.speed, 20)
        XCTAssertEqual(plate.equipmentWarnings, ["Plate needs Strength 15: speed is 10 feet slower."])

        let chain = try sheet(weak, items: ["chain-mail": 1]) {
            try $0.equip("chain-mail", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(chain.speed, 30, "chain mail needs Strength 13")

        let dwarf = hero("fighter", race: "dwarf", subrace: "hill-dwarf", str: 10)
        let dwarfInPlate = try sheet(dwarf, items: ["plate": 1]) {
            try $0.equip("plate", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(dwarfInPlate.speed, 25, "dwarves aren't slowed by heavy armour")
    }

    func testMithralHasNoStrengthRequirementOrStealthDisadvantage() throws {
        let weak = hero("fighter", str: 8)
        let mithral = try sheet(weak, items: ["mithral-armor": 1]) {
            try $0.equip("mithral-armor", in: .armour, base: "plate", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(mithral.armorClass, 18)
        XCTAssertEqual(mithral.speed, 30)
        XCTAssertFalse(mithral.hasStealthDisadvantage)
    }

    func testArmourWithoutProficiencyIsFlagged() throws {
        let wizard = hero("wizard", str: 15)
        let armoured = try sheet(wizard, items: ["chain-mail": 1]) {
            try $0.equip("chain-mail", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(armoured.unproficientArmour.map(\.id), ["chain-mail"])
        XCTAssertTrue(armoured.equipmentWarnings.first?.hasPrefix("Not proficient with Chain Mail") ?? false)
        XCTAssertTrue(armoured.attacks.first?.notes.contains("Disadvantage: armour you aren't proficient with") ?? false)

        let elven = try sheet(wizard, items: ["elven-chain": 1]) {
            try $0.equip("elven-chain", in: .armour, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(elven.unproficientArmour, [], "Elven Chain counts as proficient")
        XCTAssertEqual(elven.armorClass, 13 + 1)

        XCTAssertTrue(sheet(hero("barbarian"), items: [:]).isProficient(withArmour: .medium))
        XCTAssertFalse(sheet(hero("barbarian"), items: [:]).isProficient(withArmour: .heavy))
        XCTAssertTrue(sheet(hero("paladin"), items: [:]).isProficient(withArmour: .heavy))
        XCTAssertTrue(sheet(hero(nil), items: [:]).isProficient(withArmour: .heavy), "old characters without a class aren't nagged")
    }

    // MARK: Attacks

    func testUnarmedStrikeWhenNothingIsHeld() {
        let attacks = sheet(hero("fighter", str: 16), items: [:]).attacks
        XCTAssertEqual(attacks.map(\.name), ["Unarmed strike"])
        XCTAssertEqual(attacks.first?.attackBonus, 5)
        XCTAssertEqual(attacks.first?.damage, "1 + 3 bludgeoning")
    }

    func testLongswordOneAndTwoHanded() throws {
        let fighter = hero("fighter", str: 16)
        var held = try sheet(fighter, items: ["longsword": 1]) {
            try $0.equip("longsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(held.attacks.count, 1)
        XCTAssertEqual(held.attacks.first?.attackBonus, 5)
        XCTAssertEqual(held.attacks.first?.damage, "1d8 + 3 slashing")

        held = try sheet(fighter, items: ["longsword": 1]) {
            try $0.equip("longsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
            try $0.setUsesBothHands(true, catalog: srdCatalog)
        }
        XCTAssertEqual(held.attacks.first?.damage, "1d10 + 3 slashing")
        XCTAssertTrue(held.attacks.first?.notes.contains("Versatile: using both hands") ?? false)
    }

    func testFinesseAndRangedWeaponsUseDexterity() throws {
        let rogue = hero("rogue", str: 8, dex: 16)
        let rapier = try sheet(rogue, items: ["rapier": 1]) {
            try $0.equip("rapier", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(rapier.attacks.first?.attackBonus, 5)
        XCTAssertEqual(rapier.attacks.first?.damage, "1d8 + 3 piercing")

        let ranger = hero("ranger", str: 8, dex: 16)
        let longbow = try sheet(ranger, items: ["longbow": 1]) {
            try $0.equip("longbow", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(longbow.attacks.first?.attackBonus, 5)
        XCTAssertTrue(longbow.attacks.first?.notes.contains("Range 150/600 ft") ?? false)

        let club = try sheet(rogue, items: ["club": 1]) {
            try $0.equip("club", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(club.attacks.first?.damage, "1d4 − 1 bludgeoning", "plain melee weapons use Strength")
    }

    func testWeaponProficiencyFromClassAndRace() throws {
        let wizard = hero("wizard", str: 14)
        let longsword = try sheet(wizard, items: ["longsword": 1]) {
            try $0.equip("longsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(longsword.attacks.first?.attackBonus, 2, "no proficiency bonus")
        XCTAssertTrue(longsword.attacks.first?.notes.contains("Not proficient: no proficiency bonus") ?? false)

        let highElf = hero("wizard", race: "elf", subrace: "high-elf", str: 14)
        let elfSword = try sheet(highElf, items: ["longsword": 1]) {
            try $0.equip("longsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(elfSword.attacks.first?.attackBonus, 4, "Elf Weapon Training")

        let crossbow = try sheet(wizard, items: ["light-crossbow": 1]) {
            try $0.equip("light-crossbow", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(crossbow.attacks.first?.attackBonus, 2, "proficient: Dex 0 + 2")

        let dwarfCleric = hero("cleric", race: "dwarf", str: 14)
        let warhammer = try sheet(dwarfCleric, items: ["warhammer": 1]) {
            try $0.equip("warhammer", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(warhammer.attacks.first?.attackBonus, 4, "Dwarven Combat Training")
    }

    func testTwoWeaponFighting() throws {
        let fighter = hero("fighter", str: 16)
        let daggers = try sheet(fighter, items: ["dagger": 1, "handaxe": 1]) {
            try $0.equip("dagger", in: .mainHand, inventory: $1, catalog: srdCatalog)
            try $0.equip("handaxe", in: .offHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(daggers.attacks.map(\.name), ["Dagger", "Handaxe"])
        XCTAssertEqual(daggers.attacks[0].damage, "1d4 + 3 piercing")
        XCTAssertEqual(daggers.attacks[1].damage, "1d6 slashing", "no ability modifier on off-hand damage")
        XCTAssertTrue(daggers.attacks[1].notes.contains("Bonus action attack (two-weapon fighting)"))

        let notLight = try sheet(fighter, items: ["longsword": 1, "dagger": 1]) {
            try $0.equip("longsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
            try $0.equip("dagger", in: .offHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertTrue(notLight.attacks[1].notes.contains("Two-weapon fighting needs light weapons in both hands"))
    }

    func testMagicWeaponBonusesAndAttunement() throws {
        let fighter = hero("fighter", str: 16)
        let plusOne = try sheet(fighter, items: ["weapon-plus-1": 1]) {
            try $0.equip("weapon-plus-1", in: .mainHand, base: "longsword", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(plusOne.attacks.first?.name, "Weapon, +1 (Longsword)")
        XCTAssertEqual(plusOne.attacks.first?.attackBonus, 6)
        XCTAssertEqual(plusOne.attacks.first?.damage, "1d8 + 4 slashing")

        let unattuned = try sheet(fighter, items: ["holy-avenger": 1]) {
            try $0.equip("holy-avenger", in: .mainHand, base: "longsword", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(unattuned.attacks.first?.attackBonus, 5)
        XCTAssertTrue(unattuned.attacks.first?.notes.contains("Not attuned: no magic") ?? false)
        XCTAssertEqual(unattuned.equipmentWarnings, ["Attune to Holy Avenger (Longsword) to use its magic."])

        let attuned = try sheet(fighter, items: ["holy-avenger": 1]) {
            try $0.equip("holy-avenger", in: .mainHand, base: "longsword", inventory: $1, catalog: srdCatalog)
            try $0.attune("holy-avenger", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(attuned.attacks.first?.attackBonus, 8)
        XCTAssertEqual(attuned.attacks.first?.damage, "1d8 + 6 slashing")
    }

    func testSunBladeIsAFinesseRadiantLongsword() throws {
        let dexFighter = hero("fighter", str: 10, dex: 16)
        let blade = try sheet(dexFighter, items: ["sun-blade": 1]) {
            try $0.equip("sun-blade", in: .mainHand, inventory: $1, catalog: srdCatalog)
            try $0.attune("sun-blade", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(blade.attacks.first?.attackBonus, 3 + 2 + 2)
        XCTAssertEqual(blade.attacks.first?.damage, "1d8 + 5 radiant")
    }

    func testAttunedItemsRaiseSavesAndHitPoints() throws {
        let fighter = hero("fighter", level: 4, con: 10)
        let plain = sheet(fighter, items: [:])
        let lucky = try sheet(fighter, items: ["luck-blade": 1, "berserker-axe": 1]) {
            try $0.equip("luck-blade", in: .mainHand, base: "shortsword", inventory: $1, catalog: srdCatalog)
            try $0.attune("luck-blade", inventory: $1, catalog: srdCatalog)
            try $0.attune("berserker-axe", inventory: $1, catalog: srdCatalog)
        }
        XCTAssertEqual(lucky.savingThrow(.wis), plain.savingThrow(.wis) + 1)
        XCTAssertEqual(lucky.maxHitPoints, plain.maxHitPoints + 4, "Berserker Axe: +1 HP per level while attuned")
    }

    func testSmallCreaturesStruggleWithHeavyWeapons() throws {
        let halfling = hero("fighter", race: "halfling", str: 14)
        let greatsword = try sheet(halfling, items: ["greatsword": 1]) {
            try $0.equip("greatsword", in: .mainHand, inventory: $1, catalog: srdCatalog)
        }
        XCTAssertTrue(greatsword.attacks.first?.notes.contains("Disadvantage: heavy weapon for a Small creature") ?? false)
    }
}
