import sqlite3
from pathlib import Path

import pytest
import shapely
from pyproj import Geod

from mapbuild.build import build_package

FIXTURES = Path(__file__).parent / "fixtures"
DIETIKON = 243
SPREITENBACH = 4040
WGS84 = Geod(ellps="WGS84")


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

    assert len(segments) > 300
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
