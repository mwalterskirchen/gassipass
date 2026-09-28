# Map package format

A map package is the contract between the map build and the app. It is one SQLite file for each canton, for example `zh.sqlite`. It holds all Gemeinden of the canton as areas. The app bundles the packages and opens them read-only.

This document describes format version 4. Version 2 adds the `street` column to `segments`. Version 3 adds the totals of the areas and the `streets` table, and removes the index on `segments.id`. Version 4 adds the map tiles, and makes `fid` unique across the packages of a map release. When the format changes in a way that an older app cannot read, increase `format_version`. The app refuses a package with a format version that it does not know.

## Coordinates and geometry

All coordinates are WGS84 longitude and latitude in degrees (EPSG:4326). The map build converts them from LV95 (EPSG:2056).

Geometry columns hold 2D WKB (well-known binary) in little-endian byte order. The map build removes the heights.

## Tables

### `meta`

Key-value pairs that describe the package.

| Column  | Type | Meaning |
| ------- | ---- | ------- |
| `key`   | TEXT, primary key | Name of the value |
| `value` | TEXT | The value |

| Key              | Example   | Meaning |
| ---------------- | --------- | ------- |
| `format_version` | `4`       | Version of this format |
| `map_release`    | `2026-02` | The map release: the swissTLM3D release that the package comes from. A different value means that the app must match all walks again. |

### `areas`

One row for each area (Gemeinde) in the package.

| Column       | Type | Meaning |
| ------------ | ---- | ------- |
| `bfs_number` | INTEGER, primary key | The BFS number of the Gemeinde, for example 243 for Dietikon |
| `name`       | TEXT | The official name, for example `Dietikon` |
| `canton`     | TEXT | The two-letter abbreviation of the canton, for example `ZH` |
| `boundary`   | BLOB | WKB MultiPolygon of the Gemeinde boundary |
| `segment_count` | INTEGER | The number of segments in the area |
| `length_m`   | REAL | The total length of the segments in the area, in metres |

### `streets`

One row for each street. The map build adds up the segments of each street, so that the app does not scan all segments at each start.

| Column          | Type | Meaning |
| --------------- | ---- | ------- |
| `area`          | INTEGER | The `bfs_number` of the area of the street |
| `name`          | TEXT | The official street name, as in `segments.street` |
| `segment_count` | INTEGER | The number of segments of the street |
| `length_m`      | REAL | The total length of the segments of the street, in metres |

The primary key is (`area`, `name`).

### `segments`

One row for each segment. Each segment lies in exactly one area. The map build rules are in [README.md](README.md#rules).

| Column      | Type | Meaning |
| ----------- | ---- | ------- |
| `fid`       | INTEGER, primary key | The number of the segment: the canton number times 10,000,000, plus a running number, for example `10000243`. It is unique across the packages of a map release, but not stable across map releases. It joins `segments_index`, and it is the feature ID in the map tiles. |
| `id`        | TEXT, unique | The stable identifier of the segment. See below. The column has no index, because the app never looks up a segment by its identifier. The map build checks that it is unique. |
| `area`      | INTEGER | The `bfs_number` of the area that the segment lies in |
| `way_class` | TEXT | The swissTLM3D `OBJEKTART`, for example `2m Weg` or `4m Strasse` |
| `street`    | TEXT or NULL | The official street name, for example `Zürcherstrasse`, or NULL if the segment has no name. See below. |
| `length_m`  | REAL | The length in metres, measured in LV95 |
| `geometry`  | BLOB | WKB LineString |

The stable identifier comes from the swissTLM3D UUIDs of the ways. A segment is made of one or more pieces of ways. Each piece has an identifier:

- A way that lies fully inside the area keeps its UUID, for example `{8C2D4C8F-11C2-4B8B-B618-65D789E629C4}`.
- A way that the Gemeinde boundary or a dog-ban zone cuts gets `{uuid}:{bfs_number}:{n}`, for example `{8C2D4C8F-11C2-4B8B-B618-65D789E629C4}:243:1`. The number n counts the pieces of the way in this area, in the order along the way.

The segment takes the smallest identifier of its pieces, in text order. The identifier is unique across all packages.

A segment of several pieces has the way class of its longest piece.

A street is all segments with the same `street` in the same `area`. The same name in another area is another street. The name comes from the street name tables of swissTLM3D (`TLM_STRASSENNAME` and its link table to `TLM_STRASSE`), not from the position of the way. All pieces of a segment have the same name. A way with names in several languages has all its names in text order, joined by ` / `, for example `Bözingenstrasse / Rue de Boujean`.

Example: the streets of Dietikon with their number of segments and total length.

```sql
SELECT name, segment_count, length_m
FROM streets
WHERE area = 243;
```

### `segments_index`

An SQLite R*Tree over the bounding boxes of the segments. It finds the segments near a point quickly.

| Column    | Meaning |
| --------- | ------- |
| `fid`     | The `fid` of the segment |
| `min_lon`, `max_lon` | Longitude range of the segment |
| `min_lat`, `max_lat` | Latitude range of the segment |

The R*Tree stores 32-bit floats and rounds the boxes outwards. A box can therefore be slightly larger than the segment.

Example: the segments whose box touches a small box around a point.

```sql
SELECT s.id
FROM segments_index i JOIN segments s ON s.fid = i.fid
WHERE i.max_lon >= :lon - 0.0003 AND i.min_lon <= :lon + 0.0003
  AND i.max_lat >= :lat - 0.0002 AND i.min_lat <= :lat + 0.0002;
```

### `metadata` and `tiles`: the map tiles

The package also holds the segments as vector tiles, in the tables of the [MBTiles 1.3](https://github.com/mapbox/mbtiles-spec/blob/master/1.3/spec.md) format. The map of the app reads them directly, so that it does not read the segments table to draw the map. The map build makes the tiles with [tippecanoe](https://github.com/felt/tippecanoe).

- The tiles cover zoom levels 12 to 14. The map zooms the tiles of level 14 further in, and shows no segments below level 12.
- The tiles have one layer, `segments`, with one line feature for each segment. Every segment is in the tiles of every zoom level.
- The feature ID is the `fid` of the segment. The only property is `area`, the BFS number of the area of the segment.
- The tile data is gzip-compressed Mapbox Vector Tile data. The rows of `tiles` use the TMS scheme of MBTiles, where row 0 is at the bottom.
