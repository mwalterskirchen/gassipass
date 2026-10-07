# A person is a member of at most one pack

A person is a member of at most one pack. We decided this because several packs per person need a current walk that becomes one walk in each pack, a dog picker grouped by pack and a choice of pack for each new dog. That is a lot of work for a case that nobody has today: the app is personal first, and the only pack in production is one family.

A person who is the only member of their pack can still join another pack. They bring their dogs, with their walks and completed records, into the new pack, and their old pack disappears. The same happens when a person signs in on a phone with a pack that exists only on that phone, and their account already has a pack. The app asks for a confirmation first. A person who is in a pack with other members must leave it before they can join another pack.

## Considered Options

- **Several packs per person.** A person could walk their own dog and their parents' dog together. ADR 0004 and issues #76 and #78 described this. We dropped it, because the split of the current walk into one walk per pack is the riskiest part of the walk code, and no real member needs it.
- **Refuse every invitation for a person who already has a pack.** The first version of this ADR did this, because on CloudKit the move of the dogs copied objects across stores and used the iCloud storage of the other pack owner. ADR 0006 replaced CloudKit with Supabase, where the move only changes the pack of each dog. Without the move, a person who tries the app alone and adds a dog could never join a pack, because the app cannot delete a dog, only retire it.

## Consequences

- ADR 0004's consequence that a walk with dogs of two packs is saved as one walk in each pack no longer applies.
- Two phones of one person can no longer end up with two packs on the server, because the second phone moves its dogs into the pack of the account when the person signs in.
