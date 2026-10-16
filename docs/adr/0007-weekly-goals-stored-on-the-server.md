# Weekly goals are stored on the server, one set per dog and week

Weekly goals are the first game data that the app cannot calculate from the walks. The app chooses them, it sizes them from the walks of the last four weeks, and a member can swap one of them. Every phone of a pack must show the same goals. So the server keeps one set of goals for each dog and week, with a unique key on the dog and the week. The first phone of the pack that opens the app in a new week makes the set from the data that it has, and uploads it. A phone that finds a set on the server uses it and does not make its own. The progress on each goal is still calculated from the walks, as ADR 0002 says.

## Considered Options

- **Make the goals on each phone from a seed of the dog and the week.** This needs no table. But two phones can have different walks or different map packages at that moment, and then they choose different goals. A swap must be stored anyway.
- **Make the goals on the server, for example with a scheduled function.** The server does not have the collection, because each phone calculates it (ADR 0002, ADR 0006). So the server cannot choose, for example, a street that the dog has not completed.

## Consequences

- A week starts on Monday at midnight, Swiss time, on every phone, so that all phones agree on the week.
- Two phones can make a set for the same week at the same time. The unique key refuses the second upload, and that phone downloads the set of the first one and drops its own. Nothing is lost, because the progress comes from the walks.
- A phone without a network on Monday makes a set and keeps it until it can upload. If the server already has a set for that week by then, the set on the server wins.
- A swap changes the row, and the last write wins, as for every row (ADR 0006).
- A goal keeps the time at which it was first finished, and the earliest time wins. The goal stays finished when a walk is later deleted, like a completed record, so the streak and the week stamp do not change after the week. The week stamp follows from these times, so it needs no record of its own.
- The entry stamp, the steps of the area stamp and the ring stamps are permanent records with a date, like a completed area. The server keeps one record for each dog and stamp, and the earliest one wins, as ADR 0006 says for completed records.
- Without an account, the goals stay on the phone.
