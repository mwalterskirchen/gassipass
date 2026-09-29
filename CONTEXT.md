# gassipass

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

**Map package**:
The map data of one canton in one map release, as one file on the phone. It holds the segments, the areas and the streets of the canton, and the tiles that the map draws.
_Avoid_: Map file, database, tile set

### Progress

**Collect**:
A dog collects a segment when its walks together cover nearly all of the segment's length. The walks do not need to cover it in one go. For the player a segment is either collected or not collected, and a partly walked segment gives nothing.
_Avoid_: Complete (for segments), visit, unlock

**Collection**:
The set of segments that one dog has collected. It is always the result of all walks of that dog, matched against the current map release. It changes when a walk is deleted, when the dogs of a walk change, or when a new map release arrives.
_Avoid_: History, progress

**New segment**:
A segment that a dog has not collected yet. During the current walk, a segment is new when it is new for at least one dog that takes part.
_Avoid_: Uncollected segment, unexplored segment

**Collected length**:
The total length of the segments that a dog has collected, in one area, in one street, or in its whole collection. Like the collection, it can drop when a walk is deleted or a new map release arrives.
_Avoid_: Distance, kilometres walked

**Completion**:
The collected length of an area or a street, as a share of its total length, for one dog.
_Avoid_: Progress, coverage

**Completed**:
A dog has completed an area or a street when its completion first reaches 100%. This is a permanent record with a date. It stays when a map release later lowers the completion.
_Avoid_: Collected (for areas), finished, done

**Stamp**:
The mark in forest ink that shows that a dog has completed an area or a street, with the date. The stamp of an area is round, with the outline of the area. A street, and an area in a list, get a small date stamp. When a dog completes a street or an area during the current walk, its stamp shows on the map for a few seconds.
_Avoid_: Badge, seal, trophy, achievement

**Pinned area**:
An area that the user shows on the home screen, to follow its completion. Pinning does not change what a dog collects.
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

**Current walk**:
The walk that the app records now, from its start to its stop. There is at most one current walk.
_Avoid_: Session, recording, activity (the Live Activity only shows the current walk)

**Live feedback**:
What the app shows and does during the current walk: the new segments near the walker, a vibration for each segment that becomes collected, and the live completion of the current area for each dog. The user can switch off the vibration.
_Avoid_: Notifications, live updates

**End-of-walk question**:
The question whether the current walk has ended, which the app asks after a long time without movement. The walk does not stop without the user.
_Avoid_: Stillness alert, timeout

## German terms

The app uses these German words for the terms above. The German text uses Swiss spelling, so "Strasse" and not "Straße".

| Term | German |
|---|---|
| Segment | Segment |
| Street | Strasse |
| Area | Gemeinde |
| Map package | Kartenpaket |
| Collect, collected | sammeln, gesammelt |
| Collection | Sammlung |
| New segment | neues Segment |
| Collected length | gesammelte Länge |
| Completion | Vollständigkeit |
| Completed | abgeschlossen |
| Stamp | Stempel |
| Pinned area | angeheftete Gemeinde |
| Collection book | Sammelbuch |
| Dog | Hund |
| Retired dog | Hund im Ruhestand |
| Walk | Spaziergang |
| End-of-walk question | Frage zum Ende des Spaziergangs |
