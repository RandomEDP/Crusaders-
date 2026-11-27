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
