# Map build

The map build turns swisstopo data into a map package for the app. It runs on the developer's Mac and is not part of the app. The package format is in [PACKAGE_FORMAT.md](PACKAGE_FORMAT.md).

It needs [uv](https://docs.astral.sh/uv/) and Make.

## Build the map packages

```sh
make packages
```

The first time, this command downloads swissTLM3D (4.8 GB) and swissBOUNDARIES3D into `data/`. Then it writes one map package for each canton that the app includes: `../doggo/MapPackages/zh.sqlite` and `../doggo/MapPackages/ag.sqlite`. The app bundles these files. Each run takes about half a minute for each canton.

The top of the `Makefile` sets the releases of the two datasets. `TLM_RELEASE` is also the map release identifier in the package. `CANTONS` lists the cantons.

To build other areas, call the build directly. Give `--canton` with the abbreviation of a canton, or one `--area` with the BFS number of each Gemeinde:

```sh
uv run mapbuild --tlm data/SWISSTLM3D_2026_LV95_LN02.gpkg \
  --boundaries data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg \
  --dog-ban-zones dog_ban_zones.geojson \
  --area 243 --map-release 2026-02 --out dietikon.sqlite
```

## Rules

- Ways that a dog cannot or must not use are not segments. These are the way classes (`objektart`) Autobahn, Autostrasse, Ausfahrt, Einfahrt, Zufahrt, Dienstzufahrt, Autozug, Faehre, Klettersteig and Raststaette, ways with the restriction (`verkehrsbeschraenkung`) Gesperrt or Gesicherte Kletterpartie, and ways with the hiking category (`wanderwege`) Alpinwanderweg. All other ways are segments, including Bergwanderwege.
- The parts of ways inside a dog-ban zone are not segments.
- The build cuts ways at the Gemeinde boundaries, so that each segment lies in exactly one area. The build leaves out a cut piece shorter than 1 cm. Such slivers come from ways that end a fraction of a millimetre behind a boundary.
- A segment runs between two junctions, or between a junction and a dead end. swissTLM3D also splits a way where one of its attributes changes. The build joins such pieces into one segment, unless the area changes at that point. A junction is a point where three or more ends of usable ways meet. A way that a dog cannot use does not make a junction.

## Dog-ban zones

A dog-ban zone is a zone where dogs are banned all year, for example the Swiss National Park, or a wildlife rest zone with an access ban that applies all year. Seasonal rules and leash rules do not make a dog-ban zone.

There is no national dataset of these zones, so the zones are kept by hand in `dog_ban_zones.geojson`. Each feature is one zone as a polygon in WGS84. The file is empty at the moment, because canton Zürich and canton Aargau have no known dog-ban zones. The build reads any vector file that GDAL reads, in any coordinate system.

## Tests

```sh
make test
```

The tests run the build on a small fixture in `tests/fixtures/`. The fixture is a cut of the real swissTLM3D and swissBOUNDARIES3D data, about 2.4 km by 2.4 km on the border between Dietikon and Spreitenbach. It keeps the layer names and columns of the real GeoPackages. To cut it again from the downloads, run `make fixture`. The fixture also has one invented dog-ban zone in Dietikon, in `dog_ban_zones.geojson`.

The engine tests of the app read a map package that the build makes from this fixture: `../doggoTests/MapPackages/fixture.sqlite`. When the rules change, make it again and check it in:

```sh
make test-package
```
