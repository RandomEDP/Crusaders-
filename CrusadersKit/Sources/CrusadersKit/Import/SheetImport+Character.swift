import Foundation

extension SheetImport {
    /// Turns the import into a character: what fits the character model goes into its fields, and
    /// everything (including the printed numbers) is kept in `importedSheet`.
    ///
    /// The SRD race isn't linked: D&D Beyond's printed scores already include species bonuses, and
    /// linking SRD Dragonborn would add +2 Str and +1 Cha a second time. The SRD class is linked when the
    /// first class has an SRD match, so class features and level-up keep working.
    public func makeCharacter(id: UUID = UUID(), catalog: RulesCatalog = .srd) -> PlayerCharacter {
        let level = min(max(sheet.totalLevel, PlayerCharacter.levelRange.lowerBound), PlayerCharacter.levelRange.upperBound)
        var scores = AbilityScores()
        for entry in sheet.abilities {
            scores[entry.ability] = entry.score
        }
        let classID = sheet.classes.first.flatMap { entry in
            catalog.classes.first { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }?.id
        }
        let skills = Set(sheet.skills.filter { $0.proficiency != .none }.map(\.skill))
        let spellIDs = Set(sheet.spells.compactMap(\.srdID))
        let className = sheet.classes.count > 1
            ? sheet.classes.map(\.name).joined(separator: " / ")
            : (sheet.classes.first?.name ?? "")
        return PlayerCharacter(
            id: id,
            name: name,
            race: sheet.species ?? "",
            characterClass: className,
            level: level,
            raceID: nil,
            subraceID: nil,
            classID: classID,
            baseAbilityScores: scores,
            skillProficiencies: skills,
            experiencePoints: sheet.experiencePoints,
            spellIDs: spellIDs,
            importedSheet: sheet
        )
    }
}
