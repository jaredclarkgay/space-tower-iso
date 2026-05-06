# Animation pose direction must match upcoming physics

## Rule

When designing anticipation poses (charge wind-ups, draw-backs, loaded
springs), the body language must imply the SAME direction as the upcoming
motion. A mismatched anticipation feels surprising and "wrong" — even
before the player can articulate why.

## Why

Players read body language as a prediction of what's about to happen.
That's what anticipation IS in animation theory. If the visual cue
implies one direction and the physics goes the other, the takeoff lands
in their brain as a non-sequitur.

Two real examples from this project:

### Front-flip wind-up (F-012)

Initial POSE_CHARGE had `arms_x = +1.65` — arms swept BACK behind the
body. This is the natural cue for a **back**-flip: cock arms back,
swing them forward + overhead, body rotates backward. Operator caught
it instantly: *"the front flip isn't really making sense, because it
looks like he's gearing up for a backflip, but then the physics lead
into a front flip."*

Fixed by retuning to `arms_x = -2.20` — arms reach UP and FORWARD, like
a diver loading the leap. Arms swinging up-forward at top of charge
naturally flow into the body rotating forward at takeoff.

### Charge with sliding feet (separate but related)

Pre-charge wind-up implies "I'm about to spring upward" — but if the
character can still slide horizontally during the wind-up, the body is
both winding up AND skating. The two cues conflict. Fix was locking
horizontal velocity once `_charge_time` exceeds a brief grace period.

## Pattern

When designing a pose for a state-transition that has post-state physics
(e.g. a charge that releases into a leap), check:

1. **What direction does the post-state move?** Up, forward, sideways,
   rotating which way?
2. **What body language IRL implies that direction?** Real reference:
   how do divers / gymnasts / runners load their motion?
3. **Does the pose use that body language?** If not, retune.

| Upcoming motion | Anticipation cue |
|---|---|
| Forward leap / front-flip | Arms reach UP + FORWARD, slight forward lean |
| Backward leap / back-flip | Arms swing back behind body, then swing UP |
| Vertical jump (no rotation) | Arms back then up; deep crouch; head forward |
| Forward dash | Arms back, head forward, weight on back foot |
| Strike / punch | Wind-up to opposite side of strike direction |

## Diagnosis

If a state transition feels "surprising" or "doesn't make sense", check
the anticipation pose's directional bias against the post-state physics.
The mismatch is usually the issue, even when the player describes it
vaguely.

## See also

- `failure_log.json` F-012 (the backflip-wind-up-into-front-flip bug).
