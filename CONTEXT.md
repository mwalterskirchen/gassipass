# gassipass

A game for dog walks in Switzerland. Each dog collects the segments it walks, and fills in official areas and their streets until they are completed.

## Language

### Map

**Segment**:
A stretch of walkable way between two junctions, or between a junction and a dead end. A segment also ends where it crosses an area boundary or where its street name changes, so each segment lies in exactly one area. It is the smallest unit a dog can collect, with or without a name. Ways that a dog cannot or must not use are not segments, for example motorways, via ferratas, alpine routes and ways inside a dog-ban zone. A private way is a segment, because the map data does not show private access.
_Avoid_: Street, edge, way, path piece

**Street**:
All segments with the same official street name in the same area, for example "Zürcherstrasse, Dietikon". A street with the same name in the next area is a different street. Segments with no official name belong to no street. A street is a goal on top of segments, not a separate unit to collect.
_Avoid_: Road, way

**Area**:
A Gemeinde whose completion the app tracks. Every area that has a map package on the phone is tracked, without any action from a member. A walk in an area with no map package on the phone counts when the map package arrives.
_Avoid_: Zone, region, territory, tile, Quartier

**Current area**:
The area where the member who records the current walk is now.
_Avoid_: Local area, this Gemeinde

**Dog-ban zone**:
A zone where dogs are banned all year, for example the Swiss National Park. Ways inside it are not segments. Seasonal rules and leash rules do not make a dog-ban zone.
_Avoid_: Restricted area, protected zone

**Map release**:
A new version of the map data. It can add, change or remove segments.
_Avoid_: Data update, map refresh

**Map package**:
The map data of one canton in one map release, as one file on the phone. It holds the segments, the areas and the streets of the canton, and the map tiles that draw the segments. A map tile is a piece of the drawn map, not a unit of the game.
_Avoid_: Map file, database, tile set

### Progress

**Collect**:
A dog collects a segment when its walks together cover nearly all of the segment's length. The walks do not need to cover it in one go. A vehicle stretch does not cover anything. For the player a segment is either collected or not collected, and a partly walked segment gives nothing.
_Avoid_: Complete (for segments), visit, unlock

**Collection**:
The set of segments that one dog has collected. It is always the result of all walks of that dog, matched against the current map release. It changes when a walk is deleted, when the dogs of a walk change, when a new map release arrives, or when a map package arrives for an area that the dog walked in before. Each phone calculates the collection from the map packages that it has, so the collection of a dog can differ between the phones of its pack until each phone has the same map packages and the same map release.
_Avoid_: History, progress

**New segment**:
A segment that a dog has not collected yet. During the current walk, a segment is new when it is new for at least one dog that takes part. Outside a walk, for example in the legend of the map, the app says "not collected" for the same thing.
_Avoid_: Uncollected segment, unexplored segment

**Collected length**:
The total length of the segments that a dog has collected, in one area, in one street, or in its whole collection. Like the collection, it can drop when a walk is deleted or a new map release arrives.
_Avoid_: Distance, kilometres walked (distance is the length of the GPS track of a walk, without its vehicle stretches)

**Completion**:
The collected length of an area or a street, as a share of its total length, for one dog.
_Avoid_: Progress, coverage

**Completed**:
A dog has completed an area or a street when its completion first reaches 100%. This is a permanent record with a date. It stays when a map release or a deleted walk later lowers the completion.
_Avoid_: Collected (for areas), finished, done

**Stamp**:
The mark in forest ink that shows that a dog has completed an area or a street, with the date. The stamp of an area is round, with the outline of the area. A street, and an area in a list, get a small date stamp. When a dog completes a street or an area during the current walk, its stamp shows on the map for a few seconds.
_Avoid_: Badge, seal, trophy, achievement

**Pinned area**:
An area that a member shows on the home screen, to follow its completion. The pins belong to the phone, not to a dog or a pack, so each phone has its own pins, also two phones of the same member. The home screen shows the completion of the selected dog. Pinning does not change what a dog collects.
_Avoid_: Started area, goal, favourite

**Collection book**:
The list of all areas of a canton for one dog, including areas with no completion yet.
_Avoid_: Album, sticker book, achievements

### Walking

**Dog**:
The animal that collects segments, and so has its own collection. Each dog belongs to exactly one pack. It changes pack only when the only member of its pack joins another pack and brings the dog along. It has its own completions. It does not matter which member walks the dog.
_Avoid_: Pet, profile, player

**Retired dog**:
A dog that no longer takes part in walks, for example because it has died. Its collection, completions and collection book stay and can be viewed.
_Avoid_: Deleted dog, archived dog, inactive dog

**Walk**:
One recording of a GPS track that a member starts and stops in the app, together with the dogs that take part. A walk has at least one dog, and all its dogs belong to the same pack. It adds segments to the collection of each dog that takes part. The walk records the member who recorded it, only to show it, and it keeps that name after the member leaves the pack. The member has no effect on what the dogs collect. The dogs of a walk can change later, but only to other dogs of the same pack. Two members can walk the same dog at the same time, with one walk each. A total distance of the dog counts the time in which the two walks overlap only once.
_Avoid_: Activity, workout, session, track

**GPS track**:
The positions that the phone records during a walk. The app keeps the GPS track of every walk, because the collection is calculated from it. The length of the GPS track, without its vehicle stretches, is the distance of the walk.
_Avoid_: Route, path, trace

**Vehicle stretch**:
A part of a walk during which the phone was in a car, a bus, a train or another vehicle. A vehicle stretch does not collect segments and does not count in the distance. The app keeps the vehicle stretches with the walk, because the collection is calculated from the walks. A walk that the app recorded without motion access has no vehicle stretches.
_Avoid_: Ride, drive, transit

**Current walk**:
The recording that the app makes now, from its start to its stop. There is at most one current walk on a phone.
_Avoid_: Session, recording, activity (the Live Activity only shows the current walk)

**Live feedback**:
What the app shows and does during the current walk: the new segments near the member who records the walk, a vibration for each segment that becomes collected, and the live completion of the current area for each dog. Each member can switch off the vibration on their phone.
_Avoid_: Notifications, live updates

**End-of-walk question**:
The question whether the current walk has ended, which the app asks after a long time without movement, or after a few minutes in a vehicle. The walk does not stop without the member who records it.
_Avoid_: Stillness alert, timeout

### Pack

**Pack**:
A group of members and the dogs that they walk together. A pack has a name. Everything about a dog is shared in its pack: its walks, its collection, its completions and its stamps. Every dog always belongs to a pack, also when the pack has only one member. A person is a member of at most one pack. A person gets their own pack only when they add a dog while they are in no pack. A person who is the only member of their pack can join another pack, and then brings their dogs, with their walks and completions, into it. Their old pack then disappears. In the same way, when a person signs in on a phone with a pack that exists only on that phone, and their account already has a pack, the dogs of the phone move into the pack of the account. When a member leaves a pack, the walks that the member recorded stay with the dogs. A person without an account has a pack only on their phone, so nobody else can join it.
_Avoid_: Family, household, group, team

**Member**:
A person in a pack. A person is a member of at most one pack. A member has a name, which the member can change.
_Avoid_: User, walker, owner

**Account**:
The sign-in of a person on the server. A person needs an account only for a backup on the server and to share a pack. Without an account, the app works only on the phone. An account and a membership are separate, so a person can have an account and no pack, or a pack and no account.
_Avoid_: Profile, user, login

**Pack owner**:
The member who made the pack, or who took it over from a pack owner who deleted their account. Always use the full term, not "owner" alone. Only the pack owner invites and removes members, and the pack owner cannot leave the pack. When the pack owner deletes their account, the member who joined first becomes the pack owner. All other members are equal to the pack owner for everything about dogs and walks.
_Avoid_: Admin, creator, leader

**Invitation**:
A link that the pack owner sends to one person, so that the person can join the pack. It works once and expires after 7 days. Only a pack owner with an account can send an invitation.
_Avoid_: Share, invite code, share link

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
| Pack | Rudel |
| Member | Mitglied |
| Pack owner | Rudelchef |
| Account | Konto |
| Invitation | Einladung |
| Walk | Spaziergang |
| End-of-walk question | Frage zum Ende des Spaziergangs |
