"""Turn swissTLM3D and swissBOUNDARIES3D into one map package.

The format of the package is the contract with the app. See PACKAGE_FORMAT.md.
"""

import json
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pyogrio.raw
import shapely
from pyproj import Transformer

FORMAT_VERSION = 4

GEMEINDE_LAYER = "tlm_hoheitsgebiet"
WAY_LAYER = "tlm_strassen_strasse"
# The street names, and the link table between the names and the ways.
NAME_LAYER = "tlm_strassen_strassenname"
NAME_LINK_LAYER = "tlm_strassen_strassenname_strasse"

CANTONS = {
    1: "ZH", 2: "BE", 3: "LU", 4: "UR", 5: "SZ", 6: "OW", 7: "NW", 8: "GL",
    9: "ZG", 10: "FR", 11: "SO", 12: "BS", 13: "BL", 14: "SH", 15: "AR",
    16: "AI", 17: "SG", 18: "GR", 19: "AG", 20: "TG", 21: "TI", 22: "VD",
    23: "VS", 24: "NE", 25: "GE", 26: "JU",
}
CANTON_NUMBERS = {abbreviation: number for number, abbreviation in CANTONS.items()}

# The fid of a segment is the canton number times this, plus a running
# number, so that it is unique across the packages of all cantons.
FIDS_PER_CANTON = 10_000_000

# The zoom levels of the map tiles. The app shows no segments below the
# lowest one, and zooms the tiles of the highest one further in.
TILE_MIN_ZOOM = 12
TILE_MAX_ZOOM = 14
TILE_LAYER = "segments"

# Ways that a dog cannot or must not use. They are not segments.
EXCLUDED_WAY_CLASSES = frozenset({
    "Autobahn", "Autostrasse", "Ausfahrt", "Einfahrt", "Zufahrt", "Dienstzufahrt",
    "Autozug", "Faehre", "Klettersteig", "Raststaette",
})
EXCLUDED_RESTRICTIONS = frozenset({"Gesperrt", "Gesicherte Kletterpartie"})
EXCLUDED_HIKING_CATEGORIES = frozenset({"Alpinwanderweg"})

# Some ways end a fraction of a millimetre behind a Gemeinde boundary. The cut
# leaves a sliver in the next Gemeinde. Pieces that a cut makes shorter than
# this are not segments.
MIN_CUT_PIECE_LENGTH_M = 0.01

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
    boundary BLOB NOT NULL,
    segment_count INTEGER NOT NULL DEFAULT 0,
    length_m REAL NOT NULL DEFAULT 0
);
CREATE TABLE streets (
    area INTEGER NOT NULL REFERENCES areas (bfs_number),
    name TEXT NOT NULL,
    segment_count INTEGER NOT NULL,
    length_m REAL NOT NULL,
    PRIMARY KEY (area, name)
) WITHOUT ROWID;
CREATE TABLE segments (
    fid INTEGER PRIMARY KEY,
    -- Unique, but without an index: the app never looks a segment up by it.
    -- The build checks it instead.
    id TEXT NOT NULL,
    area INTEGER NOT NULL REFERENCES areas (bfs_number),
    way_class TEXT NOT NULL,
    street TEXT,
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
class Way:
    """A way of swissTLM3D that a dog can use."""

    uuid: str
    way_class: str
    street: str | None
    line: shapely.LineString  # LV95
    # The parts of the way outside the dog-ban zones, in LV95.
    usable: shapely.LineString | shapely.MultiLineString
    cut_by_zone: bool


@dataclass
class Segment:
    id: str
    way_class: str
    street: str | None
    line: shapely.LineString  # LV95, so that its length is in metres


def build_package(
    tlm: Path,
    boundaries: Path,
    areas: list[int],
    map_release: str,
    out: Path,
    dog_ban_zones: Path | None = None,
) -> None:
    zones = read_dog_ban_zones(dog_ban_zones) if dog_ban_zones else None
    gemeinden = read_gemeinden(boundaries, areas)
    ways = read_ways(
        tlm, shapely.union_all([g.boundary for g in gemeinden]).bounds, zones
    )
    way_ends = count_way_ends(ways)
    way_index = shapely.STRtree([way.usable for way in ways])

    out.unlink(missing_ok=True)
    connection = sqlite3.connect(out)
    connection.executescript(SCHEMA)
    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [("format_version", str(FORMAT_VERSION)), ("map_release", map_release)],
    )
    fids = Counter()
    for gemeinde in gemeinden:
        connection.execute(
            "INSERT INTO areas (bfs_number, name, canton, boundary) VALUES (?, ?, ?, ?)",
            (
                gemeinde.bfs_number,
                gemeinde.name,
                gemeinde.canton,
                shapely.to_wkb(to_wgs84(gemeinde.boundary)),
            ),
        )
        nearby = [ways[i] for i in way_index.query(gemeinde.boundary, predicate="intersects")]
        for segment in join_pieces(pieces_in(gemeinde, nearby), way_ends):
            line = to_wgs84(segment.line)
            canton = CANTON_NUMBERS[gemeinde.canton]
            fids[canton] += 1
            fid = canton * FIDS_PER_CANTON + fids[canton]
            connection.execute(
                "INSERT INTO segments (fid, id, area, way_class, street, length_m, geometry)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    fid,
                    segment.id,
                    gemeinde.bfs_number,
                    segment.way_class,
                    segment.street,
                    segment.line.length,
                    shapely.to_wkb(line),
                ),
            )
            min_lon, min_lat, max_lon, max_lat = line.bounds
            connection.execute(
                "INSERT INTO segments_index (fid, min_lon, max_lon, min_lat, max_lat)"
                " VALUES (?, ?, ?, ?, ?)",
                (fid, min_lon, max_lon, min_lat, max_lat),
            )
    check_unique_ids(connection)
    write_totals(connection)
    connection.commit()
    write_tiles(connection, name=out.stem)
    # The package is read-only in the app, so it needs no free pages.
    connection.execute("VACUUM")
    connection.close()


def write_tiles(connection: sqlite3.Connection, name: str) -> None:
    """Write the segments as vector tiles into the tables of the MBTiles
    format, so that the map of the app draws them without reading the
    segments. Each feature has the fid of its segment as its ID, and the area
    of the segment as its only property."""
    tippecanoe = shutil.which("tippecanoe")
    if tippecanoe is None:
        raise RuntimeError("The map build needs tippecanoe: brew install tippecanoe")
    with tempfile.TemporaryDirectory() as directory:
        features = Path(directory) / "segments.geojsonl"
        tiles = Path(directory) / "tiles.mbtiles"
        with features.open("w") as file:
            for fid, area, geometry in connection.execute(
                "SELECT fid, area, geometry FROM segments"
            ):
                feature = {
                    "type": "Feature",
                    "id": fid,
                    "properties": {"area": area},
                    "geometry": shapely.geometry.mapping(shapely.from_wkb(geometry)),
                }
                file.write(json.dumps(feature) + "\n")
        subprocess.run(
            [
                tippecanoe, "--quiet", "--force", "--output", str(tiles),
                "--name", name, "--layer", TILE_LAYER,
                f"--minimum-zoom={TILE_MIN_ZOOM}", f"--maximum-zoom={TILE_MAX_ZOOM}",
                # Every segment must show, at every zoom level.
                "--no-feature-limit", "--no-tile-size-limit",
                "--read-parallel", str(features),
            ],
            check=True,
        )
        connection.execute("ATTACH DATABASE ? AS tiles", (str(tiles),))
        connection.executescript(
            """
            CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT);
            INSERT INTO metadata SELECT name, value FROM tiles.metadata
                WHERE name != 'generator_options';
            CREATE TABLE tiles (
                zoom_level INTEGER NOT NULL,
                tile_column INTEGER NOT NULL,
                tile_row INTEGER NOT NULL,
                tile_data BLOB NOT NULL,
                PRIMARY KEY (zoom_level, tile_column, tile_row)
            );
            INSERT INTO tiles SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles.tiles;
            """
        )
        connection.commit()
        connection.execute("DETACH DATABASE tiles")


def check_unique_ids(connection: sqlite3.Connection) -> None:
    """Raise an error if two segments have the same identifier."""
    duplicates = connection.execute(
        "SELECT id FROM segments GROUP BY id HAVING count(*) > 1 LIMIT 5"
    ).fetchall()
    if duplicates:
        raise ValueError(f"Segment identifiers are not unique: {[id for (id,) in duplicates]}")


def write_totals(connection: sqlite3.Connection) -> None:
    """Store the number and total length of the segments of each area and
    each street, so that the app does not add them up at each start."""
    connection.execute(
        """
        UPDATE areas SET
            segment_count = totals.segment_count, length_m = totals.length_m
        FROM (
            SELECT area, count(*) AS segment_count, sum(length_m) AS length_m
            FROM segments GROUP BY area
        ) AS totals
        WHERE areas.bfs_number = totals.area
        """
    )
    connection.execute(
        """
        INSERT INTO streets (area, name, segment_count, length_m)
        SELECT area, street, count(*), sum(length_m)
        FROM segments WHERE street IS NOT NULL
        GROUP BY area, street
        """
    )


def read_layer(path: Path, layer: str, columns: list[str], **read_filter):
    """Read one layer. Return the WKB geometries and the columns by name."""
    meta, _, geometry, field_data = pyogrio.raw.read(
        path, layer=layer, columns=columns, **read_filter
    )
    return geometry, dict(zip(meta["fields"], field_data))


def read_dog_ban_zones(path: Path):
    """Read the dog-ban zones from any vector file, as one geometry in LV95."""
    meta, _, geometry, _ = pyogrio.raw.read(path, columns=[])
    to_lv95 = Transformer.from_crs(meta["crs"], "EPSG:2056", always_xy=True)
    zones = shapely.union_all(shapely.force_2d(shapely.from_wkb(geometry)))
    zones = shapely.transform(
        zones, lambda xy: np.column_stack(to_lv95.transform(xy[:, 0], xy[:, 1]))
    )
    shapely.prepare(zones)
    return zones


def areas_of_canton(boundaries: Path, canton: str) -> list[int]:
    """The BFS numbers of all Gemeinden of a canton, for example "ZH"."""
    (number,) = [n for n, abbreviation in CANTONS.items() if abbreviation == canton]
    _, fields = read_layer(
        boundaries,
        GEMEINDE_LAYER,
        ["bfs_nummer"],
        where=f"objektart = 'Gemeindegebiet' AND kantonsnummer = {number}",
    )
    return sorted({int(n) for n in fields["bfs_nummer"]})


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
    for gemeinde in gemeinden.values():
        shapely.prepare(gemeinde.boundary)
    return list(gemeinden.values())


def read_ways(tlm: Path, bounds, zones) -> list[Way]:
    """Read the ways of swissTLM3D in these bounds that a dog can use.

    The parts of the ways inside a dog-ban zone are removed.
    """
    streets = read_street_names(tlm)
    geometry, fields = read_layer(
        tlm,
        WAY_LAYER,
        ["uuid", "objektart", "verkehrsbeschraenkung", "wanderwege"],
        bbox=tuple(bounds),
    )
    can_use = ~(
        np.isin(fields["objektart"], list(EXCLUDED_WAY_CLASSES))
        | np.isin(fields["verkehrsbeschraenkung"], list(EXCLUDED_RESTRICTIONS))
        | np.isin(fields["wanderwege"], list(EXCLUDED_HIKING_CATEGORIES))
    )
    ways = []
    for uuid, way_class, wkb in zip(
        fields["uuid"][can_use], fields["objektart"][can_use], geometry[can_use]
    ):
        line = shapely.force_2d(shapely.from_wkb(wkb))
        cut_by_zone = zones is not None and zones.intersects(line)
        usable_part = line.difference(zones) if cut_by_zone else line
        if usable_part.length > 0:
            ways.append(Way(
                str(uuid), str(way_class), streets.get(str(uuid)), line, usable_part, cut_by_zone
            ))
    return ways


def read_street_names(tlm: Path) -> dict[str, str]:
    """The official street name of each named way, by the UUID of the way.

    The names come from the link table between names and ways, not from the
    position of the ways. A way with names in several languages, for example
    in Biel/Bienne, gets all its names in text order, joined by " / ".
    """
    _, names = read_layer(tlm, NAME_LAYER, ["uuid", "name"])
    name_of = dict(zip(names["uuid"], names["name"]))
    _, links = read_layer(tlm, NAME_LINK_LAYER, ["tlm_strasse_uuid", "tlm_strassenname_uuid"])
    names_of_way: dict[str, set[str]] = {}
    for way, name in zip(links["tlm_strasse_uuid"], links["tlm_strassenname_uuid"]):
        if name in name_of:
            names_of_way.setdefault(str(way), set()).add(str(name_of[name]))
    return {way: " / ".join(sorted(names)) for way, names in names_of_way.items()}


def node_key(coordinate) -> tuple[float, float]:
    """The key of a point where ways meet, rounded to a millimetre."""
    return (round(coordinate[0], 3), round(coordinate[1], 3))


def count_way_ends(ways: list[Way]) -> Counter:
    """Count how many ends of usable ways meet at each point.

    One end is a dead end, two ends meet without a junction, and three or more
    ends make a junction. A way that a dog cannot use does not make a junction.
    """
    ends = Counter()
    for way in ways:
        for part in line_parts(way.usable):
            ends[node_key(part.coords[0])] += 1
            ends[node_key(part.coords[-1])] += 1
    return ends


def pieces_in(gemeinde: Gemeinde, ways: list[Way]) -> list[Segment]:
    """Cut the ways at the boundary of one Gemeinde.

    Each piece inside the Gemeinde can become a segment. A way that lies fully
    inside keeps its swissTLM3D UUID as the identifier. A way that the boundary
    or a dog-ban zone cuts gets the identifier `{uuid}:{bfs_number}:{n}`, where
    n counts the pieces in the order along the way. Slivers from the cut are
    left out.
    """
    boundary = gemeinde.boundary
    pieces = []
    for way in ways:
        if not way.cut_by_zone and boundary.covers(way.line):
            pieces.append(Segment(way.uuid, way.way_class, way.street, way.line))
            continue
        parts = sorted(
            (
                part
                for part in line_parts(boundary.intersection(way.usable))
                if part.length >= MIN_CUT_PIECE_LENGTH_M
            ),
            key=lambda part: min(
                way.line.project(shapely.Point(part.coords[0])),
                way.line.project(shapely.Point(part.coords[-1])),
            ),
        )
        for index, part in enumerate(parts, start=1):
            pieces.append(
                Segment(
                    f"{way.uuid}:{gemeinde.bfs_number}:{index}", way.way_class, way.street, part
                )
            )
    return pieces


def join_pieces(pieces: list[Segment], way_ends: Counter) -> list[Segment]:
    """Join the pieces of one Gemeinde that meet without a junction.

    swissTLM3D also splits a way where one of its attributes changes. Such
    pieces become one segment, unless the street name changes there, so that
    each segment belongs to one street or to none. A joined segment takes the
    smallest identifier of its pieces, and the way class of its longest piece.
    """
    ends_here: dict[tuple[float, float], list[int]] = {}
    for index, piece in enumerate(pieces):
        for coordinate in (piece.line.coords[0], piece.line.coords[-1]):
            ends_here.setdefault(node_key(coordinate), []).append(index)

    parent = list(range(len(pieces)))  # union-find over the pieces

    def root(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for point, indices in ends_here.items():
        # A point where the Gemeinde boundary cuts a way is not in way_ends.
        if (
            way_ends[point] == 2
            and len(indices) == 2
            and indices[0] != indices[1]
            and pieces[indices[0]].street == pieces[indices[1]].street
        ):
            parent[root(indices[0])] = root(indices[1])

    groups: dict[int, list[Segment]] = {}
    for index, piece in enumerate(pieces):
        groups.setdefault(root(index), []).append(piece)

    segments = []
    for members in groups.values():
        if len(members) == 1:
            segments.append(members[0])
            continue
        line = shapely.line_merge(shapely.MultiLineString([m.line for m in members]))
        if line.geom_type != "LineString":
            raise ValueError(f"The pieces {[m.id for m in members]} do not form one line")
        segments.append(
            Segment(
                id=min(m.id for m in members),
                way_class=max(members, key=lambda m: m.line.length).way_class,
                street=members[0].street,
                line=line,
            )
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
