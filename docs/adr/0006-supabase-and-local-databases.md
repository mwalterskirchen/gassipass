# Supabase and a local database on each phone replace CloudKit

The app needs an Android version, and CloudKit works only between Apple devices. So the server is now Supabase, in the Zurich region. The iPhone keeps a local SwiftData database, and Android keeps a local Room database. There is no sync engine. Each change on the phone is marked as waiting to upload, and it uploads when the person is signed in. Each phone downloads the changes of its pack when the app opens, when it comes to the foreground, and on pull to refresh. Without an account, the app works only on the phone and talks to no server. This replaces ADR 0004 and removes Core Data and CloudKit from the app.

## Considered Options

- **Supabase with PowerSync.** PowerSync keeps a local SQLite database in sync with Postgres, on iOS and Android. We did not take it, because the data is small and changes slowly. One family records a few walks a day, and almost every change is a new row. Our own upload and download is less code to understand than a sync engine and its rules, and the local databases stay SwiftData and Room.
- **Convex.** It has no offline mode, and a walk must save without a network.
- **Instant.** Its hosted service shuts down on 2027-08-31.
- **Keep CloudKit on iOS and add a server only for Android.** Two backends would have to agree on every pack, so we did not consider it further.

## Consequences

- The last write wins for the whole row, by the time on the server. Conflicts are rare, because almost every change is a new row. The dogs of a walk are in their own table, so a change to the dogs does not overwrite the walk.
- A deleted row stays on the server with a deletion time, so that the other phones learn about the deletion. A download asks for all rows that changed since its last download, with some overlap.
- Dogs and walks need a stable ID that is the same on every phone. Core Data identified them only inside one phone.
- The server keeps the rule for completed records that the phones already use: one record for each dog and area, or each dog and street, and the earliest one wins.
- GPS tracks and dog photos go into Supabase Storage, not into the tables.
- Invitation, join, remove and leave are Postgres functions, so that the server checks the rules of ADR 0005 and of the pack owner.
- Pinned areas stay on each phone and never upload.
- The family pack moves once. The phone of the pack owner copies the Core Data stores into SwiftData and uploads the pack. The phone of a member copies nothing from the shared store, and the member joins again through a new invitation. Old walks with an empty member name get the name of the pack owner.
- The collection is still calculated on each phone from the walks, as ADR 0002 says. Android needs its own copy of the collection engine.
