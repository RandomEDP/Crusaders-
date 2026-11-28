import Foundation

/// Something a character can use a limited number of times, such as Sorcery Points or a Breath Weapon.
public struct CharacterResource: Identifiable, Codable, Hashable, Sendable {
    /// When uses come back.
    public static let recharges = ["Long Rest", "Short Rest", "Short or Long Rest", "Day", "Dawn", "Turn", "Round"]

    public var id: UUID
    public var name: String
    /// Uses when fully rested.
    public var uses: Int
    /// e.g. "Long Rest"
    public var recharge: String
    /// Uses spent since the last rest.
    public var used: Int
    /// e.g. "DC 12 Dex, 1d10 Acid"
    public var detail: String?

    public init(id: UUID = UUID(), name: String, uses: Int, recharge: String = "Long Rest", used: Int = 0, detail: String? = nil) {
        self.id = id
        self.name = name
        self.uses = max(0, uses)
        self.recharge = recharge
        self.used = min(max(0, used), max(0, uses))
        self.detail = detail
    }

    public var remaining: Int { max(0, uses - used) }

    /// True if a short rest brings uses back.
    public var rechargesOnShortRest: Bool {
        recharge.localizedCaseInsensitiveContains("short")
    }

    enum CodingKeys: String, CodingKey { case id, name, uses, recharge, used, detail }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            uses: try container.decodeIfPresent(Int.self, forKey: .uses) ?? 0,
            recharge: try container.decodeIfPresent(String.self, forKey: .recharge) ?? "Long Rest",
            used: try container.decodeIfPresent(Int.self, forKey: .used) ?? 0,
            detail: try container.decodeIfPresent(String.self, forKey: .detail)
        )
    }
}

/// Backstory and world-building: who the character is, what they believe and what they look like.
public struct CharacterLore: Codable, Hashable, Sendable {
    public var backstory: String
    public var personalityTraits: String
    public var ideals: String
    public var bonds: String
    public var flaws: String
    /// Faith, god or religion.
    public var religion: String
    public var alliesAndOrganizations: String
    public var appearance: String
    /// e.g. "Broad-shouldered, scaled, with a long tail"
    public var bodyShape: String
    public var age: String
    public var gender: String
    public var height: String
    public var weight: String
    public var eyes: String
    public var skin: String
    public var hair: String
    public var notes: String

    public init(backstory: String = "", personalityTraits: String = "", ideals: String = "", bonds: String = "",
                flaws: String = "", religion: String = "", alliesAndOrganizations: String = "", appearance: String = "",
                bodyShape: String = "", age: String = "", gender: String = "", height: String = "", weight: String = "",
                eyes: String = "", skin: String = "", hair: String = "", notes: String = "") {
        self.backstory = backstory
        self.personalityTraits = personalityTraits
        self.ideals = ideals
        self.bonds = bonds
        self.flaws = flaws
        self.religion = religion
        self.alliesAndOrganizations = alliesAndOrganizations
        self.appearance = appearance
        self.bodyShape = bodyShape
        self.age = age
        self.gender = gender
        self.height = height
        self.weight = weight
        self.eyes = eyes
        self.skin = skin
        self.hair = hair
        self.notes = notes
    }

    /// Every field with its label, in the order the Lore screen shows them.
    public static let fields: [(label: String, keyPath: WritableKeyPath<CharacterLore, String>, isLong: Bool)] = [
        ("Backstory", \.backstory, true),
        ("Personality traits", \.personalityTraits, true),
        ("Ideals", \.ideals, true),
        ("Bonds", \.bonds, true),
        ("Flaws", \.flaws, true),
        ("Religion", \.religion, false),
        ("Allies & organizations", \.alliesAndOrganizations, true),
        ("Appearance", \.appearance, true),
        ("Body shape", \.bodyShape, false),
        ("Age", \.age, false),
        ("Gender", \.gender, false),
        ("Height", \.height, false),
        ("Weight", \.weight, false),
        ("Eyes", \.eyes, false),
        ("Skin", \.skin, false),
        ("Hair", \.hair, false),
        ("Notes", \.notes, true)
    ]

    /// The fields that have something written in them.
    public var filled: [(label: String, text: String)] {
        Self.fields.compactMap { field in
            let text = self[keyPath: field.keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (field.label, text)
        }
    }

    public var isEmpty: Bool { filled.isEmpty }

    enum CodingKeys: String, CodingKey {
        case backstory, personalityTraits, ideals, bonds, flaws, religion, alliesAndOrganizations, appearance
        case bodyShape, age, gender, height, weight, eyes, skin, hair, notes
    }

    /// Missing fields are empty, so lore saved by older versions still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        self.init(
            backstory: try text(.backstory), personalityTraits: try text(.personalityTraits), ideals: try text(.ideals),
            bonds: try text(.bonds), flaws: try text(.flaws), religion: try text(.religion),
            alliesAndOrganizations: try text(.alliesAndOrganizations), appearance: try text(.appearance),
            bodyShape: try text(.bodyShape), age: try text(.age), gender: try text(.gender), height: try text(.height),
            weight: try text(.weight), eyes: try text(.eyes), skin: try text(.skin), hair: try text(.hair),
            notes: try text(.notes)
        )
    }
}

extension PlayerCharacter {
    /// Spends one use. Returns false if none are left.
    @discardableResult
    public mutating func useResource(_ id: CharacterResource.ID) -> Bool {
        guard let index = resources.firstIndex(where: { $0.id == id }), resources[index].remaining > 0 else { return false }
        resources[index].used += 1
        return true
    }

    /// Gives one use back.
    public mutating func restoreResource(_ id: CharacterResource.ID) {
        guard let index = resources.firstIndex(where: { $0.id == id }), resources[index].used > 0 else { return }
        resources[index].used -= 1
    }

    /// A long rest brings every use back; a short rest only those that recharge on one.
    public mutating func rest(long: Bool) {
        for index in resources.indices where long || resources[index].rechargesOnShortRest {
            resources[index].used = 0
        }
    }

    /// Splits "Common, Draconic\nElvish" into ["Common", "Draconic", "Elvish"].
    public static func list(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
