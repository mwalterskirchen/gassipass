## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The repo uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

The repo is single-context: one `CONTEXT.md` and `docs/adr/` at the root. See `docs/agents/domain.md`.

## Branches

Start each branch from `dev`, and open its pull request against `dev`. Only a release pull request goes from `dev` to `main`, because each change of `main` publishes a TestFlight build. See the README.

## Tests

Run the iOS unit tests with `ios/scripts/test.sh`: with a suite or a single test as argument while you work, and with no argument before a commit, with the local Supabase running (`supabase start`). The script runs `swift test` in the package `ios/GassiPassCore` on the Mac, without a simulator, and a full run takes about 15 seconds. The header of the script explains the rest, and `docs/research/xcode-test-setup.md` explains the choices.

## Seeing the app

The tests do not start the app. To see a screen that you changed, run the app with the demo data through the tools of the MCP server `xcode` (`.mcp.json`), which is the bridge to Xcode. Xcode must run, with "Allow external agents to use Xcode tools" on in its settings. The app runs on a simulator, so the Mac needs one. When `xcrun simctl list devices available` shows none, make one with `xcrun simctl create "iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro`.

1. `XcodeOpenWorkspace` with the absolute path of `ios/gassipass.xcodeproj` in your checkout. Pass the workspace identifier that it returns to the other tools.
2. `DeviceInteractionStartWorkspaceSession`, then `DeviceInteractionInstallAndRun` with `commandLineArguments: ["-demoData", "YES"]`. The app then shows sample dogs and walks in Dietikon from a store in memory. Run it again after each change of the code.
3. `DeviceInteractionSynthesize` without a command returns a screenshot and the UI hierarchy. To go to another screen, tap with `t <x> <y>`, with the `hitPoint` of the element in the hierarchy, not with a position from the screenshot.
4. Look at the screenshot. A tool that succeeds does not show that the screen is right.
5. `DeviceInteractionEndSession`.

For dark mode, run `xcrun simctl ui <device> appearance dark` first. For one view in German, in dark mode or with large text, `RenderPreview` renders a `#Preview` in a few seconds (`sourceFilePath` for example `gassipass/gassipass/Passport/IdentityPage.swift`). The previews have empty stores, and nothing keeps them working, so repair a preview that fails before you use it.

## Layout

The iOS app is in `ios/`, with the Xcode project `ios/gassipass.xcodeproj`. The screens are in `ios/gassipass/`. Everything else of the app is in the Swift package `ios/GassiPassCore/`: put code that is not a view there, with `public` on what the screens use, so that its tests run on the Mac. A string for the user in the package needs `bundle: .module`, and its translation goes into the string catalog of the package. The map packages are in `map-packages/` at the root, and the Xcode project bundles them from there. An Android app goes into `android/`, the Supabase backend goes into `supabase/`, and the website gassipass.ch goes into `web/`. The domain is the same for all of them, so `CONTEXT.md` and `docs/adr/` stay at the root.
