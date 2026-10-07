# Core Data syncs the packs, because SwiftData cannot share

The members of a pack use different iCloud accounts, so the dogs and the walks of a pack must live in a CloudKit share. SwiftData cannot share records between iCloud users, and it cannot choose the store that an object goes into, also in iOS 26. We therefore move the models and the sync from SwiftData to Core Data's `NSPersistentCloudKitContainer`, with a private store and a shared store. Apple supports this way, and it handles the sync, the conflicts and the large GPS tracks for us.

## Considered Options

- **Keep SwiftData on the phone and sync with CKSyncEngine.** The screens and the models would stay, and each pack would be one CloudKit zone. We did not take it, because the app would own all of the sync code: the mapping to CloudKit records, the change tracking, the conflicts, the shares and their acceptance.

## Consequences

- One pack is one share. Nothing in one share can point to an object in another share, so a walk only has dogs of one pack. A walk with dogs of two packs is saved as one walk in each pack. ADR 0005 later limited each person to one pack, so this case no longer occurs.
- The pinned areas belong to the member, so they stay in the private store and are never part of a share.
- All data of a pack counts against the iCloud storage of the pack owner.
- Core Data can open the existing SwiftData store file, and the records that SwiftData synced to the private database should carry over. Apple does not promise this, so test it on both devices before the first build with packs.
