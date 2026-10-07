## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The repo uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

The repo is single-context: one `CONTEXT.md` and `docs/adr/` at the root. See `docs/agents/domain.md`.

## Branches

Start each branch from `dev`, and open its pull request against `dev`. Only a release pull request goes from `dev` to `main`, because each change of `main` publishes a TestFlight build. See the README.

## Layout

The iOS app is in `ios/`, with the Xcode project `ios/gassipass.xcodeproj`. The map packages are in `map-packages/` at the root, and the Xcode project bundles them from there. An Android app goes into `android/`, and the Supabase backend goes into `supabase/`. The domain is the same for all of them, so `CONTEXT.md` and `docs/adr/` stay at the root.
