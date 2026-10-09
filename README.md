<p align="center">
  <img src="brand/icon.svg" width="128" alt="GassiPass app icon">
</p>

<h1 align="center">GassiPass</h1>

<p align="center">
  A game for dog walks in Switzerland.<br>
  Each dog collects the segments it walks, and fills in Gemeinden and their streets until they are completed.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-26-2D5B43" alt="iOS 26">
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-2D5B43" alt="SwiftUI and SwiftData">
  <img src="https://img.shields.io/badge/map%20data-%C2%A9swisstopo-2D5B43" alt="Map data ©swisstopo">
</p>

<p align="center">
  <img src="docs/images/home.png" width="200" alt="Home screen with pinned areas">
  <img src="docs/images/area.png" width="200" alt="Area screen of Dietikon">
  <img src="docs/images/map.png" width="200" alt="Map with collected segments">
  <img src="docs/images/walk.png" width="200" alt="Current walk with live feedback">
</p>

## How it works

The map of Switzerland is cut into **segments**. A segment is a stretch of walkable way between two junctions, or between a junction and a dead end. When a dog's walks cover nearly all of a segment, the dog **collects** it. The walks do not need to cover it in one go.

Every Gemeinde is an **area**. The collected length of an area, as a share of its total length, is its **completion**. When the completion reaches 100%, the dog has **completed** the area, and the app keeps that date for good. Streets work the same way inside each area.

Each dog has its own collection. When two dogs go on the same walk, both collect the segments.

## Features

- **Walks.** Start a walk, pick the dogs that take part, and put the phone in your pocket. The app records the track also when the phone is locked.
- **Live feedback.** During the walk, the map shows the new segments near you. The phone vibrates for each segment that becomes collected, and the completion of the current area goes up live. A Live Activity shows the walk on the lock screen.
- **Pinned areas.** Pin the areas you want to follow, and see their completion on the home screen.
- **Area screen.** See the collected segments of an area on its map, and the completion of each street.
- **Collection book.** Browse all areas of a canton for one dog, including the areas with no completion yet.
- **Map.** See the collected and the not collected segments on the swisstopo base map.
- **Several dogs.** Each dog has its own collection. A retired dog keeps its collection and its completed areas.
- **Packs.** Each dog belongs to a pack (Rudel). The pack has a name, which you can change in the settings. For now the app works only on the phone and talks to no server. Accounts, backups and shared packs come with Supabase ([ADR 0006](docs/adr/0006-supabase-and-local-databases.md)).
- **Map packages in the app.** The segments, the areas, the streets and the map tiles of each canton come with the app, so a walk counts also without a network.

<p align="center">
  <img src="docs/images/book.png" width="200" alt="Collection book of canton Zürich">
  <img src="docs/images/walks.png" width="200" alt="List of walks">
</p>

## Map data

The segments come from [swissTLM3D](https://www.swisstopo.admin.ch/en/landscape-model-swisstlm3d), the landscape model of swisstopo, and the areas come from [swissBOUNDARIES3D](https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d). The app does not use OpenStreetMap for segments. [ADR 0001](docs/adr/0001-swisstlm3d-as-segment-source.md) explains why.

Ways that a dog cannot or must not use are not segments. Examples are motorways, via ferratas, alpine routes and ways inside a dog-ban zone.

At the moment the app includes canton Zürich and canton Aargau.

## Build the app

You need Xcode 26 and a device or simulator with iOS 26.

1. Open `ios/gassipass.xcodeproj` in Xcode.
2. Select the scheme `gassipass` and run it.

The map packages of the cantons are in `map-packages/`, so the app runs without the map build. To make the packages again from the swisstopo data, see [mapbuild/README.md](mapbuild/README.md).

The app keeps its data in a SwiftData store on the phone (`ios/gassipass/Store/`). Builds before ADR 0006 kept it in Core Data and synced it with iCloud. The first launch of a newer build copies the old Core Data store into the SwiftData store once, and leaves the old files on the phone.

The app talks to two Supabase projects in Zurich. The scheme `gassipass` builds the configuration "Debug" and talks to the development project `gassipass-dev`. The scheme `gassipass Production` builds the configuration "Debug Production" and talks to the production project `gassipass`, like the TestFlight builds.

The URL and the publishable key of each project are not in git. Copy `ios/Config/Supabase.example.xcconfig` to `ios/Config/Supabase.Development.xcconfig` and to `ios/Config/Supabase.Production.xcconfig`, and fill in the values from the dashboard of each project. Without these files the app builds, but it cannot talk to Supabase.

The auth settings of both projects are in `supabase/config.toml`. To change them, edit the file, check the change with `supabase config diff --project-ref <ref>`, and push it with `supabase config push --project-ref <ref>` to each project.

New work goes to the branch `dev` first. A feature or fix branch starts from `dev`, and its pull request goes to `dev`. Test the changes on `dev` with a build from Xcode. When they work, a pull request from `dev` to `main` releases them.

Xcode Cloud publishes a TestFlight build after each change of `main`. The workflow archives the scheme `gassipass`, sets a new build number and gives the build to the internal testing group. A second workflow runs the unit tests on each pull request to `main` or `dev`. The workflows are set up in App Store Connect, not in this repository. The release workflow needs the environment variables `SUPABASE_PRODUCTION_URL` and `SUPABASE_PRODUCTION_PUBLISHABLE_KEY`. The script `ios/ci_scripts/ci_pre_xcodebuild.sh` writes them into the build, and it stops an archive without them.

To see the app with sample dogs and walks in Dietikon, add the launch argument `-demoData YES` in a debug build. The app then keeps its store in memory and does not touch your real walks.

## Tests

- The app tests run with the scheme `gassipass` (⌘U in Xcode).
- The map build tests run with `make test` in `mapbuild/`.
- The scheme `gassipass Screenshots` saves a screenshot of each main screen with the demo data. See `ios/gassipassUITests/ScreenshotTests.swift`.

## Project layout

| Folder | Content |
| ------ | ------- |
| `ios/gassipass/` | The iOS app (SwiftUI, SwiftData, MapLibre) |
| `ios/gassipassWidgets/` | The Live Activity of the current walk |
| `ios/gassipassTests/` | The unit tests and the engine tests |
| `map-packages/` | The map packages of the cantons, which the apps bundle |
| `mapbuild/` | The Python tool that makes the map packages from swisstopo data |
| `brand/` | The app icon as SVG, and the script that makes the icon and the launch screen mark from it |
| `docs/adr/` | The architecture decisions |

The repository is ready for more apps. An Android app goes into `android/`, and the Supabase backend goes into `supabase/`. Each app bundles the map packages from `map-packages/`, so the map build writes each package to one place.

The words of the domain, such as segment, area, collection and completion, are defined in [CONTEXT.md](CONTEXT.md).

## Attribution

Segment and area data ©swisstopo. The base map is the swisstopo light base map, with the attributions that the app shows on each map.

## License

Copyright © 2026 Maximilian Walterskirchen. All rights reserved.

The source code is public so that people can read it. It has no open-source license. You may not copy, change or distribute it without written permission.

The swisstopo data in the map packages is not covered by this notice. It stays under the [terms of use of swisstopo](https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices), which require the attribution "©swisstopo".
