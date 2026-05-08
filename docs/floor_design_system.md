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
- **One central elevator/spine column.** 4 × 4 m footprint, full wall
  height, translucent shaft. `FloorChrome.build_elevator_core()` is the
  canonical builder.

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

`scenes/iso_prototype/iso_camera.gd` is the canonical floor camera. Every
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

- **Top-left:** controls hint (small Label, monospace)
- **Top-right:** Resources panel (`HUD/ResourcesPanel`) — Backpack, Cash,
  any future per-floor counters
- **Bottom-left:** Cody dialogue panel when open (left-half-anchored)
- **Bottom-centre:** Seed selector HUD (Garden only — tied to planting)
- **Bottom-right:** `CameraModesHud` — three-button camera mode strip
- **Centre:** modal overlays (Schematics, future floor-specific modals)

---

## 7. Interaction grammar

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

## 8. Constants and state

- Per-floor constants live as a `FLOOR_<n>_*` block in
  `autoloads/constants.gd`, after the shared base constants.
- Per-floor runtime state lives in a typed dict on `autoloads/game_state.gd`,
  e.g. `GameState.floor_1 = { master_on, connected, pipe_active }`.
  Persists across scene swaps via the autoload.
- Multi-floor save/load (when it lands) reads/writes those dicts.

---

## 9. Adding a new floor — checklist

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
