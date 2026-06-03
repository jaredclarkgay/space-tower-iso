# Stacked-tower invariants — keep floors, transit, and shared state linked

The game is ONE continuous world: floors are offset child nodes at
`y = level * FLOOR_3D_STORY_HEIGHT` (story = 6 m; `level` is 0-indexed — Utility
is Floor 0/basement) under a single
player/camera/HUD, driven by `scenes/tower/tower_controller.gd`. Most bugs this
era came from code that forgot the floors are stacked, or that built cross-floor
state once instead of keeping it live. These are the rules that keep it coherent.
Read this before adding a floor, a vehicle, a vertical-traversal method, or any
cross-floor visual.

## 1. NEVER hardcode a world-Y. Derive it from the floor.

The single biggest class of regression. A value that was correct when the floor
sat at world y=0 is wrong once the floor is at y=6/12/18/24.

- The Cody dialogue camera aimed at a hardcoded `target.y = 1.0` → in the tower it
  looked ~5 m **below** the characters and framed the floor. Fix: derive from the
  subjects' own y (`(p1.y + p2.y)*0.5 + chest`).
- Floors build their geometry in LOCAL space (slab top at local y=0); the tower
  sets `node.position.y`. So floor controllers / shared builders need ZERO
  base-y awareness — keep it that way.
- **World height for a floor is `(level - GROUND_LEVEL) * FLOOR_3D_STORY_HEIGHT`,
  not `level * story`.** Session 14 re-anchored the tower so the Garden
  (`GROUND_LEVEL = 1`) sits at world **y=0** and the Utility basement (level 0)
  drops to y=-6 (below the site ground / empty lot, both at y=0). The top-level
  transit nodes (`elevator_platform._floor_y`, `vacuum_lift._surface_y` /
  `_floor_node_for_level`) and `tower_controller`'s floor offset all subtract
  `GROUND_LEVEL` — they used to hardcode `level * story` (Floor 0 = y=0), the
  exact "hardcoded world-Y" trap above. If you add a floor-Y computation, derive
  it from `_base_y_for_level()` (controller) or `(level - GROUND_LEVEL) * story`,
  never a bare `level * story`. The player fall-backstop is one story below the
  basement (`-(GROUND_LEVEL+1) * story`). Verified: vacuum hops + elevator rides
  to floors 0/1/2/5 all land solid post-anchor.

## 2. Transit-ownership: a system owns the player, and the tower must KEEP TRACKING.

There's a recurring pattern for "the player isn't walking right now": a system
takes over the transform and the player skips its own physics. Each one is a
GameState bool the player early-returns on:
`riding_elevator` (elevator car), `tube_hopping` (vacuum lift),
`driving_crane` (the roof crane). A fourth, `looking_out` (Sky Lounge look-out
camera), is camera-only: it doesn't move the player or change floors, so it needs
the player-freeze + defer-others (steps 1 + 3) but NOT the `_current_level`
tracking (step 2) — the player stays put. iso_camera also gates its pivot drive
off it, and the tower gates its pivot-follow off it, so nobody fights the
look-out camera.

When you add another (a new vehicle, lift, zip-line, cutscene), wire ALL of:
1. **Player skip** — add the flag to `iso_player`'s early-return so it doesn't
   fight the owner for the transform.
2. **Tower level-tracking** — add the flag to the `_current_level` update gate in
   `tower_controller._update` (next to `grounded`/`riding`/`hopping`). This is
   load-bearing: `is_on_floor()` is false while a system owns the player, so
   without it `_current_level` freezes, the destination floor's **slab stays
   gated OFF, and the player falls straight through on arrival** (the F-022 /
   commit 79021ff fall-through class). Verified every transit lands solid.
3. **Defer other systems** — anything that reads global input should bow out
   (e.g. the vacuum lift's `busy` check includes `driving_crane`, dialogue,
   schematic) so two owners never grab the player at once.

## 3. Cross-floor visual state must be LIVE, not baked at build time.

Every floor builds at startup, BEFORE any gameplay state exists. So a builder
that reads state at `_ready` sees the initial (empty) state forever.

- `build_passive_spine_pipes` decided lit-vs-cold once at build → the lit utility
  state never climbed past Floor 1. Fix: always build the lit overlay, tag it in
  a group (`"passive_spine_fill"` + `sys_id` meta), and have `tower_controller`
  drive `visible` from `GameState.floor_1.pipe_active` **every frame**.
- General rule: if a per-floor visual reflects shared/global state, render it
  unconditionally and toggle it from one central per-frame updater (the tower),
  keyed by a group + meta. Don't gate it at construction.

## 4. Shared builders are the unit of cross-floor CONSISTENCY.

`floor_chrome.gd` and `vacuum_tube.gd` are static builders every floor calls.
That's why one change fixes all floors at once:
- The "elevator walls missing on tube-reached floors" fix was a few lines added
  to `build_elevator_core` (framed-doorway cardinal walls) — every floor inherited
  it because every floor calls that builder.
If something should look/behave the same on every floor, it belongs in a shared
builder, NOT copied inline per floor. Inline-per-floor is how things drift.

## 5. Linked per-floor layouts must be MIRRORED, or they desync.

When two floors share a coordinate system, a change to one needs the same change
to the other:
- Arboretum-ground (Floor 2) tree PLOTS ↔ Canopy (Floor 3) tree HOLES ↔ corner
  TUBES all live on the same edge grid. Excluding tube corners from the ground's
  plots required the SAME exclusion in the canopy's hole computation — otherwise the Canopy gets an empty
  hole at each corner tube and the player drops through it when tube-hopping.
- These two functions are independent copies of the same algorithm. If you touch
  one, grep for the sibling. (Ideally unify into a shared helper next time.)

## 6. `no_depth_test` Label3D punches through floors — Y-gate floating labels.

The tower shows the current floor + everything below, so labels on a lower floor
are in view from above. A `Label3D` with `no_depth_test = true` (used so
same-floor geometry never clips a prompt) also renders straight through the slab.
Gate such labels by the player's floor: hide them when
`abs(player.y - self.global_position.y) > ~half a story`. (Dispenser window
labels showed from the Arboretum until gated.)

## 7. Stage ceremonies clear of shared MOVING infrastructure.

Cody's arrival rose through the central elevator shaft — fine until the unified
tower parked a physical car there, which then occluded the whole ascent. Stage
"a moment" (rise, beam, reveal) away from the elevator shaft / car / anything
that moves or gets occupied. He now rises beside the elevator.

## 8. Edge-fall = a real fall, then return to the launch point.

`iso_player` tracks `_last_ground_pos` (last grounded spot, exempt during
transit). Off an open edge you plunge up to `FALL_CATCH_MAX_FLOORS` (5) or just
past the tower bottom, THEN snap back to where you jumped from. Falls that reach
a floor below first (dropping through the Canopy tree-hole apertures onto the
Arboretum slab) land normally — the slab catches you before the threshold. Don't
make this a short snap; the operator wants the fall to play.

## Verifying without a human

Windowed physics harness (NOT `--headless`, which renders nothing): instance
`tower.tscn`, drive `GameState` flags + `Input.action_press`, step
`process_frame`, assert positions/visibility and `save_png` for the eye. Climb
floors with `VacuumLift._begin_hop(corner, level)` (sets the transit flag so the
tower tracks). See the `space-tower-screenshot-harness` memory.
