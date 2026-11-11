# The collection is calculated from the walks, not stored

The app stores the GPS track of every walk. The collection of a dog is always the result of matching all its walks against the current map release, and the app never keeps the collection as the only record. Only this rule gives correct results in three cases. When the user deletes a walk with bad GPS, its segments leave the collection unless another walk also collected them. When a map release adds a path that the dog walked before, the path is collected at once. When a walk is in an area whose map data is not on the phone yet, the walk counts as soon as that data arrives.

## Considered Options

- **Calculate the collection again from all walks after every change.** The first version of this ADR did this. With a year of walks, the summary at the end of a walk waited about 20 seconds in a test on the simulator, because the app read and added up the matches of every walk again. ADR 0006 made it worse, because each download of a walk from another member also started a full calculation.
- **Store the collection on the server.** The server would need merge rules for walks that arrive late from other phones, and the three cases above would no longer work. The phones need the collection engine anyway for the live feedback during a walk.

## Consequences

- A cached collection is allowed for speed, but it must always be possible to rebuild it from the walks. Do not "optimise" this by dropping GPS tracks after matching.
- The local store keeps the collections of the last calculation (`WalkedSegment`), so that the app shows them at once at launch. They are such a cache: they never upload, and they change when the walks, their dogs, the app build or the map packages change.
- A new walk, and a dog that is added to a walk, add to the collection without the other walks. The date at which a segment becomes collected depends only on the covered intervals of that segment in the order of time. So for each dog and segment the app keeps the intervals that added to the covered parts, in a history that the local store keeps with the collections (`CollectionHistory`, `WalkedSegment`). A new walk changes only the segments that it covers, also when it is older than other walks, for example a walk that arrives late from another member.
- A deleted walk, a dog that is removed from a walk, a new app build and new map packages calculate the collection again from all walks. A removed walk can be the reason why the history dropped the intervals of other walks, so only a full calculation is right. These changes are rare.
- A completed area is a permanent record with a date. It is not rebuilt from the walks, so a map release cannot take it away.
