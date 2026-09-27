import shutil
import sqlite3
from pathlib import Path

import pyogrio.raw
import pytest
import shapely
from pyproj import Geod, Transformer

from mapbuild.build import WAY_LAYER, areas_of_canton, build_package

FIXTURES = Path(__file__).parent / "fixtures"
FIXTURE_TLM = FIXTURES / "swisstlm3d.gpkg"
DIETIKON = 243
SPREITENBACH = 4040
OETWIL_AN_DER_LIMMAT = 246
WGS84 = Geod(ellps="WGS84")
LV95_TO_WGS84 = Transformer.from_crs("EPSG:2056", "EPSG:4326", always_xy=True)

# Ways of the fixture that lie inside Dietikon and have a junction at both ends.
JUNCTION_TO_JUNCTION_WAYS = [
    "{6D2A2C2A-A352-4B88-B420-4C2566488C81}",
    "{949B68E5-C04C-49F6-9730-A5C7500246BF}",
    "{1AE64CAB-34A7-4D4F-AA3F-A4935B26987A}",
]


@pytest.fixture(scope="module")
def package(tmp_path_factory) -> sqlite3.Connection:
    out = tmp_path_factory.mktemp("package") / "dietikon.sqlite"
    build_package(
        tlm=FIXTURES / "swisstlm3d.gpkg",
        boundaries=FIXTURES / "swissboundaries3d.gpkg",
        areas=[DIETIKON],
        map_release="2026-02",
        out=out,
    )
    connection = sqlite3.connect(out)
    yield connection
    connection.close()


def test_package_names_its_map_release(package):
    (release,) = package.execute(
        "SELECT value FROM meta WHERE key = 'map_release'"
    ).fetchone()
    assert release == "2026-02"


def test_package_has_the_dietikon_area(package):
    rows = package.execute("SELECT bfs_number, name, canton FROM areas").fetchall()
    assert rows == [(DIETIKON, "Dietikon", "ZH")]


def read_segments(package) -> list[dict]:
    rows = package.execute(
        "SELECT id, area, way_class, length_m, geometry FROM segments"
    ).fetchall()
    return [
        {
            "id": id,
            "area": area,
            "way_class": way_class,
            "length_m": length_m,
            "geometry": shapely.from_wkb(geometry),
        }
        for id, area, way_class, length_m, geometry in rows
    ]


def test_segments_lie_in_dietikon_in_wgs84(package):
    segments = read_segments(package)
    (boundary,) = package.execute(
        "SELECT boundary FROM areas WHERE bfs_number = ?", (DIETIKON,)
    ).fetchone()
    dietikon = shapely.from_wkb(boundary)

    assert len(segments) > 200
    for segment in segments:
        assert segment["area"] == DIETIKON
        assert segment["geometry"].geom_type == "LineString"
        for lon, lat in segment["geometry"].coords:
            # Dietikon lies at about 8.40° east and 47.40° north.
            assert 8.35 < lon < 8.45
            assert 47.38 < lat < 47.43
        assert dietikon.buffer(1e-6).covers(segment["geometry"])


def test_segment_lengths_match_the_geometry(package):
    for segment in read_segments(package):
        geodesic_length = WGS84.geometry_length(segment["geometry"])
        assert segment["length_m"] > 0
        assert segment["length_m"] == pytest.approx(geodesic_length, rel=1e-3, abs=0.01)


def test_the_boundary_cut_leaves_no_slivers(tmp_path):
    # Some ways end a fraction of a millimetre behind the Gemeinde boundary.
    segments = read_segments(build(tmp_path, areas=[DIETIKON, SPREITENBACH]))
    assert min(s["length_m"] for s in segments) > 0.01


def test_segment_ids_are_unique_and_segments_have_a_way_class(package):
    segments = read_segments(package)
    assert len({s["id"] for s in segments}) == len(segments)
    assert {"4m Strasse", "2m Weg"} <= {s["way_class"] for s in segments}


def segments_near(package, lon: float, lat: float, margin: float) -> set[str]:
    rows = package.execute(
        "SELECT s.id FROM segments_index i JOIN segments s ON s.fid = i.fid"
        " WHERE i.max_lon >= ? AND i.min_lon <= ? AND i.max_lat >= ? AND i.min_lat <= ?",
        (lon - margin, lon + margin, lat - margin, lat + margin),
    ).fetchall()
    return {id for (id,) in rows}


def test_spatial_index_finds_the_segments_near_a_point(package):
    segments = read_segments(package)
    for segment in segments[::25]:
        point = segment["geometry"].interpolate(0.5, normalized=True)
        assert segment["id"] in segments_near(package, point.x, point.y, 1e-5)


def test_spatial_index_finds_nothing_far_from_dietikon(package):
    # Bern, about 95 km from Dietikon.
    assert segments_near(package, 7.44, 46.95, 0.01) == set()


def test_a_way_across_the_border_gives_unique_segments_in_both_areas(tmp_path):
    out = tmp_path / "two-areas.sqlite"
    build_package(
        tlm=FIXTURES / "swisstlm3d.gpkg",
        boundaries=FIXTURES / "swissboundaries3d.gpkg",
        areas=[DIETIKON, SPREITENBACH],
        map_release="2026-02",
        out=out,
    )
    connection = sqlite3.connect(out)
    segments = read_segments(connection)
    connection.close()

    assert len({s["id"] for s in segments}) == len(segments)
    assert {s["area"] for s in segments} == {DIETIKON, SPREITENBACH}


def build(
    tmp_path, areas=(DIETIKON,), tlm=FIXTURE_TLM, dog_ban_zones=None
) -> sqlite3.Connection:
    out = tmp_path / f"package-{len(list(tmp_path.glob('package-*')))}.sqlite"
    build_package(
        tlm=tlm,
        boundaries=FIXTURES / "swissboundaries3d.gpkg",
        areas=list(areas),
        map_release="2026-02",
        out=out,
        dog_ban_zones=dog_ban_zones,
    )
    return sqlite3.connect(out)


def tlm_with_changes(tmp_path, uuid: str, **columns) -> Path:
    """A copy of the fixture where one way has other attribute values."""
    tlm = tmp_path / "swisstlm3d.gpkg"
    shutil.copy(FIXTURE_TLM, tlm)
    meta, _, geometry, field_data = pyogrio.raw.read(tlm, layer=WAY_LAYER)
    fields = dict(zip(meta["fields"], field_data))
    (row,) = (fields["uuid"] == uuid).nonzero()[0]
    for column, value in columns.items():
        fields[column][row] = value
    pyogrio.raw.write(
        tlm,
        geometry=geometry,
        field_data=list(fields.values()),
        fields=meta["fields"],
        layer=WAY_LAYER,
        driver="GPKG",
        crs=meta["crs"],
        geometry_type=meta["geometry_type"],
        layer_options={"OVERWRITE": "YES"},
    )
    return tlm


def way_in_wgs84(uuid: str) -> shapely.LineString:
    _, _, geometry, _ = pyogrio.raw.read(
        FIXTURE_TLM, layer=WAY_LAYER, columns=[], where=f"uuid = '{uuid}'"
    )
    way = shapely.force_2d(shapely.from_wkb(geometry[0]))
    return shapely.LineString(zip(*LV95_TO_WGS84.transform(*zip(*way.coords))))


def segments_at(package, point: shapely.Point) -> list[dict]:
    """The segments that pass through a point, to within about a centimetre."""
    ids = segments_near(package, point.x, point.y, 1e-6)
    return [
        s for s in read_segments(package)
        if s["id"] in ids and s["geometry"].distance(point) < 1e-7
    ]


def segment_ids_along(package, uuid: str) -> set[str]:
    way = way_in_wgs84(uuid)
    return {
        s["id"] for s in segments_at(package, way.interpolate(0.5, normalized=True))
    }


@pytest.mark.parametrize(
    "columns",
    [
        {"objektart": way_class}
        for way_class in [
            "Autobahn", "Autostrasse", "Ausfahrt", "Einfahrt", "Zufahrt",
            "Dienstzufahrt", "Autozug", "Faehre", "Klettersteig", "Raststaette",
        ]
    ]
    + [
        {"verkehrsbeschraenkung": "Gesperrt"},
        {"verkehrsbeschraenkung": "Gesicherte Kletterpartie"},
        {"wanderwege": "Alpinwanderweg"},
    ],
    ids=lambda columns: next(iter(columns.values())),
)
def test_ways_that_a_dog_cannot_use_are_not_segments(tmp_path, columns):
    way = JUNCTION_TO_JUNCTION_WAYS[0]
    assert segment_ids_along(build(tmp_path), way)

    changed = tlm_with_changes(tmp_path, way, **columns)
    assert segment_ids_along(build(tmp_path, tlm=changed), way) == set()


def test_bergwanderwege_are_segments(tmp_path):
    way = JUNCTION_TO_JUNCTION_WAYS[0]
    changed = tlm_with_changes(tmp_path, way, wanderwege="Bergwanderweg")
    assert segment_ids_along(build(tmp_path, tlm=changed), way)


def test_ways_inside_a_dog_ban_zone_are_not_segments(tmp_path):
    zones = FIXTURES / "dog_ban_zones.geojson"
    _, _, geometry, _ = pyogrio.raw.read(zones)
    zone = shapely.from_wkb(geometry[0])
    inside = zone.buffer(-1e-6)

    without_zone = read_segments(build(tmp_path))
    assert any(s["geometry"].intersects(inside) for s in without_zone)

    with_zone = read_segments(build(tmp_path, dog_ban_zones=zones))
    assert not any(s["geometry"].intersects(inside) for s in with_zone)
    # Ways that cross the edge of the zone keep their part outside the zone.
    assert any(
        s["geometry"].intersects(zone.buffer(1e-6)) and s["geometry"].length > 1e-4
        for s in with_zone
    )


def test_a_way_across_the_border_becomes_one_segment_in_each_area(tmp_path):
    package = build(tmp_path, areas=[DIETIKON, SPREITENBACH])
    # A 3m Strasse of about 700 m. About 250 m lie in Dietikon.
    way = way_in_wgs84("{10533BF1-2E4F-4D93-9FEE-EA89838C2F6A}")

    segments = {}
    for fraction in [i / 50 for i in range(1, 50)]:
        for segment in segments_at(package, way.interpolate(fraction, normalized=True)):
            segments[segment["id"]] = segment["area"]

    assert sorted(segments.values()) == [DIETIKON, SPREITENBACH]


def test_pieces_that_meet_without_a_junction_become_one_segment(tmp_path):
    package = build(tmp_path)
    # swissTLM3D splits this way where the way class changes from 2m Weg to
    # 3m Strasse. No other way meets it there.
    footpath = segment_ids_along(package, "{D4683EB9-AE1A-4DAE-9E11-7024F27711A1}")
    road = segment_ids_along(package, "{021760C1-2CCA-436E-B38A-8B485F74ED8A}")

    assert len(footpath) == 1
    assert footpath == road


def test_a_way_between_two_junctions_stays_one_segment(tmp_path):
    package = build(tmp_path)
    for uuid in JUNCTION_TO_JUNCTION_WAYS:
        way = way_in_wgs84(uuid)
        (segment,) = segments_at(package, way.interpolate(0.5, normalized=True))
        assert shapely.normalize(segment["geometry"]).equals_exact(shapely.normalize(way), 1e-9)


def test_a_canton_has_all_its_gemeinden_as_areas():
    # The fixture holds three Gemeinden: two in canton Zürich, one in canton Aargau.
    boundaries = FIXTURES / "swissboundaries3d.gpkg"
    assert areas_of_canton(boundaries, "ZH") == [DIETIKON, OETWIL_AN_DER_LIMMAT]
    assert areas_of_canton(boundaries, "AG") == [SPREITENBACH]
