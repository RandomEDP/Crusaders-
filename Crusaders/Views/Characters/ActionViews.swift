import SwiftUI
import CrusadersKit

/// One attack on the character sheet. Tapping it rolls to hit and damage and posts the result in the
/// campaign's party chat. Bows, crossbows, slings and blowguns use one piece of ammunition per attack
/// and can't be used when none is left.
struct AttackRollRow: View {
    @Environment(AppModel.self) private var model
    let attack: AttackOption
    let characterID: PlayerCharacter.ID
    let campaignCode: String?
    @Binding var outcome: ActionOutcome?
    @Binding var errorMessage: String?

    @State private var isChoosing = false
    @State private var isRolling = false

    var body: some View {
        let ammo = attack.ammunition.map { model.ammunition($0, for: characterID, campaignCode: campaignCode) } ?? []
        let ammoCount = ammo.reduce(0) { $0 + $1.quantity }
        let outOfAmmo = attack.ammunition != nil && ammoCount == 0
        Button {
            isChoosing = true
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attack.name).font(.serifBold(.headline))
                    if let damage = attack.damage {
                        Text([damage.text, attack.damageType].compactMap { $0 }.joined(separator: " "))
                            .font(.serif(.subheadline))
                    }
                    if let kind = attack.ammunition {
                        Text(outOfAmmo ? "No \(kind.plural) left" : "\(ammoCount) \(kind.plural)")
                            .font(.serif(.caption))
                            .foregroundStyle(outOfAmmo ? Theme.crimson : Theme.inkSoft)
                            .accessibilityIdentifier("attack.ammo")
                    }
                    if !attack.notes.isEmpty {
                        Text(attack.notes.joined(separator: " · "))
                            .font(.serif(.caption))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(attack.attackBonus.map(AbilityScores.signed) ?? attack.saveText ?? "")
                        .font(.serifBold(.headline))
                        .monospacedDigit()
                    Image(systemName: "dice")
                        .foregroundStyle(outOfAmmo ? Theme.inkSoft : Theme.crimson)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(outOfAmmo || isRolling)
        .accessibilityElement(children: .combine)
        .accessibilityHint(outOfAmmo ? "Out of ammunition" : "Rolls the attack and posts it in the party chat")
        .accessibilityIdentifier("attack.roll.\(attack.name)")
        .confirmationDialog("Attack with \(attack.name)", isPresented: $isChoosing, titleVisibility: .visible) {
            ForEach(attack.attackBonus == nil ? [RollMode.normal] : RollMode.allCases) { mode in
                if ammo.count > 1 {
                    // A choice of ammunition, e.g. ordinary arrows or +1 ammunition.
                    ForEach(ammo) { stack in
                        Button("\(mode.title), \(stack.name) (\(stack.quantity))") { roll(mode, ammo: stack.itemID) }
                    }
                } else {
                    Button(mode.title) { roll(mode, ammo: ammo.first?.itemID) }
                }
            }
        } message: {
            Text(attack.ammunition == nil ? "The roll goes in the party chat."
                 : "Uses 1 of your \(attack.ammunition!.plural). The roll goes in the party chat.")
        }
    }

    private func roll(_ mode: RollMode, ammo: String?) {
        isRolling = true
        Task {
            defer { isRolling = false }
            do {
                outcome = try await model.rollAttack(attack, characterID: characterID, campaignCode: campaignCode,
                                                     mode: mode, ammoItemID: ammo)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A "Cast" button next to a spell. Cantrips cast for free; leveled spells spend a slot, chosen from the
/// levels that still have one, and can't be cast when none are left.
struct CastSpellButton: View {
    @Environment(AppModel.self) private var model
    let name: String
    let spellLevel: Int
    /// Whether the spell makes an attack roll, so advantage can be chosen.
    let rollsToHit: Bool
    let sheet: CharacterSheet
    let cast: (_ slotLevel: Int?, _ mode: RollMode) async throws -> ActionOutcome
    @Binding var outcome: ActionOutcome?
    @Binding var errorMessage: String?

    @State private var isChoosing = false
    @State private var isCasting = false

    var body: some View {
        let levels = sheet.castingLevels(forSpellLevel: spellLevel)
        let canCast = spellLevel == 0 || levels.contains { $0.left > 0 }
        Button {
            isChoosing = true
        } label: {
            Label(canCast ? "Cast" : "No slots", systemImage: "sparkles")
                .font(.serif(.subheadline))
        }
        .buttonStyle(.bordered)
        .disabled(!canCast || isCasting)
        .accessibilityLabel(canCast ? "Cast \(name)" : "\(name): no spell slots left")
        .accessibilityIdentifier("spell.cast.\(name)")
        .confirmationDialog("Cast \(name)", isPresented: $isChoosing, titleVisibility: .visible) {
            let modes = rollsToHit ? RollMode.allCases : [.normal]
            if spellLevel == 0 {
                ForEach(modes) { mode in
                    Button(mode == .normal ? "Cast" : "Cast, \(mode.title.lowercased())") { run(nil, mode) }
                }
            } else {
                ForEach(levels.filter { $0.left > 0 }) { slot in
                    ForEach(modes) { mode in
                        let modeText = mode == .normal ? "" : ", \(mode.title.lowercased())"
                        Button("\(Spell.ordinal(slot.level))-level slot (\(slot.left) left)\(modeText)") { run(slot.level, mode) }
                    }
                }
            }
        } message: {
            Text(spellLevel == 0 ? "Cantrips don't use a slot. The roll goes in the party chat."
                 : "Uses a spell slot. The roll goes in the party chat.")
        }
    }

    private func run(_ slotLevel: Int?, _ mode: RollMode) {
        isCasting = true
        Task {
            defer { isCasting = false }
            do {
                outcome = try await cast(slotLevel, mode)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Spell slots left at each level, with a way to give one back after a mis-tap.
struct SpellSlotTracker: View {
    @Environment(AppModel.self) private var model
    let sheet: CharacterSheet

    var body: some View {
        let maximums = sheet.spellSlotMaximums
        VStack(alignment: .leading, spacing: 6) {
            Text("Spell slots").font(.serif(.subheadline))
            ForEach(1...9, id: \.self) { level in
                let maximum = maximums[level - 1]
                if maximum > 0 {
                    let left = sheet.spellSlotsLeft(atLevel: level)
                    HStack(spacing: 6) {
                        Text(Spell.ordinal(level)).font(.serifBold(.subheadline)).frame(width: 36, alignment: .leading)
                        ForEach(0..<maximum, id: \.self) { index in
                            Image(systemName: index < left ? "circle.fill" : "circle")
                                .foregroundStyle(index < left ? Theme.crimson : Theme.inkSoft)
                        }
                        Spacer()
                        Text("\(left) of \(maximum)").font(.serif(.caption)).foregroundStyle(Theme.inkSoft)
                        Button {
                            model.restoreSpellSlot(level: level, for: sheet.character.id)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(left == maximum)
                        .accessibilityLabel("Give back a \(Spell.ordinal(level))-level slot")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("slots.\(level)")
                    .accessibilityValue("\(left) of \(maximum) left")
                }
            }
            Text(sheet.character.usesPactMagic ? "Pact Magic slots come back on a short or long rest."
                 : "Slots come back on a long rest.")
                .font(.serif(.caption))
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

extension View {
    /// Shows what an attack, spell or ability rolled and where it was posted, or why it couldn't be used.
    /// One alert for both, because two alerts on the same screen don't both show.
    func actionOutcomeAlert(_ outcome: Binding<ActionOutcome?>, error: Binding<String?>) -> some View {
        let title: String
        let message: String
        if let result = outcome.wrappedValue {
            title = result.postedTo.map { "Posted in \($0)" } ?? "Rolled"
            message = [result.text, result.problem ?? (result.postedTo == nil
                ? "Join a campaign with this character to share rolls in its party chat." : nil)]
                .compactMap { $0 }.joined(separator: "\n\n")
        } else {
            title = "Can't do that"
            message = error.wrappedValue ?? ""
        }
        return alert(
            title,
            isPresented: Binding(
                get: { outcome.wrappedValue != nil || error.wrappedValue != nil },
                set: { if !$0 { outcome.wrappedValue = nil; error.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
