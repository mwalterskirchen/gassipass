"""Cut the test fixture around Dietikon out of the full swisstopo downloads.

The fixture keeps the layer names and columns of the real GeoPackages, so the
map build reads it exactly like a full download.

    uv run python scripts/cut_fixture.py \
        --tlm data/SWISSTLM3D_2026_LV95_LN02.gpkg \
        --boundaries data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg
"""

import argparse
from pathlib import Path

import pyogrio.raw

from mapbuild.build import GEMEINDE_LAYER, NAME_LAYER, NAME_LINK_LAYER, WAY_LAYER

# A window of about 2.4 km by 2.4 km in LV95 on the border between Dietikon
# and Spreitenbach. It holds part of the town, the A1 motorway with the ramps
# of the Dietikon junction, and the ways that cross the Gemeinde border.
FIXTURE_BBOX = (2669900, 1251300, 2672300, 1253700)

FIXTURE_DIR = Path(__file__).resolve().parent.parent / "tests" / "fixtures"


def copy_layer(source: Path, target: Path, layer: str, **read_filter) -> dict:
    meta, _, geometry, field_data = pyogrio.raw.read(source, layer=layer, **read_filter)
    pyogrio.raw.write(
        target,
        geometry=geometry,
        field_data=field_data,
        fields=meta["fields"],
        layer=layer,
        driver="GPKG",
        crs=meta["crs"],
        geometry_type=meta["geometry_type"],
        encoding=meta.get("encoding"),
        append=target.exists(),
    )
    return dict(zip(meta["fields"], field_data))


def in_list(column: str, values) -> str:
    quoted = ",".join("'" + v.replace("'", "''") + "'" for v in values)
    return f"{column} IN ({quoted})"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tlm", type=Path, required=True)
    parser.add_argument("--boundaries", type=Path, required=True)
    args = parser.parse_args()

    tlm_target = FIXTURE_DIR / "swisstlm3d.gpkg"
    boundaries_target = FIXTURE_DIR / "swissboundaries3d.gpkg"
    for target in (tlm_target, boundaries_target):
        target.unlink(missing_ok=True)

    ways = copy_layer(args.tlm, tlm_target, WAY_LAYER, bbox=FIXTURE_BBOX)

    links = copy_layer(
        args.tlm, tlm_target, NAME_LINK_LAYER,
        where=in_list("tlm_strasse_uuid", ways["uuid"]),
    )
    copy_layer(
        args.tlm, tlm_target, NAME_LAYER,
        where=in_list("uuid", set(links["tlm_strassenname_uuid"])),
    )

    copy_layer(args.boundaries, boundaries_target, GEMEINDE_LAYER, bbox=FIXTURE_BBOX)

    for target in (tlm_target, boundaries_target):
        print(target, target.stat().st_size // 1024, "KiB")


if __name__ == "__main__":
    main()
