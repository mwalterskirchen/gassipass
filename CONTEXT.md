# doggo

A game for dog walks in Switzerland. Each dog collects the paths and streets it walks, and fills in official areas until they are completed.

## Language

### Map

**Segment**:
A stretch of walkable way between two junctions, or between a junction and a dead end. It is the smallest unit a dog can collect, with or without a name. Each segment lies in exactly one area. Ways that a dog cannot or must not use are not segments, for example motorways, via ferratas, alpine routes and ways inside a dog-ban zone.
_Avoid_: Street, edge, way, path piece

**Street**:
All segments with the same official street name in the same area, for example "Zürcherstrasse, Dietikon". A street with the same name in the next area is a different street. Segments with no official name belong to no street. A street is a goal on top of segments, not a separate unit to collect.
_Avoid_: Road, way

**Area**:
A Gemeinde whose completion the app tracks. Every area in Switzerland is tracked, without any action from the user.
_Avoid_: Zone, region, territory, tile, Quartier

**Dog-ban zone**:
A zone where dogs are banned all year, for example the Swiss National Park. Ways inside it are not segments. Seasonal rules and leash rules do not make a dog-ban zone.
_Avoid_: Restricted area, protected zone

**Map release**:
A new version of the map data. It can add, change or remove segments.
_Avoid_: Data update, map refresh

### Progress

**Collect**:
A dog collects a segment when its walks together cover nearly all of the segment's length. The walks do not need to cover it in one go. For the player a segment is either collected or not collected, and a partly walked segment gives nothing.
_Avoid_: Complete (for segments), visit, unlock

**Collection**:
The set of segments that one dog has collected. It is always the result of all walks of that dog, matched against the current map release. It changes when a walk is deleted, when the dogs of a walk change, or when a new map release arrives.
_Avoid_: History, progress

**Completion**:
The collected length of an area or a street, as a share of its total length, for one dog.
_Avoid_: Progress, coverage

**Completed**:
A dog has completed an area or a street when its completion first reaches 100%. This is a permanent record with a date. It stays when a map release later lowers the completion.
_Avoid_: Collected (for areas), finished, done

**Pinned area**:
An area that the user shows on the home screen as a goal. Pinning does not change what a dog collects.
_Avoid_: Started area, goal, favourite

**Collection book**:
The list of all areas of a canton for one dog, including areas with no completion yet.
_Avoid_: Album, sticker book, achievements

### Walking

**Dog**:
The owner of a collection. Each dog has its own collection and its own completions.
_Avoid_: Pet, profile, player

**Retired dog**:
A dog that no longer takes part in walks, for example because it has died. Its collection, completions and collection book stay and can be viewed.
_Avoid_: Deleted dog, archived dog, inactive dog

**Walk**:
One recording of a GPS track that the user starts and stops in the app, together with the dogs that take part. A walk has at least one dog. It adds segments to the collection of each dog that takes part.
_Avoid_: Activity, workout, session, track
