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

Run the iOS unit tests with `ios/scripts/test.sh`: with a suite or a single test as argument while you work, and with no argument before a commit, with the local Supabase running (`supabase start`). The script runs `swift test` in the package `ios/GassiPassCore` on the Mac, without a simulator, and a full run takes about 15 seconds. Take the screenshots of the main screens with `ios/scripts/screenshots.sh`, which runs the UI test on its own simulator. The headers of the scripts explain the rest, and `docs/research/xcode-test-setup.md` explains the choices.

## Layout

The iOS app is in `ios/`, with the Xcode project `ios/gassipass.xcodeproj`. The screens are in `ios/gassipass/`. Everything else of the app is in the Swift package `ios/GassiPassCore/`: put code that is not a view there, with `public` on what the screens use, so that its tests run on the Mac. A string for the user in the package needs `bundle: .module`, and its translation goes into the string catalog of the package. The map packages are in `map-packages/` at the root, and the Xcode project bundles them from there. An Android app goes into `android/`, the Supabase backend goes into `supabase/`, and the website gassipass.ch goes into `web/`. The domain is the same for all of them, so `CONTEXT.md` and `docs/adr/` stay at the root.
