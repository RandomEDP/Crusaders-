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
