# Map build

The map build turns swisstopo data into a map package for the app. It runs on the developer's Mac and is not part of the app. The package format is in [PACKAGE_FORMAT.md](PACKAGE_FORMAT.md).

It needs [uv](https://docs.astral.sh/uv/) and Make.

## Build the Dietikon package

```sh
make dietikon
```

The first time, this command downloads swissTLM3D (4.8 GB) and swissBOUNDARIES3D into `data/`. Then it writes `../doggo/MapPackages/dietikon.sqlite`. The app bundles this file.

The top of the `Makefile` sets the releases of the two datasets. `TLM_RELEASE` is also the map release identifier in the package.

To build other areas, call the build directly. Give one `--area` with the BFS number of each Gemeinde:

```sh
uv run mapbuild --tlm data/SWISSTLM3D_2026_LV95_LN02.gpkg \
  --boundaries data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg \
  --area 243 --map-release 2026-02 --out dietikon.sqlite
```

## Rules

In this version, each way of `TLM_STRASSE` that lies in the Gemeinde becomes a segment. The build cuts ways at the Gemeinde boundary, so that each segment lies in exactly one area. The full rules follow later.

## Tests

```sh
make test
```

The tests run the build on a small fixture in `tests/fixtures/`. The fixture is a cut of the real swissTLM3D and swissBOUNDARIES3D data, about 2.4 km by 2.4 km on the border between Dietikon and Spreitenbach. It keeps the layer names and columns of the real GeoPackages. To cut it again from the downloads, run `make fixture`.

The collection engine tests in the app use a map package that the build makes from this fixture. Run `make test-package` to write it again to `../doggoTests/Fixtures/dietikon-fixture.sqlite`, for example after a change to the rules or the format.
