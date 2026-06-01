# Screenshotting / capturing Godot — the windowed harness skill

This is the single most-used verification tool in this repo: the operator iterates
from screenshots, so being fast + reliable at capturing real rendered frames is a
core skill. Read this before writing any capture; it folds in every sharp edge hit
building `_shot_harness`, `_lookout_harness`, and `_shaft_harness`.

## The one rule that matters: WINDOWED, never `--headless`

`--headless` renders NOTHING — `get_viewport().get_texture()` is blank. To capture
a real frame you must run windowed so the GPU actually draws:

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # CLI often not on $PATH
"$GODOT" --path . _my_harness.tscn                   # windowed → frames render
```

Use `--headless` ONLY for the two non-visual steps:
- `"$GODOT" --headless --path . --import` — regenerate `.uid` after adding a new
  `.gd`/`.tscn` (else an ext_resource can resolve to a script-less node; see
  `godot_script_uid.md`).
- `"$GODOT" --headless --path . scenes/tower/tower.tscn --quit-after 90` — a fast
  parse/script SMOKE test. Silent = clean. Always smoke before the windowed shot.

## The harness shape (copy-paste template)

A harness is a tiny `Node3D` script + a 4-line `.tscn`. It instances the real game
scene, drives it into the state you want, saves PNGs, and quits.

```gdscript
extends Node3D
const SHOT_DIR := "res://_shots/<group>/"          # _shots/ is gitignored — no PNG bloat
var _tower: Node
var _c: Node
var _gs: Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_tower = load("res://scenes/tower/tower.tscn").instantiate()
	add_child(_tower)
	_c = get_node("/root/Constants")
	_gs = get_node("/root/GameState")
	await _wait(50)                                  # let _ready + procedural builds settle

	var player: Node3D = _tower.get_node("Player")
	# ... drive state (see below) ...
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "1_thing.png")
	print("state check: y=%.2f flag=%s" % [player.global_position.y, str(_gs.get("looking_out"))])
	get_tree().quit()

func _wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
```

```
[gd_scene format=3]
[ext_resource type="Script" path="res://_my_harness.gd" id="1"]
[node name="MyHarness" type="Node3D"]
script = ExtResource("1")
```

Harnesses are **throwaway**: `/_*_harness.*` and `/_shots/` are gitignored (not part
of the game) — recreate from this template anytime, in seconds. Name them
`_<thing>_harness.gd/.tscn` so the ignore pattern catches them.

## Driving the scene into a state

- **Teleport the player:** set `player.global_position` AND zero the velocity
  (`(player as CharacterBody3D).velocity = Vector3.ZERO`) or momentum carries.
- **Set GameState flags directly:** `_gs.set("looking_out", true)`, etc.
- **Held input:** `Input.action_press(&"camera_rotate_right")` … `await _wait(30)` …
  `Input.action_release(...)`. Polled (`Input.is_action_pressed`) code reacts; one-shot
  `is_action_just_pressed` is awkward to fake — prefer calling the method directly.
- **Call "private" methods directly:** GDScript lets you, e.g.
  `lift.call("_begin_hop", 0, level)`, `sky.call("_enter_look_out", Vector3(1,0,0))`.
- **Climb floors:** `VacuumLift._begin_hop(corner, level)` sets the transit flag so the
  tower tracks `_current_level` and the destination slab is solid on arrival.

## Two capture modes — pick deliberately

1. **Override camera** — make your OWN camera to inspect geometry from a chosen angle:
   ```gdscript
   var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL
   cam.size = 22.0; add_child(cam); cam.make_current()
   cam.global_position = c + Vector3(-13, 11, -15); cam.look_at(c, Vector3.UP)
   ```
   Use for framing a specific object (e.g. the elevator core on each floor).

2. **The game's OWN camera** — do NOT override; let the real `iso_camera` drive, and
   force it current to be sure: `_tower.get_node("CameraPivot/Camera3D").make_current()`.
   REQUIRED when verifying camera behaviour itself (the look-out POV, mode tweens).

## Gotchas that cost real time here

- **Grounding gates `_current_level`.** The tower only updates the current floor when
  the player is grounded / riding / hopping. If you teleport straight onto a target
  spot mid-air, `_current_level` stays stale → that floor's slab collision is gated OFF
  → the player falls through. Fix: land them on SOLID ground on the target floor first
  (`await _wait(40)` to ground), THEN nudge to the spot under test. (This is also why
  the shaft-grate test grounds on the slab before stepping onto the shaft.)
- **Windowed runs render at HIGH fps**, so `await _wait(60)` is far fewer real seconds
  than 60/60 s. Never gate a state transition or an assertion on an exponential ease
  CONVERGING within N frames — it may not. Use fixed-duration timers for transitions
  (the look-out exit-restore bug was a distance threshold that never met), and assert
  with tolerance, not exact convergence.
- **Print state alongside the PNG.** Numbers confirm what the eye can't: positions,
  `GameState` flags, `cam.projection` (0 = PERSPECTIVE, 1 = ORTHOGONAL — easy to misread).
- **Filter the run output** for real errors: `... 2>&1 | grep -iE "error|nil|invalid|
  null instance" | grep -viE "shader|processor|vulkan|opengl"`.
- **Editor cache** can mask disk fixes — if a `.tscn` change "doesn't take", see
  `godot_editor_cache.md` (`rm -rf .godot/`).

## Reading the result

Capture to `_shots/<group>/`, then view the PNGs with the Read tool to judge them, and
cross-check the printed state. Name shots by sequence (`1_interior`, `2_pov`, …) so a
before/after reads at a glance.

## See also
- `space-tower-screenshot-harness` memory (cross-session pointer to this).
- `godot_script_uid.md` (run `--import` after new scripts), `godot_editor_cache.md`.
- Worked examples (throwaway — may be on disk from a recent session, else rebuild
  from the template): `_shot_harness` (all floors, override cam), `_lookout_harness`
  (game cam, drives the look-out POV), `_shaft_harness` (physics assertion,
  ground-then-move). Their patterns are all captured above.
