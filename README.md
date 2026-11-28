# Crusaders

An iOS app for running Dungeons & Dragons games: keep your characters, create or join campaigns, and browse a library of creator-made content.

Built with SwiftUI (iOS 17+).

## Getting started

1. Install Xcode (latest) and XcodeGen: `brew install xcodegen`
2. Generate the project: `xcodegen generate`
3. Open `Crusaders.xcodeproj` and run the **Crusaders** scheme.

The `.xcodeproj` is generated from `project.yml` and isn't committed. Re-run `xcodegen generate` after pulling changes that add or move files.

## Layout

| Path | What's there |
| --- | --- |
| `Crusaders/` | The SwiftUI app: screens and app state |
| `CrusadersKit/` | Swift package with models and rules (characters, campaigns, library). No UI. |
| `CrusadersTests/` | Unit tests for the app's state |
| `CrusadersUITests/` | UI tests that boot the app in the simulator |
| `.github/workflows/` | CI and TestFlight deploy |

## Tests

- Package tests: `swift test --package-path CrusadersKit`
- Everything: `xcodebuild test -project Crusaders.xcodeproj -scheme Crusaders -destination 'platform=iOS Simulator,name=iPhone 16'`

## Library items

Library > Items holds every weapon, armour, ammunition, potion, adventuring gear and tool from the SRD 5.1, under collapsible headers. The built-in list is `CrusadersKit/Sources/CrusadersKit/Resources/srd-items.json`.

### Creator editing

The app's creator can change any characteristic of an item (name, cost, weight, rarity, damage, properties, range, AC, Strength, stealth, description) from the item's **Edit** button. Edits are saved to the CloudKit public database, so every player gets them. **Reset to SRD values** removes an edit.

**iCloud is currently switched off** (`CLOUDKIT_ENABLED: NO` in `project.yml`) until the container below exists, so builds sign without it. While it's off, items are view-only in TestFlight and Library > Creator access says so. To switch it on after the setup below, set `CLOUDKIT_ENABLED: YES` and add `CODE_SIGN_ENTITLEMENTS: Crusaders/Crusaders.entitlements` in `project.yml`.

With iCloud on, Release builds (TestFlight) use it. Debug builds keep edits in memory so CI runs without signing. In Debug, add the launch argument `-creatorMode` to try creator tools, or `-useCloudKit` to talk to iCloud from a signed build.

### iCloud setup (once, by the Apple account owner)

1. In the Apple Developer portal, create the iCloud container `iCloud.com.randomedp.Crusaders` and enable iCloud (CloudKit) on the App ID `com.randomedp.Crusaders` with that container. The entitlements file (`Crusaders/Crusaders.entitlements`) is ready for when iCloud is switched on.
2. In the CloudKit Dashboard, in the public database, create two record types:
   - `ItemOverride` with fields `itemID` (String) and `payload` (String). Add a queryable index on `recordName`.
   - `Creator` with field `userID` (String, queryable).
3. Security: everyone (World) can read both types. Only a **Creator** security role can create or write `ItemOverride`. Nobody in the app can create `Creator` records.
4. Add the creator: in the app, open Library > Creator access and copy the iCloud ID. Create a `Creator` record with that `userID`, and give that user the Creator role.
5. Deploy the schema to Production (TestFlight uses the Production environment).

Item data attribution: This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.

## Library creatures

Library > Creatures holds all 334 monsters, beasts and NPCs from the SRD 5.1 with full stat blocks (AC, hit points, speed, ability scores, saves, skills, resistances, senses, languages, challenge rating with XP, traits, actions, reactions and legendary actions). They sit under collapsible headers by type (Aberrations, Beasts, Dragons...). Search by name, type, subtype, or challenge rating such as `CR 1/4`.

The built-in list is `CrusadersKit/Sources/CrusadersKit/Resources/srd-creatures.json`, generated from the [5e-bits/5e-database](https://github.com/5e-bits/5e-database) monsters JSON with `python3 scripts/srd/convert_creatures.py <5e-database>/src/2014/en/5e-SRD-Monsters.json CrusadersKit/Sources/CrusadersKit/Resources/srd-creatures.json`. Don't edit it by hand. Monsters outside the SRD (for example from the Monster Manual only, Volo's or Mordenkainen's) are copyrighted and aren't included; the creator can add their own instead.

### Creator tools

The creator (the same creator list as Library items) gets:

- A **+** button on Library > Creatures to add a new creature, with every part of the stat block, and any number of traits, actions, reactions and legendary actions.
- An **Edit** button on every creature. **Reset to SRD stats** removes edits to an SRD creature; **Delete creature** removes one the creator added.

Rules (validation, who can edit) are in `CrusadersKit/Sources/CrusadersKit/Creatures` and are unit tested. Added creatures are marked with a star, edited ones with a pencil.

Creatures follow the same iCloud switch as items: with iCloud off, creator tools are off in TestFlight; in Debug, `-creatorMode` turns them on (changes stay in memory).

### iCloud setup for creatures (once, by the Apple account owner)

In the CloudKit Dashboard, public database, after the Library items setup:

1. Create record type `CreatureEntry` with fields `creatureID` (String) and `payload` (String). Add a queryable index on `recordName`. Records are named `creature-<id>`: SRD ids like `goblin` are edits, ids starting `custom-` are creatures the creator added.
2. Security: World can read. Only the **Creator** role can create or write (the same role as `ItemOverride`).
3. Deploy the schema to Production.

## Campaigns

Campaigns > + > **Create campaign** asks for a campaign name and your name, then makes a random **6-digit join code** (for example `042 917`). Whoever creates the campaign is its **Dungeon Master**. Other players use **Join campaign**, enter the code and their name, and are listed as **Players**. Tap a campaign to see its code (with a Share button), the DM and the players. Pull down to refresh the player list.

**Joining with a character.** Join campaign lists the characters saved on the phone; the player picks one (create one in Characters first). The DM sees each player's character on the Party tab.

**Inventory.** Each campaign has Party, Inventory and Chat tabs (see Campaign chat). On Inventory, the DM sees every player's character and can **add** Library items (with a quantity). Players see their own character's items. Both the DM and that player can **remove** items with the − button. Every add or remove is saved as its own `InventoryChange`, and the inventory is worked out from them, so a player never edits the DM's records. Changes the rules don't allow (a player adding, or removing from someone else) are ignored. In Debug, the launch argument `-dmTestCampaign` starts you as DM of "Test Table" (code `654321`) with one player, for UI tests.

**Equipping items (5e SRD rules).** On Inventory, the player (or the DM) taps the shield button next to a weapon or armour to wear, wield or attune to it. The rules, in `CrusadersKit/Sources/CrusadersKit/Equipment`:

- One suit of body armour and one shield. Wearing new armour swaps out the old.
- Two hands: a shield takes the off hand; two-handed weapons need both hands; versatile weapons can be switched to two hands for the bigger damage die; light weapons in both hands give the two-weapon fighting bonus attack (no ability modifier on off-hand damage).
- AC: light armour = base + Dex, medium = base + Dex (max +2), heavy = base only, shield +2, plus magic bonuses. With no armour: 10 + Dex, or Unarmored Defense (Barbarian 10 + Dex + Con, Monk 10 + Dex + Wis with no shield) or Draconic Resilience (13 + Dex).
- Heavy armour below its Strength requirement makes you 10 ft slower (not for dwarves). Armour with Stealth disadvantage flags the Stealth skill. Armour you aren't proficient with shows a warning (disadvantage, no spellcasting).
- Attacks use Str (melee), Dex (ranged) or the better of the two (finesse), plus proficiency if the class or race is proficient, plus magic bonuses.
- Magic weapons and armour like "Armor, +1" ask which armour or weapon they are. Items that need attunement only work once attuned; at most 3 at a time.

The changes show on the character sheet automatically (Armor Class, speed, attacks, saves, hit points), on the phone of the player who owns the character. Every change is saved as a `LoadoutChange`, and items the DM later removes simply drop off.

Each phone gets a random member id on first launch (it becomes the Sign in with Apple / iCloud id later). The user's campaigns are saved on the phone in `campaigns.json` (Application Support). The launch argument `-inMemoryCampaigns` (used by UI tests) skips saving.

**Sharing between phones needs iCloud.** While iCloud is switched off (see Library items), campaigns stay on the phone that made them, and a sample campaign with code `123456` is there to try joining. With iCloud on, Release builds (and Debug builds with `-useCloudKit`) use the CloudKit public database through `CloudKitCampaignDirectory`.

### iCloud setup for campaigns (once, by the Apple account owner)

In the CloudKit Dashboard, public database, after the container from the Library items setup exists:

1. Create record type `Campaign` with fields `name`, `joinCode`, `dmID`, `dmName` (all String). Records are named `campaign-<code>`, which keeps codes unique.
2. Create record type `CampaignPlayer` with fields `joinCode` (String, **queryable**), `memberID`, `name`, `characterID`, `characterName`, `characterSummary` (all String).
3. Create record type `InventoryChange` with fields `joinCode` (String, **queryable**), `playerID`, `itemID`, `itemName`, `authorID` (String), `delta` (Int64), `changedAt` (Date/Time).
4. Create record type `LoadoutChange` with fields `joinCode` (String, **queryable**), `playerID`, `authorID`, `loadout` (String), `changedAt` (Date/Time).
5. Security for all four: World can read, Authenticated (any iCloud user) can create, only the record's creator can write. Each player creates their own `CampaignPlayer` record and each inventory change is a new record, so nobody edits anyone else's.
6. Deploy the schema to Production.

## Campaign chat

Each campaign has a **Chat** tab with:

- **Party chat**: everyone in the campaign (the DM and every player) can read and write.
- **Private chats**: one per player, between the DM and that player only. The DM sees a private chat for each player; a player sees only their own. Other players can't see it exists, let alone read it.
- **Narrate** (DM only): sends a line as the story, in italics with no name, for example a private "You hear a voice in your head call out your name."

Open chats check for new messages every 10 seconds, and you can pull down to refresh. The rules (who can read and write each chat, and that only the DM narrates) are in `CrusadersKit/Sources/CrusadersKit/CampaignChat.swift` and are unit tested. The app also drops any message that breaks them, even if a server returned it.

**While iCloud is off** chats stay on the phone (and reset when the app closes), like campaigns. The sample campaign has a welcome message.

**With iCloud on** (`CloudKitChatService`):

- Party messages are `ChatMessage` records in the public database, like the rest of the campaign.
- Private chats are **not** in the public database. Each one is a record zone in the **DM's private iCloud database**, shared with that single player through a CloudKit share with no public access. iCloud only lets the DM and that player read or write it, so even someone who got hold of the share link can't open it. The DM's phone sets up a private chat the first time the DM opens the Chat tab; until then the player sees "Your private chat opens once the Dungeon Master opens it."
- The player's iCloud identity comes from iCloud's own record of who created their `CampaignPlayer` record, and the player's phone checks the invite was written by the campaign's DM, so nobody can pose as someone else.

### iCloud setup for chat (once, by the Apple account owner)

In the CloudKit Dashboard, after the campaign setup above:

1. Public database: create record type `ChatMessage` with fields `joinCode` (String, **queryable**), `channel`, `senderID`, `senderName`, `text` (all String), `narration` (Int64), `sentAt` (Date/Time).
2. Public database: create record type `WhisperInvite` with fields `joinCode`, `playerID`, `shareURL` (all String).
3. Security for both: World can read, Authenticated can create, only the creator can write (same as the campaign types).
4. Private chats use `WhisperMessage` records in the DM's private database (same fields as `ChatMessage`). This type is created automatically the first time a DM sends a private message from a Debug build with `-useCloudKit` on a device signed in to iCloud (Development environment). No security settings are needed: the share decides who can see it.
5. Deploy the schema to Production.

`Info.plist` has `CKSharingSupported` set, which CloudKit sharing needs.

## Building a character

- **Ability scores**: standard array, point buy (27 points, 8 to 15), 4d6 drop the lowest (rolled in the app, with reroll), or custom scores rolled at the table. In array and rolled modes, the arrows on a score swap it with another.
- **Presets**: the wand button on Ability scores gives three builds per class for different play styles (for example Fighter: Tank, Archer, Duelist). It places the best scores where that build needs them and picks its skills, using the current scores' method.
- **Hit points**: fixed (half the hit die + 1 per level) or rolled hit dice. Level 1 always takes the full die. Rolled characters roll again on each level-up, and the level-up screen shows the roll.

## Saving characters

Characters are saved with SwiftData, so they're still there after the app closes. With iCloud on, SwiftData also mirrors them to each player's **private** CloudKit database, so they sync across every device signed in to the same Apple ID. Nobody else can see them.

- **iCloud off** (today, `CLOUDKIT_ENABLED: NO`): characters are saved on the device only. The Characters screen says so.
- **iCloud on**: Release builds (TestFlight) sync. Debug builds stay on the device unless launched with `-useCloudKit`. Characters already saved on the device are uploaded the first time iCloud is used.
- Each character is one `StoredCharacter` record holding the character as JSON, so new character fields never need a database migration.
- UI tests launch with `-resetCharacters` (start empty) or `-inMemoryCharacters` (never touch the disk).

Extra iCloud setup for character sync (with the Library items setup below):

1. On the App ID, also enable **Push Notifications** (CloudKit uses silent pushes to deliver changes from other devices). The entitlements file already has `aps-environment`, and Info.plist has the `remote-notification` background mode.
2. Run a Debug build once with `-useCloudKit` on a device signed in to iCloud and create a character. That creates the `CD_StoredCharacter` record type in the Development private database. Then deploy the schema to Production in the CloudKit Dashboard.

## Characters and SRD content

The character builder uses every race, class (with its SRD subclass) and spell from the **System Reference Document 5.1**: 9 races, 12 classes and 319 spells. Characters level up from XP using the SRD table, and the level-up screen lists each new feature, spell slot, spell level and subclass.

The data is generated Swift under `CrusadersKit/Sources/CrusadersKit/Characters/SRD/`, built from the [5e-bits/5e-database](https://github.com/5e-bits/5e-database) JSON (`src/2014/en`) with `python3 scripts/srd/convert.py <5e-database>/src/2014/en CrusadersKit/Sources/CrusadersKit/Characters/SRD`. Don't edit those files by hand.

Content outside the SRD (for example Xanathar's or Tasha's subclasses, or races like Tabaxi) is copyrighted by Wizards of the Coast and isn't included.

> This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.

## Look and feel

The app uses an old-parchment theme. Everything lives in `Crusaders/Theme/Theme.swift`; the colours are in `CrusadersKit/Sources/CrusadersKit/Theme/ThemePalette.swift` so their contrast is unit tested (body text at least 7:1, everything else at least 4.5:1).

- Logo and app icon: `Logo` and `AppIcon` in the asset catalog, from the red shield and dragon artwork.
- Background: `Parchment` image, with list rows on lighter paper cards.
- Fonts (bundled in `Crusaders/Resources/Fonts`, both SIL Open Font License 1.1, licences included): Grenze Gotisch for titles and headings, EB Garamond for everything else. Both scale with the iPhone's text size setting.
- New screens: call `.parchmentScreen()` after `.navigationTitle(...)` and use `ThemedSection` instead of `Section`.
- The app always uses light mode so the parchment stays readable.

## Work cycle

1. Create a branch for each piece of work.
2. Do the work and add tests. CI runs on every push.
3. Open a pull request and merge it into `main` once CI is green.
4. Deploy to TestFlight from `main` only. Never from a branch.

The **TestFlight** workflow runs when a PR is merged into `main`. If other pull requests are still open it skips the upload, so we only ship when nothing else is in progress. Run it by hand from the Actions tab (Run workflow, on `main`) once they're done.

## TestFlight secrets

Repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_P8` | Full text of the `.p8` key file, including the BEGIN/END lines |

The API key needs the **Admin** role so Xcode can create the distribution certificate and profile automatically. The team ID (`DP3V39HSP5`) is set in `project.yml`. The app record for bundle ID `com.randomedp.Crusaders` must exist in App Store Connect.
