import argparse
from pathlib import Path

from mapbuild.build import build_package


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="mapbuild",
        description="Build a doggo map package from swissTLM3D and swissBOUNDARIES3D.",
    )
    parser.add_argument("--tlm", type=Path, required=True, help="swissTLM3D GeoPackage")
    parser.add_argument(
        "--boundaries", type=Path, required=True, help="swissBOUNDARIES3D GeoPackage"
    )
    parser.add_argument(
        "--area",
        type=int,
        action="append",
        required=True,
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
        areas=args.areas,
        map_release=args.map_release,
        out=args.out,
    )
    print(f"Wrote {args.out}")
