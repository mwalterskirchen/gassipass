# The collection is calculated from the walks, not stored

The app stores the GPS track of every walk. The collection of a dog is always the result of matching all its walks against the current map release, and the app never keeps the collection as the only record. Only this rule gives correct results in three cases. When the user deletes a walk with bad GPS, its segments leave the collection unless another walk also collected them. When a map release adds a path that the dog walked before, the path is collected at once. When a walk is in an area whose map data is not on the phone yet, the walk counts as soon as that data arrives.

## Consequences

- A cached collection is allowed for speed, but it must always be possible to rebuild it from the walks. Do not "optimise" this by dropping GPS tracks after matching.
- The local store keeps the collections of the last calculation (`WalkedSegment`), so that the app shows them at once at launch. They are such a cache: they never upload, and the app calculates them again when the walks, their dogs, the app build or the map packages change.
- A completed area is a permanent record with a date. It is not rebuilt from the walks, so a map release cannot take it away.
