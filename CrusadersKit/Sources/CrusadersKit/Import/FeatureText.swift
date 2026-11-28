import Foundation

/// Reads D&D Beyond's FEATURES & TRAITS text.
///
/// The text looks like this:
///
///     === SORCERER FEATURES ===
///     * Innate Sorcery • PHB-2024 140
///     Twice per Long Rest, you can take a Bonus Action to …
///        | 2 / Long Rest • 1 Bonus Action
///     * Metamagic Options • PHB-2024 141
///        | Empowered Spell • br-2024
///           | Metamagic: Empowered Spell: Special
///
/// `* Name • SOURCE page` starts a feature, `=== X ===` starts a section, `| Name •` is an option under the
/// feature, `| 2 / Long Rest` is how often it can be used, and `| A: B: Action` is an action note.
/// Indents aren't reliable, because the text is split over columns and pages.
enum FeatureText {
    struct Result {
        var features: [ImportedSheet.FeatureEntry] = []
        var resources: [ImportedSheet.ResourceEntry] = []
        var feats: [String] = []
        var metamagic: [String] = []
        /// (class name, subclass), from "Sorcerer Subclass" → "| Draconic Sorcery".
        var subclasses: [(String, String)] = []
        var ancestry: String?
    }

    private struct Option {
        var name: String
        var text: [String] = []
    }

    private struct Feature {
        var section: String
        var name: String
        var source: String?
        var text: [String] = []
        var options: [Option] = []
    }

    static func parse(_ text: String) -> Result {
        var section = ""
        var features: [Feature] = []
        var explicit: [ImportedSheet.ResourceEntry] = []

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmed
            guard !line.isEmpty else { continue }

            if let header = SheetText.sectionHeader(line) {
                section = titleCase(header)
                continue
            }
            if line.hasPrefix("*") {
                let body = String(line.dropFirst()).trimmed
                let (name, source) = splitBullet(body)
                features.append(Feature(section: section, name: name, source: source))
                continue
            }
            if line.hasPrefix("|") {
                let body = String(line.dropFirst()).trimmed
                if let usage = usage(body) {
                    let featureIndex = features.indices.last
                    let option = featureIndex.flatMap { features[$0].options.last }
                    let owner = usage.name ?? option.map { baseName($0.name) } ?? featureIndex.map { features[$0].name }
                    guard let owner else { continue }
                    var resource = ImportedSheet.ResourceEntry(name: owner, uses: usage.uses, recharge: usage.recharge)
                    let description = ((option?.text ?? []) + (featureIndex.map { features[$0].text } ?? [])).joined(separator: " ")
                    addDetails(from: description, to: &resource)
                    if !explicit.contains(where: { $0.name.caseInsensitiveCompare(owner) == .orderedSame }) {
                        explicit.append(resource)
                    }
                    continue
                }
                if body.contains(":") && !body.contains("•") {
                    // An action note such as "Font of Magic: Convert Spell Slots: No Action".
                    continue
                }
                let (name, _) = splitBullet(body)
                guard !name.isEmpty, let last = features.indices.last else { continue }
                features[last].options.append(Option(name: name))
                continue
            }
            // Description text: belongs to the latest option, or the feature.
            guard let last = features.indices.last else { continue }
            if features[last].options.isEmpty {
                features[last].text.append(line)
            } else {
                features[last].options[features[last].options.count - 1].text.append(line)
            }
        }

        var result = Result()
        result.resources = explicit
        for feature in features {
            let optionText = feature.options.map { option in
                ([option.name] + option.text).joined(separator: "\n")
            }
            result.features.append(ImportedSheet.FeatureEntry(
                section: feature.section,
                name: feature.name,
                source: feature.source,
                text: (feature.text + optionText).joined(separator: "\n"),
                options: feature.options.map(\.name)
            ))

            let lowerName = feature.name.lowercased()
            let sectionWords = feature.section.lowercased().split(separator: " ")
            if sectionWords.contains(where: { $0 == "feats" || $0 == "feat" }), !lowerName.contains("ability score improvement") {
                result.feats.append(feature.name)
            }
            if lowerName.contains("metamagic options") {
                result.metamagic += feature.options.map(\.name)
            }
            if lowerName.hasSuffix(" subclass"), let subclass = feature.options.first?.name {
                result.subclasses.append((String(feature.name.dropLast(" subclass".count)), subclass))
            }
            if lowerName.contains("ancestry"), result.ancestry == nil, let ancestry = feature.options.first?.name {
                result.ancestry = ancestry
            }
            // Uses written only in the description, e.g. "Once per Long Rest as a Bonus Action".
            if let usage = describedUsage(feature.text.joined(separator: " ")),
               !result.resources.contains(where: { $0.name.caseInsensitiveCompare(feature.name) == .orderedSame }) {
                var resource = ImportedSheet.ResourceEntry(name: feature.name, uses: usage.uses, recharge: usage.recharge)
                addDetails(from: feature.text.joined(separator: " "), to: &resource)
                result.resources.append(resource)
            }
        }
        return result
    }

    /// "Innate Sorcery • PHB-2024 140" → ("Innate Sorcery", "PHB-2024 140"); "Black Dragon •" → ("Black Dragon", nil).
    static func splitBullet(_ text: String) -> (String, String?) {
        guard let bullet = text.range(of: "•") else { return (text.trimmed, nil) }
        let name = String(text[..<bullet.lowerBound]).trimmed
        let source = String(text[bullet.upperBound...]).trimmed
        return (name, source.isEmpty ? nil : source)
    }

    /// "Breath Weapon (Acid)" → "Breath Weapon".
    static func baseName(_ name: String) -> String {
        guard let open = name.firstIndex(of: "(") else { return name.trimmed }
        let base = String(name[..<open]).trimmed
        return base.isEmpty ? name.trimmed : base
    }

    private static let recharges = ["Short or Long Rest", "Long Rest", "Short Rest", "Day", "Dawn", "Turn", "Round"]

    /// "2 / Long Rest • 1 Bonus Action" → (nil, 2, Long Rest).
    /// "Font of Magic: Sorcery Points: 4 / Long Rest • Special" → ("Sorcery Points", 4, Long Rest).
    static func usage(_ text: String) -> (name: String?, uses: Int, recharge: String)? {
        let beforeBullet = text.components(separatedBy: "•").first?.trimmed ?? text
        let parts = beforeBullet.components(separatedBy: ":").map(\.trimmed)
        guard let last = parts.last else { return nil }
        let pieces = last.components(separatedBy: "/").map(\.trimmed)
        guard pieces.count == 2, let uses = Int(pieces[0]),
              let recharge = recharges.first(where: { $0.caseInsensitiveCompare(pieces[1]) == .orderedSame })
        else { return nil }
        let name = parts.count >= 2 ? parts[parts.count - 2] : nil
        return (name?.isEmpty == true ? nil : name, uses, recharge)
    }

    /// "Once per Long Rest", "Twice per Long Rest", "2 times per Long Rest", "3 times per Short or Long Rest".
    static func describedUsage(_ text: String) -> (uses: Int, recharge: String)? {
        let pattern = #"\b(once|twice|thrice|(\d+) times) per (short or long rest|long rest|short rest|day)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let wordRange = Range(match.range(at: 1), in: text),
              let rechargeRange = Range(match.range(at: 3), in: text)
        else { return nil }
        let word = text[wordRange].lowercased()
        let uses: Int
        switch word {
        case "once": uses = 1
        case "twice": uses = 2
        case "thrice": uses = 3
        default:
            guard let countRange = Range(match.range(at: 2), in: text), let count = Int(text[countRange]) else { return nil }
            uses = count
        }
        let recharge = recharges.first { $0.caseInsensitiveCompare(String(text[rechargeRange])) == .orderedSame } ?? "Long Rest"
        return (uses, recharge)
    }

    /// Reads "DC 12 Dex. saving throw" and "1d10 Acid damage" from a description.
    static func addDetails(from text: String, to resource: inout ImportedSheet.ResourceEntry) {
        let range = NSRange(text.startIndex..., in: text)
        if let regex = try? NSRegularExpression(pattern: #"\bDC (\d+) ([A-Za-z]+)\.? saving throw"#),
           let match = regex.firstMatch(in: text, range: range),
           let dc = Range(match.range(at: 1), in: text), let ability = Range(match.range(at: 2), in: text) {
            resource.saveDC = Int(text[dc])
            resource.saveAbility = String(text[ability])
        }
        if let regex = try? NSRegularExpression(pattern: #"\b(\d+d\d+(?:\s*[+-]\s*\d+)?) ([A-Za-z]+) damage"#),
           let match = regex.firstMatch(in: text, range: range),
           let dice = Range(match.range(at: 1), in: text), let type = Range(match.range(at: 2), in: text) {
            resource.damage = String(text[dice])
            resource.damageType = String(text[type])
        }
    }

    /// "SORCERER FEATURES" → "Sorcerer Features".
    static func titleCase(_ text: String) -> String {
        text.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
