import XCTest
@testable import CrusadersKit

final class ItemValidationTests: XCTestCase {
    private let base = EquipmentItem(id: "dagger", name: "Dagger", category: .weapons, group: "Simple Melee",
                                     cost: Cost(amount: 2, coin: .gp), weight: 1,
                                     weapon: WeaponStats(damage: "1d4", damageType: .piercing, properties: [.finesse, .thrown],
                                                         normalRange: 20, longRange: 60))

    func testDamageFormats() {
        for valid in ["1d4", "2d6", "1", "0", "1d8 + 2", "10d10-1", "1D6"] {
            XCTAssertTrue(ItemValidator.isValidDamage(valid), valid)
        }
        for invalid in ["", "d6", "1d", "lots", "1d6+", "1d6 fire"] {
            XCTAssertFalse(ItemValidator.isValidDamage(invalid), invalid)
        }
    }

    func testTrimsTextFields() throws {
        var item = base
        item.name = "  Dagger of Doom  "
        item.description = " Sharp. \n"
        let result = try ItemValidator.validated(item)
        XCTAssertEqual(result.name, "Dagger of Doom")
        XCTAssertEqual(result.description, "Sharp.")
    }

    func testRejectsEmptyNameAndGroup() {
        var item = base
        item.name = "   "
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .emptyName) }
        item = base
        item.group = ""
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .emptyGroup) }
    }

    func testRejectsNegativeCostAndWeight() {
        var item = base
        item.cost?.amount = -1
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .negativeCost) }
        item = base
        item.weight = -2
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .negativeWeight) }
    }

    func testRejectsBadDamage() {
        var item = base
        item.weapon?.damage = "lots"
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .invalidDamage("lots")) }
        item = base
        item.weapon?.versatileDamage = "big"
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .invalidDamage("big")) }
    }

    func testBlankVersatileDamageIsCleared() throws {
        var item = base
        item.weapon?.versatileDamage = "  "
        XCTAssertNil(try ItemValidator.validated(item).weapon?.versatileDamage)
    }

    func testRangeRules() {
        var item = base
        item.weapon?.longRange = 10
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .invalidRange) }
        item = base
        item.weapon?.longRange = nil
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .invalidRange) }
        item = base
        item.weapon?.normalRange = nil
        item.weapon?.longRange = nil
        XCTAssertNoThrow(try ItemValidator.validated(item))
    }

    func testArmourRules() {
        var item = base
        item.weapon = nil
        item.armour = ArmourStats(kind: .heavy, baseArmorClass: 31, addsDexterity: false)
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .armorClassOutOfRange) }
        item.armour = ArmourStats(kind: .medium, baseArmorClass: 14, addsDexterity: true, maxDexterityBonus: 11)
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .dexterityCapOutOfRange) }
        item.armour = ArmourStats(kind: .heavy, baseArmorClass: 18, addsDexterity: false, strengthRequirement: 0)
        XCTAssertThrowsError(try ItemValidator.validated(item)) { XCTAssertEqual($0 as? ItemValidationError, .strengthOutOfRange) }
    }

    func testErrorsHaveMessages() {
        let errors: [ItemValidationError] = [.emptyName, .emptyGroup, .negativeCost, .negativeWeight, .invalidDamage("x"),
                                             .invalidRange, .armorClassOutOfRange, .dexterityCapOutOfRange, .strengthOutOfRange]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
