# Map build

The map build turns swisstopo data into a map package for the app. It runs on the developer's Mac and is not part of the app. The package format is in [PACKAGE_FORMAT.md](PACKAGE_FORMAT.md).

It needs [uv](https://docs.astral.sh/uv/), Make and [tippecanoe](https://github.com/felt/tippecanoe) (`brew install tippecanoe`), which makes the map tiles.

## Build the map packages

```sh
make packages
```

The first time, this command downloads swissTLM3D (4.8 GB) and swissBOUNDARIES3D into `data/`. Then it writes one map package for each canton that the app includes: `../map-packages/zh.sqlite` and `../map-packages/ag.sqlite`. The iOS app bundles these files. Each run takes about half a minute for each canton.

The top of the `Makefile` sets the releases of the two datasets. `MAP_RELEASE` is the map release identifier in the package. It is the swissTLM3D release, with a number for each new build of that release with other rules, for example `2026-02.1`. Increase it when the rules change, so that the app matches all walks again. `CANTONS` lists the cantons.

To build other areas, call the build directly. Give `--canton` with the abbreviation of a canton, or one `--area` with the BFS number of each Gemeinde:

```sh
uv run mapbuild --tlm data/SWISSTLM3D_2026_LV95_LN02.gpkg \
  --boundaries data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg \
  --dog-ban-zones dog_ban_zones.geojson \
  --area 243 --map-release 2026-02 --out dietikon.sqlite
```

## Rules

- Ways that a dog cannot or must not use are not segments. These are the way classes (`objektart`) Autobahn, Autostrasse, Ausfahrt, Einfahrt, Zufahrt, Dienstzufahrt, Autozug, Faehre, Klettersteig and Raststaette, ways with the restriction (`verkehrsbeschraenkung`) Gesperrt or Gesicherte Kletterpartie, and ways with the hiking category (`wanderwege`) Alpinwanderweg. All other ways are segments, including Bergwanderwege.
- The parts of ways inside a dog-ban zone are not segments. When in doubt, the build leaves a way out: fewer segments are better than segments that a dog must not walk.
- The build cuts ways at the Gemeinde boundaries, so that each segment lies in exactly one area. The build leaves out a cut piece shorter than 1 cm. Such slivers come from ways that end a fraction of a millimetre behind a boundary.
- A segment runs between two junctions, or between a junction and a dead end. swissTLM3D also splits a way where one of its attributes changes. The build joins such pieces into one segment, unless the area or the street name changes at that point. A junction is a point where three or more ends of usable ways meet. A way that a dog cannot use does not make a junction.
- A segment takes the official street name of its way from the street name tables of swissTLM3D. A street is all segments with the same name in the same area. A way can have the name of a street in the next Gemeinde, for example where the street crosses the border. Its segments in this area still belong to the street of this area with that name. Segments with no name belong to no street.

## Dog-ban zones

A dog-ban zone is a zone where dogs are banned all year or can be banned, for example a cemetery, a school, a sports ground or the Swiss National Park. Seasonal rules and leash rules do not make a dog-ban zone.

Most zones come from the areas of swissTLM3D. `DOG_BAN_AREA_CLASSES` in `build.py` lists their classes (`objektart`):

- Cemeteries, school and university grounds, hospital grounds and allotment gardens.
- Sports grounds, swimming pools, zoos, golf courses, amusement parks and horse race tracks.
- Sites that are closed to the public: prisons, quarries, landfills, sewage plants, waste incinerators, substations and power plants.
- The Swiss National Park.

Public parks, vineyards, orchards, campsites and military training grounds are not dog-ban zones, because dogs can usually walk there.

Zones that swissTLM3D does not show, for example a wildlife rest zone with an access ban all year, are kept by hand in `dog_ban_zones.geojson`. Each feature is one zone as a polygon in WGS84. The file is empty at the moment. The build reads any vector file that GDAL reads, in any coordinate system.

## Tests

```sh
make test
```

The tests run the build on a small fixture in `tests/fixtures/`. The fixture is a cut of the real swissTLM3D and swissBOUNDARIES3D data, about 2.4 km by 2.4 km on the border between Dietikon and Spreitenbach. It keeps the layer names and columns of the real GeoPackages, with the ways, the street names and the areas of the dog-ban zone classes. To cut it again from the downloads, run `make fixture`. The fixture also has one invented dog-ban zone in Dietikon, in `dog_ban_zones.geojson`.

The engine tests of the app read a map package that the build makes from this fixture: `../ios/gassipassTests/MapPackages/fixture.sqlite`. When the rules change, make it again and check it in:

```sh
make test-package
```
