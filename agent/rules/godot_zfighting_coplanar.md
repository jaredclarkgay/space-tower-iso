# Z-fighting flicker from coplanar opaque surfaces

The flicker the operator keeps catching (B-001; the roof-deck build flicker; and
earlier one-off fixes) is **always the same bug wearing a different hat.** Read this
before adding ANY procedural surface that sits near other geometry, or moving a
surface that travels/holds near other geometry.

## What it is (not a material bug)
A shimmering/stipple patch where two surfaces meet, worst as the camera nudges but
present even static. It's the **depth buffer unable to order two opaque surfaces at
the SAME depth (coplanar)** — so which one wins flips per-pixel / per-frame = flicker.
GL Compatibility (this project's renderer) is no more forgiving than Forward+ here.

## Root cause, stated once
**Two opaque surfaces occupying the same plane at the same world depth.** That's it.
Fix = make sure that never happens (or force a deterministic winner).

## Why it KEEPS happening — the trap
It's rarely two obviously-overlapping static boxes you'd notice in code review. It's:

1. **A new surface placed exactly at a neighbor's coordinate.** B-001: the earth-frame
   top at `y=0` == the apron / grade plane; the earth-slab top at `-6` == the pit-floor
   top. Looks fine in isolation; coplanar with something built elsewhere.

2. **Moving / tweened / relocating geometry that RESTS or is HELD at a plane shared
   with static geometry — only in a TRANSIENT state.** The roof-deck flicker: the
   climbing worksite is *held* at the pit floor (`y=-6`) while the CC assembles, and the
   solid deck's top surface sits exactly at `-6` == the pit-floor top. At its *final*
   resting spot (one story up, on an as-yet-unbuilt floor) it's fine — so it's invisible
   if you only check the end state. **The flicker lives in the in-between.**

3. **A surface that assembles at the plane where another object is waiting.** Same class:
   the floor slab pours at exactly the plane the held deck occupies.

## Prevent it while building — the checklist
1. **Enumerate the world-coordinate of every nearby surface the new one could share a
   plane with** before placing it. In this project that's: grade / site-ground / apron
   (`y=0`), floor tops (`floor_top_y(level) = base_y + FLOOR_3D_TOP_Y`), the pit floor
   (`-PIT_DEPTH`), slab bottoms, CC/earth surfaces. Keep a clear gap — z-fighting is
   sub-millimetre so even ~0.05 m kills it, but leave 0.1–0.5 m of margin for sanity.
2. **For anything that moves, check EVERY plane it rests / holds / pauses at across its
   whole travel — not just the final position.** Tween start poses, mid-assembly holds,
   a platform climbing past floor planes. This is the step that gets skipped.
3. **When two surfaces MUST share a plane** (a construction deck forming where a slab
   pours; a floor and its would-be ceiling): don't render both in that state. Pick, in
   order of preference:
   - **Hide the redundant one** while they'd coincide (the roof-deck fix: hide the deck
     `and not mid_build`, so during assembly the crew read as standing on the real slab,
     and the deck reveals + lifts *after* top-out — a better beat anyway).
   - **Offset one by a clear margin** (B-001: drop the earth surfaces off both planes).
   - **`material.render_priority`** to force a deterministic draw-order winner (last
     resort; offset/hide are surer on GL Compatibility).
4. **Coplanar-by-design overlays** (Label3D prompts, ground-selection rings, decals):
   give them a small lift/inset off the surface and/or `render_priority` +
   `no_depth_test`, never exact equal depth. (See `godot_label3d_orthographic_zoom.md`.)

## Verify the TRANSIENT states, not just the end
A single end-state screenshot passes while the build-time flicker is still there. In the
windowed harness (`godot_screenshot_harness.md`), **drive into and sample the MID
states** — mid-build (`is_crane_building()==true`), mid-climb, held-during-tween — and
**print the world-Y of the suspect surface vs the neighbour plane**. If two opaque
tops share a Y to the millimetre, that's your flicker, even if the eye missed it in a
still frame.

## Recurrences (all one bug)
- **B-001**: earth surround coplanar with apron/grade (`y=0`) and the pit floor (`-6`).
  Fixed by offsetting the earth surfaces a clear margin off both planes + insetting the
  vertical faces behind the excavation walls.
- **Roof-deck build flicker**: the climbing worksite's solid deck held coplanar with the
  floor slab materializing at its plane (and with the pit floor during the CC build).
  Fixed by hiding the deck while the floor is mid-assembly (`_worksite_deck.visible …
  and not mid_build`); its resting plane is always an unbuilt floor, so never coplanar.

Same root cause both times: an opaque surface landing exactly on a plane occupied by
other geometry — one via static placement, one via a held/transient position.
