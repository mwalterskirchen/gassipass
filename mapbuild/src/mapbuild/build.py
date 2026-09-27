"""Turn swissTLM3D and swissBOUNDARIES3D into one map package.

The format of the package is the contract with the app. See PACKAGE_FORMAT.md.
"""

import sqlite3
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pyogrio.raw
import shapely
from pyproj import Transformer

FORMAT_VERSION = 1

GEMEINDE_LAYER = "tlm_hoheitsgebiet"
WAY_LAYER = "tlm_strassen_strasse"

CANTONS = {
    1: "ZH", 2: "BE", 3: "LU", 4: "UR", 5: "SZ", 6: "OW", 7: "NW", 8: "GL",
    9: "ZG", 10: "FR", 11: "SO", 12: "BS", 13: "BL", 14: "SH", 15: "AR",
    16: "AI", 17: "SG", 18: "GR", 19: "AG", 20: "TG", 21: "TI", 22: "VD",
    23: "VS", 24: "NE", 25: "GE", 26: "JU",
}

LV95_TO_WGS84 = Transformer.from_crs("EPSG:2056", "EPSG:4326", always_xy=True)

SCHEMA = """
CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE areas (
    bfs_number INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    canton TEXT NOT NULL,
    boundary BLOB NOT NULL
);
CREATE TABLE segments (
    fid INTEGER PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    area INTEGER NOT NULL REFERENCES areas (bfs_number),
    way_class TEXT NOT NULL,
    length_m REAL NOT NULL,
    geometry BLOB NOT NULL
);
CREATE VIRTUAL TABLE segments_index USING rtree (
    fid,
    min_lon, max_lon,
    min_lat, max_lat
);
"""


def to_wgs84(geometry):
    """Convert a 2D geometry from LV95 to WGS84 longitude and latitude."""
    return shapely.transform(
        geometry,
        lambda xy: np.column_stack(LV95_TO_WGS84.transform(xy[:, 0], xy[:, 1])),
    )


@dataclass
class Gemeinde:
    bfs_number: int
    name: str
    canton: str
    boundary: shapely.MultiPolygon  # LV95


@dataclass
class SegmentPiece:
    id: str
    way_class: str
    line: shapely.LineString  # LV95, so that its length is in metres


def build_package(
    tlm: Path, boundaries: Path, areas: list[int], map_release: str, out: Path
) -> None:
    out.unlink(missing_ok=True)
    connection = sqlite3.connect(out)
    connection.executescript(SCHEMA)
    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [("format_version", str(FORMAT_VERSION)), ("map_release", map_release)],
    )
    for gemeinde in read_gemeinden(boundaries, areas):
        connection.execute(
            "INSERT INTO areas (bfs_number, name, canton, boundary) VALUES (?, ?, ?, ?)",
            (
                gemeinde.bfs_number,
                gemeinde.name,
                gemeinde.canton,
                shapely.to_wkb(to_wgs84(gemeinde.boundary)),
            ),
        )
        for segment in segments_in(tlm, gemeinde):
            line = to_wgs84(segment.line)
            cursor = connection.execute(
                "INSERT INTO segments (id, area, way_class, length_m, geometry)"
                " VALUES (?, ?, ?, ?, ?)",
                (
                    segment.id,
                    gemeinde.bfs_number,
                    segment.way_class,
                    segment.line.length,
                    shapely.to_wkb(line),
                ),
            )
            min_lon, min_lat, max_lon, max_lat = line.bounds
            connection.execute(
                "INSERT INTO segments_index (fid, min_lon, max_lon, min_lat, max_lat)"
                " VALUES (?, ?, ?, ?, ?)",
                (cursor.lastrowid, min_lon, max_lon, min_lat, max_lat),
            )
    connection.commit()
    connection.close()


def read_layer(path: Path, layer: str, columns: list[str], **read_filter):
    """Read one layer. Return the WKB geometries and the columns by name."""
    meta, _, geometry, field_data = pyogrio.raw.read(
        path, layer=layer, columns=columns, **read_filter
    )
    return geometry, dict(zip(meta["fields"], field_data))


def read_gemeinden(boundaries: Path, bfs_numbers: list[int]) -> list[Gemeinde]:
    """Read the Gemeinden with these BFS numbers from swissBOUNDARIES3D.

    A Gemeinde with several rows becomes one Gemeinde with the union of their
    boundaries.
    """
    numbers = ",".join(str(int(n)) for n in bfs_numbers)
    geometry, fields = read_layer(
        boundaries,
        GEMEINDE_LAYER,
        ["bfs_nummer", "name", "kantonsnummer"],
        where=f"objektart = 'Gemeindegebiet' AND bfs_nummer IN ({numbers})",
    )
    gemeinden: dict[int, Gemeinde] = {}
    for bfs_number, name, canton, wkb in zip(
        fields["bfs_nummer"], fields["name"], fields["kantonsnummer"], geometry
    ):
        bfs_number = int(bfs_number)
        boundary = shapely.force_2d(shapely.from_wkb(wkb))
        if bfs_number in gemeinden:
            boundary = shapely.union(gemeinden[bfs_number].boundary, boundary)
        gemeinden[bfs_number] = Gemeinde(
            bfs_number=bfs_number,
            name=str(name),
            canton=CANTONS[int(canton)],
            boundary=boundary,
        )
    return list(gemeinden.values())


def segments_in(tlm: Path, gemeinde: Gemeinde) -> list[SegmentPiece]:
    """Cut the ways of swissTLM3D at the boundary of one Gemeinde.

    Each piece inside the Gemeinde becomes a segment. A way that lies fully
    inside keeps its swissTLM3D UUID as the segment identifier. A way that the
    boundary cuts gets the identifier `{uuid}:{bfs_number}:{n}`, where n counts
    the pieces in the order along the way.
    """
    boundary = gemeinde.boundary
    geometry, fields = read_layer(
        tlm, WAY_LAYER, ["uuid", "objektart"], bbox=tuple(boundary.bounds)
    )
    shapely.prepare(boundary)
    segments = []
    for uuid, way_class, wkb in zip(fields["uuid"], fields["objektart"], geometry):
        way = shapely.force_2d(shapely.from_wkb(wkb))
        if not boundary.intersects(way):
            continue
        if boundary.covers(way):
            segments.append(SegmentPiece(uuid, str(way_class), way))
            continue
        pieces = sorted(
            line_parts(boundary.intersection(way)),
            key=lambda piece: min(
                way.project(shapely.Point(piece.coords[0])),
                way.project(shapely.Point(piece.coords[-1])),
            ),
        )
        for index, piece in enumerate(pieces, start=1):
            segments.append(
                SegmentPiece(f"{uuid}:{gemeinde.bfs_number}:{index}", str(way_class), piece)
            )
    return segments


def line_parts(geometry) -> list[shapely.LineString]:
    """Return the line strings of a clipped way, joined where they touch."""
    lines = [
        part
        for part in shapely.get_parts(geometry)
        if part.geom_type == "LineString" and part.length > 0
    ]
    if len(lines) > 1:
        lines = list(shapely.get_parts(shapely.line_merge(shapely.MultiLineString(lines))))
    return lines
