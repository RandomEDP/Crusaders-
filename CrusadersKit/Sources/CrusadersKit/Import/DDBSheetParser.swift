import Foundation

/// Something the import couldn't read, or read but isn't sure about. Shown on the review screen.
public struct ImportIssue: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        /// Not on the sheet, or the box was empty.
        case missing
        /// Read, but it may be wrong. Check it.
        case uncertain
    }

    public var kind: Kind
    /// What the issue is about, e.g. "Armor Class" or "Spells".
    public var field: String
    public var message: String

    public init(kind: Kind, field: String, message: String) {
        self.kind = kind
        self.field = field
        self.message = message
    }

    public var id: String { "\(kind.rawValue)-\(field)-\(message)" }
}

/// The result of reading a sheet: what was read, and what needs checking.
public struct SheetImport: Hashable, Sendable {
    public var sheet: ImportedSheet
    /// The character's name with "Copy of " removed.
    public var name: String
    public var issues: [ImportIssue]

    public init(sheet: ImportedSheet, name: String, issues: [ImportIssue]) {
        self.sheet = sheet
        self.name = name
        self.issues = issues
    }

    public func issues(for field: String) -> [ImportIssue] {
        issues.filter { $0.field == field }
    }
}

/// Reads a D&D Beyond character sheet PDF (2014 or 2024 rules, any number of pages).
///
/// Pages are told apart by their labels, never by page number, because features and spells can run
/// onto extra pages. A missing page or box is reported as an issue and never stops the import.
public enum DDBSheetParser {
    public enum PageKind: String, CaseIterable, Sendable {
        case core, features, additionalFeatures, details, spells, unknown
    }

    #if canImport(PDFKit)
    public static func parse(pdf data: Data, catalog: RulesCatalog = .srd, now: Date = Date()) throws -> SheetImport {
        parse(pages: try PDFSheetReader.pages(from: data), catalog: catalog, now: now)
    }

    public static func parse(pdfAt url: URL, catalog: RulesCatalog = .srd, now: Date = Date()) throws -> SheetImport {
        parse(pages: try PDFSheetReader.pages(from: url), catalog: catalog, now: now)
    }
    #endif

    /// What a page is, from its labels (or, if the labels couldn't be read, from its box names).
    public static func kind(of page: PDFSheetPage) -> PageKind {
        let text = page.text.uppercased()
        func has(_ labels: String...) -> Bool { labels.allSatisfy { text.contains($0) } }
        if has("SPELLCASTING") && has("SPELL SAVE DC") { return .spells }
        if has("PREP", "SPELL NAME") { return .spells }
        if has("ADDITIONAL FEATURES") || has("ADDITIONAL EQUIPMENT") { return .additionalFeatures }
        if has("FEATURES & TRAITS") && has("EQUIPMENT") { return .features }
        if has("STRENGTH", "SAVING THROWS", "SKILLS") { return .core }
        if has("ALIGNMENT") && (has("PERSONALITY TRAITS") || has("CHARACTER BACKSTORY") || has("IDEALS")) { return .details }
        // No usable labels: fall back to the boxes on the page.
        if page.hasField("STR") && page.hasField("AC") { return .core }
        if page.hasField("spellCastingAbility0") || !page.numberedFields("spellName").isEmpty { return .spells }
        if page.hasField("ALIGNMENT") || page.hasField("Backstory") { return .details }
        if page.hasField("GP") || page.hasField("CP") { return .features }
        if !page.numberedFields("FeaturesTraits").isEmpty || !page.numberedFields("Eq Name").isEmpty { return .additionalFeatures }
        return .unknown
    }

    public static func parse(pages: [PDFSheetPage], catalog: RulesCatalog = .srd, now: Date = Date()) -> SheetImport {
        var reader = Reader(pages: pages, catalog: catalog)
        return reader.read(now: now)
    }
}

// MARK: - Reading

private struct Reader {
    let pages: [PDFSheetPage]
    let kinds: [DDBSheetParser.PageKind]
    let catalog: RulesCatalog
    var sheet = ImportedSheet()
    var issues: [ImportIssue] = []

    init(pages: [PDFSheetPage], catalog: RulesCatalog) {
        self.pages = pages
        self.kinds = pages.map(DDBSheetParser.kind(of:))
        self.catalog = catalog
    }

    func pagesOf(_ kinds: DDBSheetParser.PageKind...) -> [PDFSheetPage] {
        zip(pages, self.kinds).filter { kinds.contains($0.1) }.map(\.0)
    }

    var corePage: PDFSheetPage? { pagesOf(.core).first }

    /// A box from the first page of a kind that has it filled in, or from any page if none do.
    func value(_ name: String, on kind: DDBSheetParser.PageKind) -> String? {
        for page in pagesOf(kind) {
            if let value = page.value(name) { return value }
        }
        return nil
    }

    func anyValue(_ names: String...) -> String? {
        for name in names {
            for page in pages {
                if let value = page.value(name) { return value }
            }
        }
        return nil
    }

    mutating func flag(_ kind: ImportIssue.Kind, _ field: String, _ message: String) {
        issues.append(ImportIssue(kind: kind, field: field, message: message))
    }

    mutating func read(now: Date) -> SheetImport {
        sheet.importedAt = now
        sheet.rawText = pages.map(\.rawText).joined(separator: "\n\n")

        if corePage == nil { flag(.missing, "Core sheet", "Couldn't find the main page (abilities, saves and skills).") }

        let name = readIdentity()
        readAbilities()
        readSavesAndSkills()
        readCombat()
        readProficiencies()
        readAttacks()
        readCoinsAndEquipment()
        readFeatures()
        readDetails()
        readSpells()

        return SheetImport(sheet: sheet, name: name, issues: issues)
    }

    // MARK: Identity

    mutating func readIdentity() -> String {
        var name = (anyValue("CharacterName", "CharacterName2", "CharacterName3", "CharacterName4") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("copy of ") {
            name = String(name.dropFirst("copy of ".count)).trimmingCharacters(in: .whitespaces)
        }
        if name.isEmpty { flag(.missing, "Name", "No character name on the sheet.") }

        if let classText = anyValue("CLASS LEVEL", "CLASS LEVEL2", "CLASS LEVEL3") {
            sheet.classes = SheetText.classLevels(classText)
            if sheet.classes.isEmpty { flag(.uncertain, "Class", "Couldn't read class and level from \"\(classText.trimmed)\".") }
        } else {
            flag(.missing, "Class", "No class and level on the sheet.")
        }

        sheet.playerName = anyValue("PLAYER NAME", "PLAYER NAME2")?.trimmed
        sheet.species = anyValue("RACE", "RACE2", "SPECIES", "RACE3")?.trimmed
        if sheet.species == nil { flag(.missing, "Species", "No species or race on the sheet.") }
        let allText = pages.map(\.text).joined(separator: "\n").uppercased()
        if allText.contains("SPECIES") {
            sheet.rulesEdition = "2024"
        } else if allText.contains("RACE") {
            sheet.rulesEdition = "2014"
        }
        sheet.background = anyValue("BACKGROUND", "BACKGROUND2")?.trimmed
        if sheet.background == nil { flag(.missing, "Background", "No background on the sheet.") }
        if let xp = anyValue("EXPERIENCE POINTS", "EXPERIENCE POINTS2") {
            sheet.experiencePoints = SheetText.number(xp)
        }
        return name
    }

    // MARK: Abilities

    mutating func readAbilities() {
        let names: [(Ability, String, [String])] = [
            (.str, "STR", ["STRmod"]), (.dex, "DEX", ["DEXmod"]), (.con, "CON", ["CONmod"]),
            (.int, "INT", ["INTmod"]), (.wis, "WIS", ["WISmod"]), (.cha, "CHA", ["CHamod", "CHAmod"])
        ]
        for (ability, scoreName, modNames) in names {
            let scoreValue = value(scoreName, on: .core).flatMap(SheetText.number)
            let modifierValue = first(modNames, on: .core).flatMap(SheetText.number)
            guard let pair = SheetText.scoreAndModifier(scoreValue, modifierValue) else {
                if scoreValue == nil && modifierValue == nil {
                    flag(.missing, ability.name, "No \(ability.name) score on the sheet.")
                } else {
                    flag(.uncertain, ability.name, "\(ability.name) score and modifier don't match.")
                    if let score = scoreValue {
                        sheet.abilities.append(.init(ability: ability, score: score, modifier: AbilityScores.modifier(for: score)))
                    }
                }
                continue
            }
            sheet.abilities.append(.init(ability: ability, score: pair.score, modifier: pair.modifier))
        }
    }

    // MARK: Saves and skills

    static let saveNames: [(Ability, String, String)] = [
        (.str, "ST Strength", "StrProf"), (.dex, "ST Dexterity", "DexProf"), (.con, "ST Constitution", "ConProf"),
        (.int, "ST Intelligence", "IntProf"), (.wis, "ST Wisdom", "WisProf"), (.cha, "ST Charisma", "ChaProf")
    ]

    /// The sheet's box names for each skill: (bonus names, proficiency names).
    static let skillNames: [Skill: ([String], [String])] = [
        .acrobatics: (["Acrobatics"], ["AcrobaticsProf"]),
        .animalHandling: (["Animal", "AnimalHandling", "Animal Handling"], ["AnimalHandlingProf", "AnimalProf"]),
        .arcana: (["Arcana"], ["ArcanaProf"]),
        .athletics: (["Athletics"], ["AthleticsProf"]),
        .deception: (["Deception"], ["DeceptionProf"]),
        .history: (["History"], ["HistoryProf"]),
        .insight: (["Insight"], ["InsightProf"]),
        .intimidation: (["Intimidation"], ["IntimidationProf"]),
        .investigation: (["Investigation"], ["InvestigationProf"]),
        .medicine: (["Medicine"], ["MedicineProf"]),
        .nature: (["Nature"], ["NatureProf"]),
        .perception: (["Perception"], ["PerceptionProf"]),
        .performance: (["Performance"], ["PerformanceProf"]),
        .persuasion: (["Persuasion"], ["PersuasionProf"]),
        .religion: (["Religion"], ["ReligionProf"]),
        .sleightOfHand: (["SleightofHand", "SleightOfHand", "Sleight of Hand"], ["SleightOfHandProf", "SleightofHandProf"]),
        .stealth: (["Stealth"], ["StealthProf"]),
        .survival: (["Survival"], ["SurvivalProf"])
    ]

    func first(_ names: [String], on kind: DDBSheetParser.PageKind) -> String? {
        for name in names {
            if let found = value(name, on: kind) { return found }
        }
        return nil
    }

    mutating func readSavesAndSkills() {
        var missingSaves: [String] = []
        for (ability, bonusName, profName) in Self.saveNames {
            guard let bonus = value(bonusName, on: .core).flatMap(SheetText.number) else {
                missingSaves.append(ability.name)
                continue
            }
            let marker = value(profName, on: .core)?.trimmed ?? ""
            sheet.savingThrows.append(.init(ability: ability, bonus: bonus, proficient: !marker.isEmpty))
        }
        if !missingSaves.isEmpty {
            flag(.missing, "Saving throws", "No printed save for \(missingSaves.joined(separator: ", ")).")
        }

        var missingSkills: [String] = []
        for skill in Skill.allCases {
            let (bonusNames, profNames) = Self.skillNames[skill] ?? ([], [])
            guard let bonus = first(bonusNames, on: .core).flatMap(SheetText.number) else {
                missingSkills.append(skill.name)
                continue
            }
            let marker = (first(profNames, on: .core)?.trimmed ?? "").uppercased()
            let proficiency: ImportedSheet.Proficiency
            switch marker {
            case "E": proficiency = .expertise
            case "P": proficiency = .proficient
            case "": proficiency = .none
            default:
                proficiency = .proficient
                flag(.uncertain, "Skills", "\(skill.name) has an unknown proficiency mark \"\(marker)\".")
            }
            sheet.skills.append(.init(skill: skill, bonus: bonus, proficiency: proficiency))
        }
        if !missingSkills.isEmpty {
            flag(.missing, "Skills", "No printed bonus for \(missingSkills.joined(separator: ", ")).")
        }
    }

    // MARK: Combat

    mutating func readCombat() {
        sheet.armorClass = value("AC", on: .core).flatMap(SheetText.number)
        if sheet.armorClass == nil { flag(.missing, "Armor Class", "No Armor Class on the sheet.") }
        sheet.initiative = value("Init", on: .core).flatMap(SheetText.number)
        if sheet.initiative == nil { flag(.missing, "Initiative", "No initiative on the sheet.") }
        if let speed = value("Speed", on: .core) {
            sheet.speeds = SheetText.speeds(speed)
            if sheet.speeds.isEmpty { flag(.uncertain, "Speed", "Couldn't read speed \"\(speed.trimmed)\".") }
        } else {
            flag(.missing, "Speed", "No speed on the sheet.")
        }
        sheet.maxHitPoints = value("MaxHP", on: .core).flatMap(SheetText.number)
        if sheet.maxHitPoints == nil { flag(.missing, "Max HP", "No max hit points on the sheet.") }
        sheet.hitDice = (value("Total", on: .core) ?? value("HD", on: .core))?.trimmed
        if sheet.hitDice == nil { flag(.missing, "Hit dice", "No hit dice on the sheet.") }
        sheet.proficiencyBonus = value("ProfBonus", on: .core).flatMap(SheetText.number)
        if sheet.proficiencyBonus == nil { flag(.missing, "Proficiency bonus", "No proficiency bonus on the sheet.") }
        sheet.passivePerception = value("Passive1", on: .core).flatMap(SheetText.number)
        sheet.passiveInsight = value("Passive2", on: .core).flatMap(SheetText.number)
        sheet.passiveInvestigation = value("Passive3", on: .core).flatMap(SheetText.number)
        if sheet.passivePerception == nil { flag(.missing, "Passive Perception", "No passive Perception on the sheet.") }

        if let senses = value("AdditionalSenses", on: .core) {
            sheet.senses = SheetText.list(senses)
        }
        if let defenses = value("Defenses", on: .core) {
            for (kind, values) in SheetText.defenses(defenses) {
                switch kind {
                case "resistances", "resistance": sheet.resistances += values
                case "immunities", "immunity": sheet.immunities += values
                case "vulnerabilities", "vulnerability": sheet.vulnerabilities += values
                default: flag(.uncertain, "Defenses", "Unknown defense \"\(kind)\".")
                }
            }
        }
    }

    mutating func readProficiencies() {
        guard let text = value("ProficienciesLang", on: .core) else {
            flag(.missing, "Proficiencies", "No proficiencies or languages on the sheet.")
            return
        }
        for (section, body) in SheetText.sections(text) {
            let items = SheetText.list(body)
            switch section.uppercased() {
            case "ARMOR", "ARMOUR": sheet.armorProficiencies += items
            case "WEAPONS", "WEAPON": sheet.weaponProficiencies += items
            case "TOOLS", "TOOL": sheet.toolProficiencies += items
            case "LANGUAGES", "LANGUAGE": sheet.languages += items
            default: break
            }
        }
    }

    // MARK: Attacks

    mutating func readAttacks() {
        guard let core = corePage else { return }
        for row in 1...12 {
            let names = row == 1 ? ["Wpn Name", "Wpn Name 1"] : ["Wpn Name \(row)"]
            guard let name = names.lazy.compactMap({ core.value($0) }).first?.trimmed, !name.isEmpty else { continue }
            let bonusText = core.value("Wpn\(row) AtkBonus")?.trimmed
            let damageText = core.value("Wpn\(row) Damage")?.trimmed
            let notes = (core.value("Wpn Notes \(row)") ?? core.value("Wpn\(row) Notes"))?.trimmed
            var attack = ImportedSheet.AttackEntry(name: name, notes: notes.flatMap { $0.isEmpty ? nil : $0 })
            if let bonusText {
                if let bonus = SheetText.number(bonusText) {
                    attack.attackBonus = bonus
                } else {
                    attack.saveText = bonusText
                }
            }
            if let damageText {
                let parts = SheetText.damage(damageText)
                attack.damage = parts.dice
                attack.damageType = parts.type
            }
            sheet.attacks.append(attack)
        }
    }

    // MARK: Coins and equipment

    mutating func readCoinsAndEquipment() {
        var foundCoins = false
        for coin in Coin.allCases {
            let text = value(coin.rawValue.uppercased(), on: .features) ?? anyValue(coin.rawValue.uppercased())
            if text != nil { foundCoins = true }
            sheet.coins.append(.init(coin: coin, count: text.flatMap(SheetText.number) ?? 0))
        }
        if !foundCoins { flag(.missing, "Coins", "No coins on the sheet. Everything was set to 0.") }

        var merged: [ImportedSheet.EquipmentEntry] = []
        for page in pagesOf(.features, .additionalFeatures) {
            for (number, field) in page.numberedFields("Eq Name").sorted(by: { $0.number < $1.number }) {
                let name = field.value.trimmed
                guard !name.isEmpty else { continue }
                let quantityText = page.value("Eq Qty\(number)")
                let quantity = quantityText.flatMap(SheetText.number) ?? 1
                let weight = page.value("Eq Weight\(number)")?.trimmed
                if let index = merged.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    merged[index].quantity += quantity
                } else {
                    merged.append(.init(name: name, quantity: quantity, weight: weight.flatMap { $0 == "--" ? nil : $0 }))
                }
            }
        }
        if merged.isEmpty && pagesOf(.features).isEmpty {
            flag(.missing, "Equipment", "Couldn't find the equipment page.")
        }
        sheet.equipment = merged
    }

    // MARK: Features

    mutating func readFeatures() {
        var texts: [(page: Int, number: Int, text: String)] = []
        for page in pagesOf(.features, .additionalFeatures) {
            for (number, field) in page.numberedFields("FeaturesTraits") where !field.value.trimmed.isEmpty {
                texts.append((page.index, number, field.value))
            }
        }
        texts.sort { ($0.page, $0.number) < ($1.page, $1.number) }
        guard !texts.isEmpty else {
            flag(.missing, "Features", "Couldn't find features and traits.")
            return
        }
        let parsed = FeatureText.parse(texts.map(\.text).joined(separator: "\n"))
        sheet.features = parsed.features
        sheet.feats = parsed.feats
        sheet.metamagic = parsed.metamagic
        sheet.resources = parsed.resources
        sheet.ancestry = parsed.ancestry
        for (className, subclass) in parsed.subclasses {
            if let index = sheet.classes.firstIndex(where: { $0.name.caseInsensitiveCompare(className) == .orderedSame }) {
                sheet.classes[index].subclass = subclass
            } else if sheet.classes.count == 1 {
                sheet.classes[0].subclass = subclass
            }
        }
    }

    // MARK: Details

    mutating func readDetails() {
        sheet.alignment = (value("ALIGNMENT", on: .details) ?? anyValue("ALIGNMENT"))?.trimmed
        if sheet.alignment == nil { flag(.missing, "Alignment", "No alignment on the sheet.") }
        sheet.size = (value("SIZE", on: .details) ?? anyValue("SIZE"))?.trimmed
        if sheet.size == nil { flag(.missing, "Size", "No size on the sheet.") }
        sheet.personalityTraits = value("PersonalityTraits", on: .details)?.trimmed
        sheet.ideals = value("Ideals", on: .details)?.trimmed
        sheet.bonds = value("Bonds", on: .details)?.trimmed
        sheet.flaws = value("Flaws", on: .details)?.trimmed
        sheet.backstory = value("Backstory", on: .details)?.trimmed
        let others: [(String, String)] = [
            ("Gender", "GENDER"), ("Age", "AGE"), ("Height", "HEIGHT"), ("Weight", "WEIGHT"), ("Faith", "FAITH"),
            ("Skin", "SKIN"), ("Eyes", "EYES"), ("Hair", "HAIR"), ("Appearance", "Appearance"),
            ("Allies & Organizations", "AlliesOrganizations"), ("Additional notes", "AdditionalNotes1"),
            ("More notes", "AdditionalNotes2")
        ]
        for (label, name) in others {
            if let text = value(name, on: .details)?.trimmed, !text.isEmpty {
                sheet.otherDetails.append(.init(label: label, text: text))
            }
        }
    }

    // MARK: Spells

    mutating func readSpells() {
        let spellPages = pagesOf(.spells)
        guard !spellPages.isEmpty else { return }

        for page in spellPages {
            for (number, field) in page.numberedFields("spellCastingAbility").sorted(by: { $0.number < $1.number }) {
                let ability = Ability(rawValue: field.value.trimmed.lowercased())
                let entry = ImportedSheet.SpellcastingEntry(
                    className: page.value("spellCastingClass\(number)")?.trimmed,
                    ability: ability,
                    saveDC: page.value("spellSaveDC\(number)").flatMap(SheetText.number),
                    attackBonus: page.value("spellAtkBonus\(number)").flatMap(SheetText.number)
                )
                if !sheet.spellcasting.contains(entry) { sheet.spellcasting.append(entry) }
            }
        }
        if sheet.spellcasting.isEmpty { flag(.missing, "Spellcasting", "No spellcasting ability, save DC or attack bonus.") }

        // Headers and rows are numbered separately, so put them in reading order: page, then top to bottom
        // (and left column before right column).
        enum Row { case header(level: Int?, slots: Int?), spell(page: PDFSheetPage, number: Int) }
        var rows: [(page: Int, column: Int, top: Double, row: Row)] = []
        for page in spellPages {
            let columnSplit = 306.0
            for (number, field) in page.numberedFields("spellHeader") {
                let slotText = page.value("spellSlotHeader\(number)")
                let header = Row.header(level: SheetText.spellLevel(field.value), slots: slotText.flatMap(SheetText.slotCount))
                rows.append((page.index, field.x > columnSplit ? 1 : 0, field.y + field.height / 2, header))
            }
            for (number, field) in page.numberedFields("spellName") where !field.value.trimmed.isEmpty {
                rows.append((page.index, field.x > columnSplit ? 1 : 0, field.y + field.height / 2, .spell(page: page, number: number)))
            }
        }
        rows.sort { ($0.page, $0.column, -$0.top) < ($1.page, $1.column, -$1.top) }

        var level: Int?
        var unknownLevel = false
        for row in rows {
            switch row.row {
            case let .header(headerLevel, slots):
                level = headerLevel
                if let headerLevel, headerLevel > 0, let slots {
                    if let index = sheet.spellSlots.firstIndex(where: { $0.level == headerLevel }) {
                        sheet.spellSlots[index].slots = max(sheet.spellSlots[index].slots, slots)
                    } else {
                        sheet.spellSlots.append(.init(level: headerLevel, slots: slots))
                    }
                }
            case let .spell(page, number):
                guard let name = page.value("spellName\(number)")?.trimmed else { continue }
                if level == nil { unknownLevel = true }
                let prepared = page.value("spellPrepared\(number)")?.trimmed.uppercased() ?? ""
                let source = page.value("spellSource\(number)")?.trimmed
                let alwaysPrepared = prepared == "P" || (source?.localizedCaseInsensitiveContains("always prepared") ?? false)
                var spell = ImportedSheet.SpellEntry(
                    name: name,
                    level: level ?? 0,
                    source: source,
                    alwaysPrepared: alwaysPrepared,
                    saveOrAttack: page.value("spellSaveHit\(number)")?.trimmed.nonEmptyValue,
                    castingTime: page.value("spellCastingTime\(number)")?.trimmed.nonEmptyValue,
                    range: page.value("spellRange\(number)")?.trimmed.nonEmptyValue,
                    components: page.value("spellComponents\(number)")?.trimmed.nonEmptyValue,
                    duration: page.value("spellDuration\(number)")?.trimmed.nonEmptyValue,
                    pageReference: page.value("spellPage\(number)")?.trimmed.nonEmptyValue,
                    notes: page.value("spellNotes\(number)")?.trimmed.nonEmptyValue
                )
                spell.srdID = catalog.spells.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
                // The same spell can be listed twice (from the class, and always prepared): keep one, always prepared.
                if let index = sheet.spells.firstIndex(where: {
                    $0.level == spell.level && $0.name.caseInsensitiveCompare(spell.name) == .orderedSame
                }) {
                    if spell.alwaysPrepared && !sheet.spells[index].alwaysPrepared {
                        sheet.spells[index].alwaysPrepared = true
                        sheet.spells[index].source = spell.source
                    }
                } else {
                    sheet.spells.append(spell)
                }
            }
        }
        if unknownLevel { flag(.uncertain, "Spells", "Some spells had no level heading and were listed as cantrips.") }
    }
}

// MARK: - Text helpers

enum SheetText {
    /// "6,140" → 6140, "+3" → 3, "-1" → -1, "−1" → -1, "13" → 13. "--", "" and words → nil.
    static func number(_ text: String) -> Int? {
        var cleaned = text.trimmed.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
        if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        guard !cleaned.isEmpty, cleaned != "-", cleaned != "--" else { return nil }
        if let value = Int(cleaned) { return value }
        // "78 lb." or "30 ft." → the leading number.
        return Scanner(string: cleaned).scanInt()
    }

    /// Picks which of two numbers is the score and which is the modifier: modifier = floor((score − 10) / 2).
    static func scoreAndModifier(_ a: Int?, _ b: Int?) -> (score: Int, modifier: Int)? {
        guard let a, let b else {
            // Only the score was printed: work the modifier out from it.
            if let a, b == nil { return (a, AbilityScores.modifier(for: a)) }
            return nil
        }
        if AbilityScores.modifier(for: a) == b { return (a, b) }
        if AbilityScores.modifier(for: b) == a { return (b, a) }
        return nil
    }

    /// "Sorcerer 4 / Warlock 1" → [Sorcerer 4, Warlock 1].
    static func classLevels(_ text: String) -> [ImportedSheet.ClassEntry] {
        text.components(separatedBy: "/").compactMap { part in
            let words = part.trimmed.split(separator: " ")
            guard words.count >= 2, let level = Int(words.last!) else { return nil }
            return ImportedSheet.ClassEntry(name: words.dropLast().joined(separator: " "), level: level)
        }
    }

    /// "30 ft. (Walking), 60 ft. (Flying)" → [(30, Walking), (60, Flying)].
    static func speeds(_ text: String) -> [ImportedSheet.SpeedEntry] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n")).compactMap { part in
            let trimmed = part.trimmed
            guard let feet = number(trimmed) else { return nil }
            var mode = "Walking"
            if let open = trimmed.firstIndex(of: "("), let close = trimmed.lastIndex(of: ")"), open < close {
                mode = String(trimmed[trimmed.index(after: open)..<close]).trimmed
            }
            return ImportedSheet.SpeedEntry(feet: feet, mode: mode)
        }
    }

    /// Comma or line separated list, without blanks.
    static func list(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n")).map(\.trimmed).filter { !$0.isEmpty }
    }

    /// "Resistances - Acid, Fire\nImmunities - Poison" → [("resistances", [Acid, Fire]), ("immunities", [Poison])].
    static func defenses(_ text: String) -> [(String, [String])] {
        text.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmed
            guard !trimmed.isEmpty else { return nil }
            guard let range = trimmed.range(of: " - ") ?? trimmed.range(of: ": ") else { return nil }
            let kind = String(trimmed[..<range.lowerBound]).trimmed.lowercased()
            return (kind, list(String(trimmed[range.upperBound...])))
        }
    }

    /// "=== WEAPONS === \nSimple Weapons \n\n=== TOOLS === ..." → [("WEAPONS", "Simple Weapons"), ...].
    static func sections(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        var current: String?
        var body: [String] = []
        for line in text.components(separatedBy: "\n") {
            if let header = sectionHeader(line) {
                if let current { result.append((current, body.joined(separator: "\n"))) }
                current = header
                body = []
            } else {
                body.append(line)
            }
        }
        if let current { result.append((current, body.joined(separator: "\n"))) }
        return result
    }

    /// "=== SORCERER FEATURES ===" → "SORCERER FEATURES".
    static func sectionHeader(_ line: String) -> String? {
        let trimmed = line.trimmed
        guard trimmed.hasPrefix("==="), trimmed.hasSuffix("==="), trimmed.count > 6 else { return nil }
        return String(trimmed.dropFirst(3).dropLast(3)).trimmed
    }

    /// "1d4+1 Piercing" → ("1d4+1", "Piercing"); "0 Bludgeoning" → ("0", "Bludgeoning"); "1d8" → ("1d8", nil).
    static func damage(_ text: String) -> (dice: String?, type: String?) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, trimmed != "--" else { return (nil, nil) }
        guard let space = trimmed.firstIndex(of: " ") else { return (trimmed, nil) }
        let dice = String(trimmed[..<space])
        let type = String(trimmed[trimmed.index(after: space)...]).trimmed
        return (dice, type.isEmpty ? nil : type)
    }

    /// "=== CANTRIPS ===" → 0, "=== 1st LEVEL ===" → 1, "=== 9th LEVEL ===" → 9.
    static func spellLevel(_ text: String) -> Int? {
        let header = (sectionHeader(text) ?? text.trimmed).uppercased()
        if header.contains("CANTRIP") { return 0 }
        let digits = header.prefix { $0.isNumber }
        return Int(digits)
    }

    /// "4 Slots OOOO" → 4. "(At Will)" → nil.
    static func slotCount(_ text: String) -> Int? {
        let trimmed = text.trimmed
        guard trimmed.lowercased().contains("slot") else { return nil }
        return number(trimmed)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nil for "" and "--".
    var nonEmptyValue: String? {
        let value = trimmed
        return value.isEmpty || value == "--" ? nil : value
    }
}
