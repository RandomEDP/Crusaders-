import XCTest
@testable import CrusadersKit

final class SRDItemDataTests: XCTestCase {
    private var items: [EquipmentItem] = []

    override func setUpWithError() throws {
        items = try SRDItems.load()
    }

    private func item(_ id: String) throws -> EquipmentItem {
        try XCTUnwrap(items.first { $0.id == id }, "missing \(id)")
    }

    func testLoadsEveryCategory() {
        XCTAssertGreaterThan(items.count, 250)
        for category in ItemCategory.allCases {
            XCTAssertFalse(items.filter { $0.category == category }.isEmpty, "\(category) is empty")
        }
    }

    func testIdsAreUniqueAndNamesPresent() {
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        for item in items {
            XCTAssertFalse(item.name.isEmpty, item.id)
            XCTAssertFalse(item.group.isEmpty, item.id)
        }
    }

    func testEveryItemPassesValidation() {
        for item in items {
            XCTAssertNoThrow(try ItemValidator.validated(item), item.id)
        }
    }

    func testAllThirtySevenMundaneWeaponsHaveStats() {
        let mundane = items.filter { $0.category == .weapons && $0.rarity == nil }
        XCTAssertEqual(mundane.count, 37)
        XCTAssertTrue(mundane.allSatisfy { $0.weapon != nil && $0.cost != nil })
        XCTAssertEqual(Set(mundane.map(\.group)), ["Simple Melee", "Simple Ranged", "Martial Melee", "Martial Ranged"])
    }

    func testAllThirteenMundaneArmoursHaveStats() {
        let mundane = items.filter { $0.category == .armour && $0.rarity == nil }
        XCTAssertEqual(mundane.count, 13)
        XCTAssertTrue(mundane.allSatisfy { $0.armour != nil })
    }

    func testLongsword() throws {
        let sword = try item("longsword")
        XCTAssertEqual(sword.group, "Martial Melee")
        XCTAssertEqual(sword.cost, Cost(amount: 15, coin: .gp))
        XCTAssertEqual(sword.weight, 3)
        XCTAssertEqual(sword.weapon?.damage, "1d8")
        XCTAssertEqual(sword.weapon?.damageType, .slashing)
        XCTAssertEqual(sword.weapon?.versatileDamage, "1d10")
        XCTAssertEqual(sword.weapon?.properties, [.versatile])
    }

    func testLongbowRangeAndProperties() throws {
        let bow = try item("longbow")
        XCTAssertEqual(bow.weapon?.normalRange, 150)
        XCTAssertEqual(bow.weapon?.longRange, 600)
        XCTAssertEqual(bow.weapon?.properties, [.ammunition, .heavy, .twoHanded])
        XCTAssertEqual(bow.weapon?.propertiesText, "Ammunition (range 150/600), Heavy, Two-handed")
    }

    func testPlateAndHalfPlate() throws {
        let plate = try XCTUnwrap(try item("plate").armour)
        XCTAssertEqual(plate.baseArmorClass, 18)
        XCTAssertEqual(plate.strengthRequirement, 15)
        XCTAssertTrue(plate.stealthDisadvantage)
        XCTAssertEqual(plate.armorClass(dexterityModifier: 3), 18)

        let halfPlate = try XCTUnwrap(try item("half-plate").armour)
        XCTAssertEqual(halfPlate.armorClass(dexterityModifier: 4), 17)
        XCTAssertEqual(halfPlate.armorClassText, "15 + Dex modifier (max 2)")
    }

    func testPotionsAndAmmunition() throws {
        let healing = try item("potion-of-healing")
        XCTAssertEqual(healing.rarity, .common)
        XCTAssertTrue(healing.description.contains("2d4 + 2"))
        XCTAssertEqual(try item("arrows").cost, Cost(amount: 1, coin: .gp))
        XCTAssertEqual(try item("sling-bullets").cost, Cost(amount: 4, coin: .cp))
        XCTAssertEqual(try item("ammunition-plus-3").rarity, .veryRare)
    }
}

final class ItemCatalogTests: XCTestCase {
    private let club = EquipmentItem(id: "club", name: "Club", category: .weapons, group: "Simple Melee",
                                     cost: Cost(amount: 1, coin: .sp), weight: 2,
                                     weapon: WeaponStats(damage: "1d4", damageType: .bludgeoning, properties: [.light]))
    private let longsword = EquipmentItem(id: "longsword", name: "Longsword", category: .weapons, group: "Martial Melee",
                                          weapon: WeaponStats(damage: "1d8", damageType: .slashing))
    private let leather = EquipmentItem(id: "leather", name: "Leather", category: .armour, group: "Light Armour",
                                        armour: ArmourStats(kind: .light, baseArmorClass: 11, addsDexterity: true))
    private let rope = EquipmentItem(id: "rope", name: "Rope, Hempen", category: .gear, group: "Adventuring Gear",
                                     description: "Has 2 hit points.")

    private var catalog: ItemCatalog { ItemCatalog(baseItems: [club, longsword, leather, rope]) }

    func testSectionsFollowCategoryOrderAndKeepGroups() {
        let sections = catalog.sections()
        XCTAssertEqual(sections.map(\.category), [.weapons, .armour, .gear])
        XCTAssertEqual(sections[0].groups.map(\.name), ["Simple Melee", "Martial Melee"])
        XCTAssertEqual(sections[0].itemCount, 2)
    }

    func testSearchMatchesNameGroupAndDescription() {
        XCTAssertEqual(catalog.sections(matching: "LONG").flatMap { $0.groups.flatMap(\.items) }.map(\.id), ["longsword"])
        XCTAssertEqual(catalog.sections(matching: "light armour").map(\.category), [.armour])
        XCTAssertEqual(catalog.sections(matching: "hit points").first?.category, .gear)
        XCTAssertTrue(catalog.sections(matching: "zzz").isEmpty)
        XCTAssertEqual(catalog.sections(matching: "   ").count, 3)
    }

    func testEditsReplaceItemsAndCanBeReverted() {
        var catalog = self.catalog
        var edited = club
        edited.weapon?.damage = "1d6"
        catalog.applyEdit(edited)
        XCTAssertEqual(catalog.item(id: "club")?.weapon?.damage, "1d6")
        XCTAssertEqual(catalog.original(id: "club")?.weapon?.damage, "1d4")
        XCTAssertTrue(catalog.isEdited("club"))
        XCTAssertEqual(catalog.items.map(\.id), ["club", "longsword", "leather", "rope"])

        catalog.revert(id: "club")
        XCTAssertFalse(catalog.isEdited("club"))
        XCTAssertEqual(catalog.item(id: "club"), club)
    }

    func testOverrideIdenticalToOriginalIsNotEdited() {
        let catalog = ItemCatalog(baseItems: [club], overrides: [club])
        XCTAssertFalse(catalog.isEdited("club"))
    }

    func testEditCanMoveItemToAnotherCategory() {
        var catalog = self.catalog
        var moved = rope
        moved.category = .tools
        moved.group = "Other Tools"
        catalog.applyEdit(moved)
        XCTAssertEqual(catalog.sections().map(\.category), [.weapons, .armour, .tools])
    }

    func testSummaries() {
        XCTAssertEqual(club.summary, "1d4 bludgeoning · 1 sp")
        XCTAssertEqual(leather.summary, "AC 11 + Dex modifier")
        var magic = rope
        magic.rarity = .veryRare
        magic.requiresAttunement = true
        XCTAssertEqual(magic.summary, "Very rare, attunement")
    }

    func testShieldArmorClass() {
        let shield = ArmourStats(kind: .shield, baseArmorClass: 2, addsDexterity: false)
        XCTAssertEqual(shield.armorClassText, "+2")
        XCTAssertEqual(shield.armorClass(dexterityModifier: 5), 2)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(club)
        XCTAssertEqual(try JSONDecoder().decode(EquipmentItem.self, from: data), club)
    }

    func testCoinValues() {
        XCTAssertEqual(Cost(amount: 3, coin: .gp).inCopper, 300)
        XCTAssertEqual(Cost(amount: 2, coin: .pp).inCopper, 2000)
    }
}
