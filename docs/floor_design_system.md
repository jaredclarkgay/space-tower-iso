# Floor Design System

The Space Tower has many floors. This doc captures the rules every floor
follows so they read as the same building viewed at different stories,
and so a player who learned how to operate one floor can operate any
other one without retraining.

These are constraints, not suggestions. New floors follow them by default;
deviations require an explicit reason.

---

## 1. Footprint

- **30 × 30 m square slab.** Constants: `FLOOR_3D_SIZE = 30.0`.
- **Slab thickness** `FLOOR_3D_SLAB_THICKNESS = 0.2` m. Top face at y = 0.
- **Floor centred on the world origin** (xz extent: ±15).
- **One central elevator/spine column.** 4 × 4 m square footprint with
  the four corners chamfered at 45° (octagonal-ish cross-section, see
  `ELEVATOR_CHAMFER`). Taller than the wall trim (`ELEVATOR_HEIGHT_MULT
  × WALL_HEIGHT`) so it pokes above the ceiling and reads as a
  multi-story shaft. The four cardinal faces hold sliding doors (built
  + animated by `ElevatorHandler`); the four chamfered corner faces
  hold spine pipes — Floor 1 distributes its six pipes 1-2-1-2 across
  them, and every other floor renders **passive** copies of the same
  pipes (via `FloorChrome.build_passive_spine_pipes`) reading
  GameState.floor_1 so an online lane glows on every floor it passes
  through, not just the floor where you flipped the switch. Collision
  is on the chamfer panels only — the cardinal-face areas are passable
  so the player can walk INTO the elevator through the doors.

  Travel sequence (`ElevatorHandler` state machine):

  1. **PROXIMITY** (default): doors slide apart as the player approaches,
     close as they walk away. Glow at baseline (faint blue).
  2. **DEPARTING** (E pressed near elevator): doors slide closed around
     the player; inner core glow ramps up to a hot yellow over the same
     0.35 s; brief 0.1 s held pose with doors shut + glow at full;
     0.4 s screen fade-to-black; `change_scene_to_file`.
  3. **ARRIVING** (next floor's `_ready`, with `GameState.in_transit`):
     player positioned at elevator centre, doors closed, glow at full.
     0.4 s fade-in from black; 0.3 s held pose with doors still shut +
     glow on; 0.4 s doors slide apart while glow fades to baseline.
     Returns to PROXIMITY.

  The yellow glow leaks visibly through the seams between door panels
  and the gaps between chamfer panels — that's the visual signature of
  "rider inside the column."

A floor that needs more space negotiates that as a design exception
(e.g. an open rooftop). A floor that needs *less* doesn't exist —
shrinking the footprint breaks the visual continuity.

---

## 2. Walls and chrome

Built by `scenes/shared/floor_chrome.gd`. Every floor calls:

```gdscript
const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

FloorChrome.build_slab(self, _c)
FloorChrome.build_walls(self, _c)
FloorChrome.build_extension_grid(self, _c)
FloorChrome.build_elevator_core(self, _c)
```

The walls are: low solid base + vertical posts + translucent glass +
thin top trim. The blueprint extension grid extends past each wall
(6 lines per side fading to transparent + a perpendicular crossbar),
which is the visual language for "the tower could keep growing here".

Wall height: `WALL_HEIGHT = 2.6` m. Don't override. A floor with extra
ceiling height belongs to a different visual category (exterior, atrium).

---

## 3. Vacuum tubes (corner cargo conduits)

Every floor has **four corner vacuum tubes** placed inset from the wall:
- Constants: `VACUUM_TUBE_INSET`, `VACUUM_TUBE_RADIUS`,
  `VACUUM_TUBE_HEIGHT`, `VACUUM_TUBE_INTERACT_RADIUS`.
- `VACUUM_TUBE_HAS_FLOOR_ABOVE = false` seals the up port; the same flag
  set true on a floor with a story above unlocks bidirectional routing.
- Down port routes to Floor 1 → out to the world for cash. Player drops
  full backpack with E, sees `+$N (M sold)` floater + whoosh on the
  tube glow.

Floor 1 is the special exception: tubes don't terminate at the floor's
own corners — they terminate at the central spine's six lanes (water,
power, atmosphere, data, waste, cargo). The cargo lane is what receives
produce dropped through other floors' corner tubes.

---

## 4. Camera

`scenes/floor_2/iso_camera.gd` is the canonical floor camera. Every
floor's `.tscn` has the same node structure:

```
CameraPivot (Node3D, position (0, 1, 0))
  Camera3D (script = iso_camera.gd, projection = ORTHOGONAL, size = 40)
```

Camera affordances every floor inherits:
- **Q / R** — 90° rotation snaps (around the pivot)
- **Mouse wheel** or **`=` / `-`** — zoom (clamped to
  `CAMERA_ORTHO_SIZE_MIN..MAX`)
- **Middle-drag or left-drag** — pan
- **Camera mode toggle** (iso / profile / over-shoulder) via the
  `CameraModesHud` Control, anchored bottom-right
- **Dialogue close-up** — automatic when `GameState.dialogue_open` flips,
  tweens to a player + NPC midpoint

A floor with no dialogue NPC (Floor 1 today) leaves the
`iso_robot_path` empty on the camera; the dialogue close-up is gated on
non-null `_iso_robot`, so the missing reference is a no-op.

Tilt: -30° on X. Yaw: -135° initial. Distance 20. Ortho size 40.
Constants: `CAMERA_TILT_DEG`, `CAMERA_YAW_DEG_INITIAL`,
`CAMERA_DISTANCE`, `CAMERA_ORTHO_SIZE_DEFAULT`.

---

## 5. Lighting

Every floor lights its character and its critical interactables with
soft top-down spotlights, even in a fully-lit room. This is the visual
hook that says "the tower cares about *people*, not just spaces."

- **Player follow-spotlight** parented to `IsoPlayer` in the .tscn:
  ```
  [node name="PlayerSpot" type="SpotLight3D" parent="World/IsoPlayer"]
  position = Vector3(0, 3.2, 0)
  rotation_degrees = Vector3(-90, 0, 0)
  spot_range = 4.5
  spot_angle = 38.0
  spot_attenuation = 0.7
  ```
  Energy varies per floor: dimmer (0.9) where ambient is bright, brighter
  (1.4) where ambient is low.
- **Fixed spotlights on critical interactables** (e.g. Floor 1's master
  breaker). Pulled into 30 % energy when the floor's primary lighting
  comes on so they stay subtly visible as returnable targets.
- **Always-on emergency overhead OmniLight** for any floor that has a
  pre-lit (intro) state — gives the room enough fill to be readable
  before the master breaker / equivalent activates.

---

## 6. HUD layout

Each region has a defined purpose. Floors fill in the slots they need;
they don't put content in slots reserved for other purposes.

- **Top-left — Floor identity + controls.**
  - `HeaderLabel`: large amber title, e.g. `FLOOR 1 / UTILITY`. The first
    thing the player reads when the scene loads.
  - `ControlsLabel`: dim, smaller, 3–5 short lines max. Group related
    keys with `·` separators rather than one-key-per-line.
- **Top-right — Per-floor primary status panel.**
  - Garden: `ResourcesPanel` (Backpack count, Cash).
  - Floor 1: `SystemsHud` (offline/connected/online dot per system).
  - Future floors: pick the one stat that defines the floor's loop.
  - Style is consistent: `PanelContainer` with `ResourcePanelStyle`
    (warm-cream borders, dark-olive bg, drop shadow).
- **Bottom-left — Conversational dialogue.** Cody chat panel when open;
  empty otherwise.
- **Bottom-centre — Floor-specific tools.** Garden uses this for
  `SeedHud`. Floors with no tool stack leave it empty.
- **Bottom-right — `CameraModesHud`.** Always present, always at the
  bottom-right corner with consistent margin. Don't put anything else
  here.
- **Centre — modal overlays.** Schematics, future floor-specific
  modals. Hidden by default.

What NOT to do: put a floor name in the bottom-right (collides with
camera modes), or pile resources into the bottom-centre (the controls
hint and the SeedHud already share that visual lane).

---

## 7. Player spawn

Every floor spawns the player just south of the elevator core, at
`Vector3(0, 0.2, 3.0)`. The player's facing yaw is set to face the
camera (`deg_to_rad(CAMERA_YAW_DEG_INITIAL)`), so on first frame their
front is visible rather than their back. The same position + facing is
applied on arrival via the elevator (`ElevatorHandler` repositions the
player after the scene swap so they exit through the south door
instead of inside the elevator collision shape).

If a floor needs the player to spawn elsewhere (e.g. a cinematic intro),
override the `IsoPlayer` transform in that floor's `.tscn` and reset
the facing yaw with `IsoPlayer.set_facing_yaw(...)`.

---

## 8. Interaction grammar

- **Tap-E** for any verb. No 1.6/1.2/0.9-second holds; the iso slice
  established a tap-and-tween idiom (~0.5 s animation, no charge bar)
  and every floor matches that.
- **3D Label3D prompts** float above an interactable when the player is
  in range. Format: an `[E]` glyph above a verb subtitle, both billboarded
  + outlined for legibility. Hidden when the verb is no longer applicable
  (e.g. master breaker prompt hides once the breaker is on).
- **The HUD's controls hint** lists the floor's verbs in one column;
  match the existing format so floors feel related.

---

## 9. Constants and state

- Per-floor constants live as a `FLOOR_<n>_*` block in
  `autoloads/constants.gd`, after the shared base constants.
- Per-floor runtime state lives in a typed dict on `autoloads/game_state.gd`,
  e.g. `GameState.floor_1 = { master_on, connected, pipe_active }`.
  Persists across scene swaps via the autoload.
- Multi-floor save/load (when it lands) reads/writes those dicts.

---

## 10. Adding a new floor — checklist

- [ ] `scenes/floor_<n>/floor_<n>.tscn` + `floor_<n>.gd`
- [ ] `_ready` calls `FloorChrome.build_slab/walls/extension_grid/elevator_core`
- [ ] Camera setup uses `CameraPivot` + `Camera3D` with `iso_camera.gd`
- [ ] HUD includes `CameraModesHud`, controls hint top-left
- [ ] `IsoPlayer` is reused; add `PlayerSpot` SpotLight3D as child
- [ ] Four corner `VacuumTube` nodes (or the floor's equivalent — Floor 1
  uses the central spine instead)
- [ ] State dict added to `GameState`
- [ ] Per-floor constants block in `autoloads/constants.gd`
- [ ] Backslash debug-swap available until the elevator wires properly (M6)

---

## When to break a rule

If breaking one of these makes a floor *feel* obviously better, do it
and document the deviation here. The default is conformance; the
exception is reasoned and recorded.

---

## 11. Documented deviations

### Floor 4 (Canopy) — no elevator stop, stairs-only access

Floor 4 is reachable ONLY by walking up the spiral staircase from Floor 3
(`scenes/shared/spiral_staircase.gd`). The elevator's geometry still
passes through Floor 4's slab (the central square footprint is cut out)
and the spine pipes still render so the architectural continuity reads,
but no `ElevatorHandler` is instanced — there is no E-prompt or door
animation. Intent: making the canopy private and unreachable by lift
gives the floor a more elevated, contemplative feel, and turns the
spiral staircase into a meaningful piece of architecture rather than
redundant geometry.

### Floor 4 — slab is tiled, not a single box

Where every other floor uses `FloorChrome.build_slab` (single BoxMesh +
collision), Floor 4 builds its slab tile-by-tile in `floor_4.gd` so it
can punch holes in three regions:
1. Central square ±`ELEVATOR_RADIUS` (elevator passes through).
2. Annular ring `STAIRCASE_HOLE_INNER_RADIUS..STAIRCASE_HOLE_OUTER_RADIUS`
   (staircase emerges from below).
3. Edge tree-plot tiles (mature crowns emerge through; a dark torus
   rim is rendered around each hole for visual read).

This pattern is the right move whenever a floor's slab needs cutouts.
Other floors (Garden, Floor 1) don't need any, so they stay on the
single-box `build_slab` for speed.

### Floors 3-4 (Arboretum) — edge-only growing plots

The Arboretum uses every-other-cell along a 1-cell-deep ring inside the
walls (`ARBORETUM_EDGE_INSET` and `ARBORETUM_PLOT_STRIDE`). With
`GARDEN_GRID_SIZE = 30` this yields ~52 plots. The choice keeps the
floor reading as a curated arboretum, not a hedge, and leaves the
centre clear for the elevator + spiral staircase. Tree visuals span
two floors: trunk + lower foliage on Floor 3, upper trunk + canopy
on Floor 4. Floor 3 owns the tree state in `GameState.floor_3.trees`;
Floor 4 reads the same dict and renders its slice (mirrors the
`build_passive_spine_pipes` cross-floor render pattern from Floor 1).
