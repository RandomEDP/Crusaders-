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

## Campaigns

Campaigns > + > **Create campaign** asks for a campaign name and your name, then makes a random **6-digit join code** (for example `042 917`). Whoever creates the campaign is its **Dungeon Master**. Other players use **Join campaign**, enter the code and their name, and are listed as **Players**. Tap a campaign to see its code (with a Share button), the DM and the players. Pull down to refresh the player list.

**Joining with a character.** Join campaign lists the characters saved on the phone; the player picks one (create one in Characters first). The DM sees each player's character on the Party tab.

**Inventory.** Each campaign has a Party tab and an Inventory tab. On Inventory, the DM sees every player's character and can **add** Library items (with a quantity). Players see their own character's items. Both the DM and that player can **remove** items with the − button. Every add or remove is saved as its own `InventoryChange`, and the inventory is worked out from them, so a player never edits the DM's records. Changes the rules don't allow (a player adding, or removing from someone else) are ignored. In Debug, the launch argument `-dmTestCampaign` starts you as DM of "Test Table" (code `654321`) with one player, for UI tests.

Each phone gets a random member id on first launch (it becomes the Sign in with Apple / iCloud id later). The user's campaigns are saved on the phone in `campaigns.json` (Application Support). The launch argument `-inMemoryCampaigns` (used by UI tests) skips saving.

**Sharing between phones needs iCloud.** While iCloud is switched off (see Library items), campaigns stay on the phone that made them, and a sample campaign with code `123456` is there to try joining. With iCloud on, Release builds (and Debug builds with `-useCloudKit`) use the CloudKit public database through `CloudKitCampaignDirectory`.

### iCloud setup for campaigns (once, by the Apple account owner)

In the CloudKit Dashboard, public database, after the container from the Library items setup exists:

1. Create record type `Campaign` with fields `name`, `joinCode`, `dmID`, `dmName` (all String). Records are named `campaign-<code>`, which keeps codes unique.
2. Create record type `CampaignPlayer` with fields `joinCode` (String, **queryable**), `memberID`, `name`, `characterID`, `characterName`, `characterSummary` (all String).
3. Create record type `InventoryChange` with fields `joinCode` (String, **queryable**), `playerID`, `itemID`, `itemName`, `authorID` (String), `delta` (Int64), `changedAt` (Date/Time).
4. Security for all three: World can read, Authenticated (any iCloud user) can create, only the record's creator can write. Each player creates their own `CampaignPlayer` record and each inventory change is a new record, so nobody edits anyone else's.
5. Deploy the schema to Production.

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
