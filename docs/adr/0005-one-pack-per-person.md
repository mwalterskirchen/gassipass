# A person is a member of at most one pack

A person is a member of at most one pack. The app refuses an invitation from a person who is already in a pack, also when that pack is their own and has only their own dogs. We decided this because several packs per person need a current walk that becomes one walk in each pack, a dog picker grouped by pack and a choice of pack for each new dog. That is a lot of work for a case that nobody has today: the app is personal first, and the only pack in production is one family.

## Considered Options

- **Several packs per person.** A person could walk their own dog and their parents' dog together. ADR 0004 and issues #76 and #78 described this. We dropped it, because the split of the current walk into one walk per pack is the riskiest part of the walk code, and no real member needs it.
- **Move the dogs of a person who joins.** A person whose own pack has only their own dogs could bring the dogs, their walks and their completed records into the new pack. We did not build it yet, because it copies objects across stores and uses the iCloud storage of the other pack owner. Add it when a real person needs it, for example when the app becomes public.

## Consequences

- The app cannot delete a dog, only retire it. So a person who added a dog once can never join another pack.
- Two phones of one person can still end up with two packs, when one phone joins a pack while the other phone, offline, adds the first dog. The app does not handle this case, and a walk with dogs of both packs would fail to save.
- ADR 0004's consequence that a walk with dogs of two packs is saved as one walk in each pack no longer applies.
