# Scripted cinematic cameras: persistent member-state eased toward per-beat targets

**When:** any multi-beat scripted camera move (intro cinematic, cutscene, scripted
walk-and-talk) where the camera owns itself for a while, hands between several
"beats", and must feel like ONE continuous glide — never a snap at a beat
boundary. Proven on the Garden first-entry opener (`_begin_arrival_cinematic` /
`_update_arrival_cinematic` in `scenes/tower/tower_controller.gd`).

## The pattern

DON'T compute a fresh camera transform per beat and assign it. That snaps every
time a beat hands off, because beat N's last frame and beat N+1's first frame are
two different formulas.

DO keep the camera pose as a bag of **persistent live members** plus a parallel
bag of **targets**, and ease live → target every frame in ONE place:

```
# live (seeded once at cinematic start, persist across all beats)
_cam_focus, _cam_yaw, _cam_back, _cam_lift, _cam_shoulder, _cam_size, _cam_lookahead, _cam_looklift
# targets (whatever the current beat wants)
_cam_focus_tgt, _cam_yaw_tgt, ...

func _drive_arrival_camera(delta):           # called by EVERY beat
    var f := 1.0 - pow(EASE_BASE, delta)     # framerate-independent exp ease
    _cam_focus = _cam_focus.lerp(_cam_focus_tgt, f)
    _cam_yaw   += (wrapf(_cam_yaw_tgt - _cam_yaw + PI, 0, TAU) - PI) * f   # shortest-arc for angles
    ...
    # apply ONCE from the eased members (pivot pos+yaw, camera local offset, look_at, size)
```

A beat's job is now only **"set the targets"**. Because the live members carry
over, the transition between any two beats is automatically continuous — the
formula that moves the camera never changes, only the goalposts do.

## The non-obvious wins this bought

1. **Seed the live members AT the first beat's settled pose, not at a wider
   "establishing" pose.** Seeding wide meant Beat 1 visibly swooped down into the
   follow framing. Seeding at the final follow pose makes entry→walk read as one
   motion — the only thing that moves is a short intro blend from the *prior*
   camera (captured live at cinematic start) into the already-correct follow pose.

2. **A multi-beat ease must advance the SAME progress var across the boundary —
   don't restart it.** The yaw→profile rotation begins in Beat 3 (as the NPC
   settles) but usually isn't finished when Beat 3 ends. Track it in a member
   (`_rotate_t`) and have Beat 5 keep calling the SAME `_advance_rotate_ease`
   until `_rotate_t` clamps at its duration, THEN hold. If you instead kick off a
   new tween in Beat 5 it snaps/restarts at the seam. One curve, owned by member
   state, drives yaw+focus+size together.

3. **Keep every sweep monotonic and one-directional.** A conversation "orbit"
   built from `(1−cos)` was a back-and-forth = a visible reversal the operator
   flagged. The fix was to make the whole piece ONE direction: walk-yaw → profile
   → iso, never reversing. When in doubt, a still hold beats a swing.

4. **Clamp the camera's WORLD xz over the floor footprint** (`_clamp_cam_over_footprint`).
   A behind-the-back pose at a doorway pushes the camera past the slab edge, where
   it looks UNDER the floor (void / floor below). Clamp the camera point inward,
   convert back to a pivot-local offset, and the look-at still aims at the focus —
   only the framing slides, it never sees under the edge. (See F-027.)

## Replayability

If the cinematic can replay (dev chapter-jump, restart), every actor it animates
must expose a `cinematic_reset()` that restores its PRE-cinematic state. On a
replay the NPC/elevator are left in their END state (parked, doors open), which
short-circuits any `is_*_done()` gate and the beat never advances. Reset at the
top of `_begin_*` — a no-op on first boot, essential on replay. (See F-028.)
