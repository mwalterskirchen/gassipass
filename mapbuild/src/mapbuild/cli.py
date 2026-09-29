import argparse
from pathlib import Path

from mapbuild.build import CANTONS, areas_of_canton, build_package


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="mapbuild",
        description="Build a gassipass map package from swissTLM3D and swissBOUNDARIES3D.",
    )
    parser.add_argument("--tlm", type=Path, required=True, help="swissTLM3D GeoPackage")
    parser.add_argument(
        "--boundaries", type=Path, required=True, help="swissBOUNDARIES3D GeoPackage"
    )
    parser.add_argument(
        "--dog-ban-zones",
        type=Path,
        required=True,
        help="Vector file with the zones where dogs are banned all year",
    )
    areas = parser.add_mutually_exclusive_group(required=True)
    areas.add_argument(
        "--canton",
        type=str.upper,
        choices=sorted(CANTONS.values()),
        help="Include all Gemeinden of this canton, for example zh.",
    )
    areas.add_argument(
        "--area",
        type=int,
        action="append",
        dest="areas",
        help="BFS number of a Gemeinde to include. Repeat for several.",
    )
    parser.add_argument(
        "--map-release", required=True, help="Map release identifier, e.g. 2026-02"
    )
    parser.add_argument("--out", type=Path, required=True, help="Map package to write")
    args = parser.parse_args()

    build_package(
        tlm=args.tlm,
        boundaries=args.boundaries,
        areas=args.areas or areas_of_canton(args.boundaries, args.canton),
        map_release=args.map_release,
        out=args.out,
        dog_ban_zones=args.dog_ban_zones,
    )
    print(f"Wrote {args.out}")
