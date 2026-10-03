# Motion activity is kept with the walk

While the app records a walk, it also records the motion activity of the phone (Core Motion) and keeps it with the walk, next to the GPS track. ADR 0002 says that the collection is always rebuilt from the walks, and iOS keeps motion history for only 7 days, so the app must keep the motion activity itself. The collection rules use it in two ways. A vehicle stretch collects nothing at any speed. A stretch that the phone reports as running or cycling collects up to 25 km/h instead of the usual 12 km/h, because a dog can run beside a runner or a bicycle. A stretch counts as a vehicle stretch only when the phone reports a vehicle with medium or high confidence for at least 60 seconds, so that a real walk does not lose segments.

## Considered Options

- **GPS speed only.** It works for every walk and is always rebuilt from the GPS track. The 12 km/h speed rule already keeps fast vehicles out. We still added motion activity, because speed alone cannot tell a slow bus from a walker, or a bicycle from a car.

## Consequences

- A walk without motion activity, for example an old walk or a walk without motion access, follows the 12 km/h rule and has no vehicle stretches.
- The motion activity of a walk cannot be found again later. Do not drop it when a walk is matched again or synced.
