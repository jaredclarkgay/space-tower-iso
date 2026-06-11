# Floor Design System

The Space Tower has many floors. This doc captures the rules every floor follows
so they read as the same building viewed at different stories, and so a player who
learned how to operate one floor can operate any other one without retraining.

These are constraints, not suggestions. New floors follow them by default;
deviations require an explicit reason (see §11).

> **Architecture this doc assumes (current — stacked world).** There is **one
> runtime scene**, `scenes/tower/tower.tscn`, driven by
> `scenes/tower/tower_controller.gd`. There are **no per-floor `.tscn` files**:
> each floor is a `.gd` controller in a content-named `scenes/<name>/` dir
> (`utility/`, `garden/`, `arboretum_ground/`, `arboretum_canopy/`,
> `residential/`, `sky_lounge/`, `roof/`), instanced as an offset child of
> `tower.tscn` under `Floors/<Name>` at `y = (level − GROUND_LEVEL) × story`
> (story = 6 m). **One** player, **one** camera, **one** HUD — shared across all
> floors. You **walk / fall / ride / hop** between floors; nothing scene-swaps.
> **Locked numbering (0-indexed):** Utility **0** (basement, below grade), Garden
> **1** (ground/spawn), Arboretum-ground **2**, Canopy **3**, Residential **4**,
> Sky Lounge **5**, Roof **unnumbered** (internal level 6). See the architecture
> callout at the top of `CLAUDE.md` for the canonical statement.

---

## 1. Footprint

- **30 × 30 m square slab.** Constants: `FLOOR_3D_SIZE = 30.0`.
- **Slab thickness** `FLOOR_3D_SLAB_THICKNESS = 0.2` m. Local top face at y = 0
  (the floor node is then offset to its stacked height by the tower).
- **Floor centred on the world origin** (xz extent: ±15).
- **One central elevator/spine column.** ~4 × 4 m footprint with chamfered
  corners. Built by `FloorChrome.build_elevator_core`; taller than the wall trim
  so it pokes above the ceiling and reads as a multi-story shaft. The chamfered
  corner faces hold spine pipes; the **Utility** floor (Floor 0) distributes its
  six live pipes across them, and every other floor renders **passive** copies via
  `FloorChrome.build_passive_spine_pipes(self, _c, _gs, elevator_data)`, driven
  from `GameState.utility.pipe_active`, so an online lane glows on every floor it
  passes through — not just the floor where you flipped the switch.

A floor that needs more space negotiates that as a design exception (e.g. the open
Roof). A floor that needs *less* doesn't exist — shrinking the footprint breaks the
visual continuity.

---

## 2. Walls and chrome

Built by `scenes/shared/floor_chrome.gd` (a `RefCounted`, loaded via `preload`,
NOT `class_name` — F-010). Every floor's `_ready()` calls into it:

```gdscript
const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

FloorChrome.build_slab(self, _c)              # + optional shaft_half to cut a central hole
FloorChrome.build_walls(self, _c)             # doorways:bool, seal:bool, seal_height:float
FloorChrome.build_extension_grid(self, _c)
var elevator_data = FloorChrome.build_elevator_core(self, _c)
FloorChrome.build_passive_spine_pipes(self, _c, _gs, elevator_data)
```

The slab is a `StaticBody3D` named **`SlabBody`** on collision **layer 2**. The
tower toggles each floor's `SlabBody.collision_layer` by the player's current
floor — floors ABOVE you switch off, so a jump arcs straight up through the
ceiling and falls back to the SAME floor (vertical travel is the elevator / stairs
/ vacuum hop, never jumping). The Canopy's slab is the exception (see §11).

The walls are: low solid base + vertical posts + translucent glass + thin top
trim. `seal` raises an invisible collision wall (`WALL_SEAL_HEIGHT`) so a charged
jump can't clear the perimeter — leave it off for the basement and for grade
floors with doorways (the Garden), where it would bleed into the opening. The
blueprint **extension grid** past each wall is the visual language for "the tower
could keep growing here". Wall height: `WALL_HEIGHT`. Don't override.

---

## 3. Vacuum tubes (corner cargo conduits)

Every floor has **four corner vacuum tubes** (`scenes/shared/vacuum_tube.gd`),
inset from the walls. Constants: `VACUUM_TUBE_*`.

- The **down** port routes produce down the shaft and out to the world for cash.
  Player drops a full backpack with E → `+$N (M sold)` floater + whoosh on the
  tube glow.
- The **up** port is sealed unless a floor exists above (build-state dependent).
- The four corner tubes double as the **vacuum-lift hop** path
  (`scenes/shared/vacuum_lift.gd`): standing in a corner mouth, **jump** hops you
  up one floor and **down** hops you down one (±1, reaches every floor 0→Roof).
  The Roof is tube-only; the Canopy has no elevator stop, so the tubes + stairs
  are how you reach it.

The **Utility** floor (Floor 0) is the special case: its tubes terminate at the
central spine's six lanes (water, power, atmosphere, data, waste, cargo); the
cargo lane receives produce dropped from the floors above.

---

## 4. Camera

There is **one** camera for the whole tower: `CameraPivot/Camera3D` in
`tower.tscn`, scripted by `scenes/garden/iso_camera.gd` (the `iso_*` name
describes the *renderer*, not the Garden — it serves every floor). Orthographic,
tilt `CAMERA_TILT_DEG` (−30°), initial yaw `CAMERA_YAW_DEG_INITIAL` (−135°),
size `CAMERA_ORTHO_SIZE_DEFAULT` (40). The tower owns pivot **y** (floor + jump +
fall follow); the camera owns pivot **xz** (player follow + lead).

Affordances (consistent on every floor):
- **Q / R** — 90° rotation snaps around the pivot.
- **Mouse wheel** or **`=` / `-`** — zoom (clamped `CAMERA_ORTHO_SIZE_MIN..MAX`).
- **Middle-drag / left-drag** — pan.
- **Camera modes** iso / profile / over-shoulder via the bottom-right
  `CameraModesHud`.
- **Dialogue close-up** — automatic when `GameState.dialogue_open` flips; tweens
  to the player + NPC midpoint and orbits. Floors with no dialogue NPC simply
  never set the flag, so it's a no-op.

`iso_camera._process` hands the camera off entirely to whichever exclusive mode is
active (construction view, exterior walk, arrival cinematic, re-entry ease, Sky
Lounge look-out, dialogue) and resumes cleanly when it clears.

---

## 5. Lighting

Every floor lights its character and its critical interactables with soft top-down
spotlights, even in a fully-lit room — the visual hook that says "the tower cares
about *people*, not just spaces."

- **Player follow-spotlight** (`PlayerSpot`, a `SpotLight3D` child of the single
  `Player` node in `tower.tscn`). Energy varies per floor: dimmer where ambient is
  bright, brighter where ambient is low.
- **Fixed spotlights on critical interactables** (e.g. the Utility master
  breaker), pulled to ~30 % energy once the floor's primary lighting comes on so
  they stay subtly visible as returnable targets.
- **Always-on emergency overhead Omni** for any floor with a pre-lit intro state,
  so the room is readable before its master switch activates.

Per-floor lighting identity (ambient colour/energy, background, sun energy,
sky-exposure) lives in `tower_controller._preset_for(level)`; time-of-day
modulates on top, scaled by each floor's exposure.

---

## 6. HUD layout

One shared `HUD` CanvasLayer in `tower.tscn`; per-floor groups (`GardenGroup`,
`UtilityGroup`, …) toggle visibility by current floor. Each region has a defined
purpose; floors fill the slots they need and don't poach reserved ones.

- **Top-left — Floor identity + controls.** Large amber `HeaderLabel`
  (e.g. `FLOOR 0 / UTILITY`); dim `ControlsLabel`, 3–5 short lines, related keys
  grouped with `·` separators.
- **Top-right — Per-floor primary status.** Garden → resources (Backpack, Cash);
  Utility → `SystemsHud` (per-system offline/connected/online dot). Pick the one
  stat that defines the floor's loop. Consistent `PanelContainer` styling.
- **Bottom-left — Conversational dialogue** (Cody chat panel when open).
- **Bottom-centre — Floor-specific tools** (Garden's `SeedHud`). Empty otherwise.
- **Bottom-right — `CameraModesHud`.** Always present; don't put anything else here.
- **Centre — modal overlays** (Schematics, etc.). Hidden by default.

Don't: put a floor name bottom-right (collides with camera modes), or pile
resources into bottom-centre (the controls hint + SeedHud already share that lane).

---

## 7. Player + spawn

There is **one** `Player` (a `CharacterBody3D`) for the whole tower; you don't
re-spawn per floor, you traverse to floors. The tower owns the spawn
(`tower_controller._spawn_in_garden`): the player starts on the **Garden**
(Floor 1, the ground floor) facing the camera. Arrival on any other floor is
handled by the traversal that took you there — the elevator car repositions the
rider as it stops, the stairs/hop land you on solid slab — so you never appear
inside a wall or the elevator collision.

A scripted intro (e.g. the Garden arrival cinematic) drives the player via
`tower_controller`, which sets velocity/position directly while suppressing input.

---

## 8. Interaction grammar

- **Tap-E** for any verb. No long holds; the iso idiom is tap-and-tween (~0.5 s
  animation, no charge bar) and every floor matches it. (Exception: the charged
  *jump* is a deliberate movement verb, not an interaction.)
- **3D `Label3D` prompts** float above an interactable in range: an `[E]` glyph
  over a verb subtitle, billboarded + outlined. Hidden when the verb no longer
  applies. Use `scenes/shared/label_scaler.gd` so prompts hold a roughly constant
  screen size as the camera zooms.
- **The HUD's controls hint** lists the floor's verbs in one column; match the
  existing format so floors feel related.

---

## 9. Constants and state

- Per-floor constants live as a **content-named** block in
  `autoloads/constants.gd` (e.g. `UTILITY_*`, `GARDEN_*`, `ARBORETUM_*`,
  `CANOPY_*`). **Do not embed floor numbers in names** — the Session-9 renumber
  left a trail of stale `FLOOR_1_*`/`FLOOR_4_*` identifiers that had to be
  renamed; content names don't go stale.
- Per-floor runtime state lives in a typed dict on `autoloads/game_state.gd`,
  keyed by **content name** (e.g. `GameState.utility = { master_on, connected,
  pipe_active }`, `GameState.arboretum.trees`). It persists across floor
  transitions because it's autoload state. **Litmus:** what's *true* in the world
  → `GameState`; what should *happen next* → `GameDirector`.

---

## 10. Adding a new floor — checklist

(See `CLAUDE.md` "Constraints" for the authoritative version.)

- [ ] New content-named dir `scenes/<name>/` + a `<name>.gd` controller
      (`extends Node3D`), building geometry procedurally in `_ready()`.
- [ ] `_ready()` calls `FloorChrome.build_slab / build_walls /
      build_extension_grid / build_elevator_core / build_passive_spine_pipes`,
      plus `VacuumTube.build_corner_tubes`.
- [ ] Wired into `tower.tscn` as a `Floors/<Name>` node, and into
      `tower_controller._FLOORS` (node path + level + display name).
- [ ] If elevator-served, add the level to `elevator_platform.gd`'s `SERVED`
      list + `NAMES`. (Canopy is stairs/hop-only; Roof is tube-only.)
- [ ] Per-floor state dict on `GameState` (content-named key).
- [ ] Content-named constants block in `autoloads/constants.gd`.
- [ ] A `▾ CHAPTERS` entry in `scenes/shared/chapter_jump.gd` + the
      `tower_controller` chapter map, so you can jump straight to it while iterating.
- [ ] Verify every visual/behavioural change with the **windowed** screenshot
      harness (`agent/rules/godot_screenshot_harness.md`) — never `--headless` for
      capture.

The two blank floors (`scenes/residential/`, `scenes/sky_lounge/`) are the minimal
template to copy.

---

## When to break a rule

If breaking one of these makes a floor *feel* obviously better, do it and document
the deviation below. The default is conformance; the exception is reasoned and
recorded.

---

## 11. Documented deviations

### Canopy (Floor 3) — no elevator stop, stairs/hop access

The Canopy is reachable only by the straight staircase up from Arboretum-ground
(Floor 2, `scenes/shared/stairs.gd`) or a corner vacuum hop — not the elevator.
The elevator geometry + spine pipes still pass through so the architectural
continuity reads, but the level is absent from the elevator `SERVED` list. Intent:
making the canopy lift-private gives it a more elevated, contemplative feel and
turns the stairs into meaningful architecture.

### Canopy (Floor 3) — slab is tiled, not a single box

Where other floors use `FloorChrome.build_slab` (single `BoxMesh`), the Canopy
builds its slab tile-by-tile in `arboretum_canopy.gd` so it can punch holes for:
(1) the central elevator footprint, (2) the stairwell aperture, and (3) each edge
tree plot (mature crowns emerge through; a dark rim reads the hole). Its slab is on
collision **layer 1** and is **never toggled off** — it stays a solid **glass
ceiling**: from Floor 2 you can't jump through it (you bonk it, which lights a
localized glow), and standing on Floor 3 it's a translucent glass floor. This
tile-with-holes pattern is the right move whenever a floor's slab needs cutouts.

### Arboretum (Floors 2-3) — edge-only growing plots, trees span two floors

The Arboretum plants on an every-other-cell ring just inside the walls
(`ARBORETUM_EDGE_INSET`, `ARBORETUM_PLOT_STRIDE`), keeping it a curated arboretum
(not a hedge) with the centre clear for the elevator + stairs. A tree is a single
physical object owned by **Floor 2** that passes up through the Canopy's slab hole:
Floor 2 renders trunk + lower foliage, the **Canopy (Floor 3)** renders the crown
above the slab. Floor 2 owns the state in `GameState.arboretum.trees`; the Canopy
reads the same dict and renders its slice — the same cross-floor render pattern as
`build_passive_spine_pipes` driving off `GameState.utility`.
