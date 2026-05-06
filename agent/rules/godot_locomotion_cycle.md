# Procedural locomotion cycle (foot-planted)

## Rule

For procedural walk / run animation on a character with single-rigid-leg
geometry, **derive cycle rate from speed** and **use a piecewise plant /
swing trajectory** rather than a fixed-rate sin curve. Single waveforms
always produce sliding feet — there's no phase where the foot is fixed
in world space.

## Why

A fixed cycle rate decoupled from speed makes the body cover a different
distance per stride than the foot does per swing — sliding is unavoidable.
And a pure-sin foot trajectory keeps the foot moving even at the
rotational extents (cos = 0 there, but the body keeps moving), so the
foot never "sticks" to the ground — it slides along the ground at body
speed at every moment.

Real walking has the foot stationary in world during the plant phase
(half the cycle) and the body translates over it. Procedurally:

- **SWING** half: foot arcs from -amp_z to +amp_z through air, with a
  Y-offset lift so it clears the ground.
- **PLANT** half: foot z-relative-to-body marches linearly from +amp_z
  down to -amp_z. The rate of decrease exactly cancels the body's
  forward velocity, so the foot is stationary in world.

For the plant rate to cancel body velocity exactly, the cycle rate must
satisfy: time-for-plant-half · speed = 2 · amp_z, which gives:

```
cycle_rate = π · speed / (2 · amp_z)
amp_z = leg_length · sin(amplitude)
```

Where `amplitude` is the rotation magnitude of the leg pivot (radians)
and `leg_length` is the distance from the pivot to the foot.

## Implementation pattern

```gdscript
const LEG_LENGTH := 0.57
const WALK_LIMB_AMPLITUDE := 0.55
const RUN_LIMB_AMPLITUDE := 0.95
const WALK_FOOT_LIFT := 0.06
const RUN_FOOT_LIFT := 0.12

var _locomotion_phase: float = 0.0
var _locomotion_amp: float = 0.0     # smoothed in/out
var _locomotion_lift: float = 0.0

func _physics_process(delta):
    var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
    var locomotion_active: bool = on_floor and horizontal_speed > 0.5 \
        and not _is_in_locked_pose()

    var target_amp: float = 0.0
    var target_lift: float = 0.0
    if locomotion_active:
        if Input.is_action_pressed(&"sprint"):
            target_amp = RUN_LIMB_AMPLITUDE
            target_lift = RUN_FOOT_LIFT
        else:
            target_amp = WALK_LIMB_AMPLITUDE
            target_lift = WALK_FOOT_LIFT

    _locomotion_amp = lerp(_locomotion_amp, target_amp, 12.0 * delta)
    _locomotion_lift = lerp(_locomotion_lift, target_lift, 12.0 * delta)

    var amp_z: float = LEG_LENGTH * sin(_locomotion_amp)
    if locomotion_active and amp_z > 0.001:
        var cycle_rate: float = horizontal_speed * PI / (2.0 * amp_z)
        _locomotion_phase = fmod(_locomotion_phase + cycle_rate * delta, TAU)

    _apply_leg(_leg_l_pivot, _locomotion_phase, amp_z, _locomotion_lift)
    _apply_leg(_leg_r_pivot, fmod(_locomotion_phase + PI, TAU), amp_z, _locomotion_lift)


func _apply_leg(pivot: Node3D, leg_phase: float, amp_z: float, lift_amp: float) -> void:
    var foot_z: float
    var foot_lift: float
    if leg_phase < PI:
        # SWING — foot in air
        var t: float = leg_phase / PI
        foot_z = lerp(-amp_z, amp_z, t)
        foot_lift = sin(t * PI) * lift_amp
    else:
        # PLANT — foot fixed in world; relative-Z marches linearly
        var t: float = (leg_phase - PI) / PI
        foot_z = lerp(amp_z, -amp_z, t)
        foot_lift = 0.0
    # 1-DOF inverse-sin: foot_z_relative = -leg_length · sin(rotation_x)
    pivot.rotation.x = asin(clamp(-foot_z / LEG_LENGTH, -1.0, 1.0))
    pivot.position.y = foot_lift   # raises/lowers the per-leg pivot
```

Phase advances ONLY while moving on the ground, so legs settle naturally
when the character stops — amplitude lerps toward 0, the inverse-sin
solves to 0 rotation, legs return to vertical.

## Composition with parent pose pivots

The per-leg pivot is a child of an outer `_legs_pivot` (which rotates
both legs together for tuck-flip-knees-up). Both rotations apply
multiplicatively, so a tuck pose can have legs forward (parent rotates
−1.10) AND the cycle continues in the per-leg pivots — but typically
you GATE the cycle off during tuck because both feet are airborne.

Other states to gate the cycle off: harvesting, planting, charging
beyond the move-lock threshold, mid-air, mid-land-squash.

## Tuning notes

- Cadence at base speed: rate = 7 m/s · π / (2 · 0.57 · sin(0.55)) ≈
  37 rad/s ≈ 5.9 cycles/sec ≈ 11.8 strides/sec. Fast! Real human
  walking is 2 strides/sec, running is 3-4 strides/sec. The high cadence
  is a consequence of base speed being too fast for the body geometry —
  if cadence reads as too fast, options are: bigger amplitude (lower
  cycle rate at same speed), longer LEG_LENGTH, or accept the fast
  cadence as part of the prototype's "mini-human" feel.
- Amplitudes feel right at 0.55 (walk) / 0.95 (run) for a 0.57 m leg.
  Smaller amplitudes look too modest at base speed; larger amplitudes
  exceed sin(amp) ≈ 1.0 limit.
- Foot lift 0.06 m walk / 0.12 m run is enough to read as foot
  clearing the ground without obvious clipping.

## See also

- `failure_log.json` F-013 (the slipping-foot bug that drove this).
- `rules/animation_pose_alignment.md` (pose direction must match
  upcoming physics).
