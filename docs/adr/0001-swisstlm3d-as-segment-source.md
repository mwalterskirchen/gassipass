# swissTLM3D is the source for segments, not OpenStreetMap

Segments come from the swisstopo landscape model swissTLM3D (`TLM_STRASSE`), not from OpenStreetMap, although comparable apps such as CityStrides and Wandrer use OpenStreetMap. swissTLM3D has one line per street, so sidewalks that OpenStreetMap maps as separate footways do not become parallel segments that one walk collects at random. It also carries the official hiking categories (Wanderweg, Bergwanderweg, Alpinwanderweg), which the rules for excluded ways depend on. It has one release per year, which gives clear map releases. The licence is swisstopo open government data: attribution ("©swisstopo") is required, and there is no share-alike condition.

## Considered Options

- **OpenStreetMap.** It is more detailed and changes every day. We rejected it because of the separately mapped sidewalks, the continuous changes to segments, and the share-alike condition of the ODbL licence for any extractable data.
- **Both sources combined.** This is the most complete option. We rejected it because joining two networks line by line is a large project of its own.

## Consequences

- swissTLM3D has no information about private access. A private way that is in the data is a segment.
- New paths appear only with the next yearly release, and swisstopo revises each region only every three years.
