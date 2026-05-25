extends Node3D

# Elevator interaction shared by every floor. The central elevator core
# is geometry built by FloorChrome — this handler attaches to the floor
# scene and adds the verb: walk near the core, tap E, fade to black,
# change to the linked floor, fade back in.
#
# `target_scene_path` is the .tscn to switch to. `target_label` is the
# human-readable destination ("Garden", "Utility") used in the prompt.
# Per-floor instances set both via @export from the .tscn. GameState.
# in_transit coordinates the fade-in on the receiving scene's _ready.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var target_scene_path: String = ""
@export var target_label: String = ""
# "up" or "down" — drives the prompt arrow and the directional feel.
@export var direction: String = "up"
@export var player_path: NodePath
# Floor controller exposing _elevator_data dict (FloorChrome's return) —
# carries the inner-core material reference so the handler can drive the
# yellow travel glow.
@export var floor_provider_path: NodePath

# Multi-destination elevator. Each entry is a Dictionary with keys:
#   scene:     String — res://...tscn to switch to
#   label:     String — human-readable destination ("Garden", "Utility")
#   direction: String — "up" or "down"
# When this array has 2+ entries, tapping E opens a chooser; the player
# presses a number key (1..N) to pick a destination. When it has 0 entries
# AND target_scene_path is set, the legacy single-destination fields are
# used as a fallback (one synthesized entry). 1 entry behaves the same
# as the legacy single-target wiring — no chooser, just go.
@export var destinations: Array = []
# Normalized at _ready from `destinations` (or synthesized from the
# legacy target_* fields if destinations is empty). All runtime logic
# reads this list — never the export directly.
var _dests: Array = []
var _player: Node3D
var _floor_provider: Node

# Player's resting position once they've stepped out of the elevator.
# Travel-arrive places them at the elevator centre and lets the doors
# open around them.
const ARRIVAL_POSITION := Vector3(0, 0.2, 0.0)

# Door panels — 8 total (2 per cardinal face). Each pair slides apart
# along the face's tangent axis when the player is in interaction range.
# Built procedurally from the elevator's geometry constants in _ready.
var _door_panels: Array = []   # list of {pivot: Node3D, base: Vector3, tangent: Vector3, slot_sign: int}
var _doors_open_t := 0.0       # 0 closed, 1 fully open

# Elevator inner-core material reference. Pulled from the floor
# controller's _elevator_data; tweened to a yellow high-energy emission
# during DEPARTING + ARRIVING, decays back to the baseline blue glow
# in PROXIMITY.
var _inner_mat: StandardMaterial3D
var _inner_mat_base_emission: Color = Color(0.30, 0.55, 0.85)
var _inner_mat_base_energy: float = 0.4
var _glow_t := 0.0   # 0 baseline, 1 full travel glow

# Travel state machine.
#   PROXIMITY  — default: doors open/close with player distance, E shows prompt.
#   CHOOSING   — E pressed with 2+ destinations: chooser visible, listening
#                for number keys to pick. ESC returns to PROXIMITY.
#   DEPARTING  — destination chosen: doors close, glow ramps, fade-to-black,
#                change_scene_to_file.
#   ARRIVING   — receiving scene: fade-in, hold, doors open + glow fades.
const DOOR_STATE_PROXIMITY := 0
const DOOR_STATE_CHOOSING := 1
const DOOR_STATE_DEPARTING := 2
const DOOR_STATE_ARRIVING := 3
var _door_state: int = DOOR_STATE_PROXIMITY
# Time elapsed in the current state, used to drive the multi-step
# departure / arrival animations.
var _state_t := 0.0
# Destination index chosen during CHOOSING, consumed by DEPARTING.
var _chosen_dest: Dictionary = {}

# Travel timing — see _update_travel_state for what each segment owns.
const DEPART_DOOR_CLOSE := 0.35
const DEPART_HOLD := 0.10
const DEPART_FADE := 0.40
const ARRIVE_FADE := 0.40
const ARRIVE_HOLD := 0.30
const ARRIVE_DOOR_OPEN := 0.40

# Prompt above the elevator. Built once; visibility + position lerp.
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D
# Chooser label appears beneath the standard prompt during CHOOSING state,
# listing all available destinations with their number-key prefixes.
var _chooser_label: Label3D

# Fade overlay — full-screen ColorRect on a CanvasLayer, alpha-tweened.
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect

const INTERACT_RADIUS := 2.6   # slightly outside the 4×4 elevator core
const FADE_DURATION := 0.4


func _ready() -> void:
	if player_path:
		_player = get_node(player_path)
	if floor_provider_path:
		_floor_provider = get_node(floor_provider_path)
		var data: Dictionary = _floor_provider.get("_elevator_data") if _floor_provider else {}
		if data and data.has("inner_mat"):
			_inner_mat = data.inner_mat
	_normalize_destinations()
	_build_prompt()
	_build_fade()
	_build_doors()
	# Arrival path — start in ARRIVING state. Player at elevator centre,
	# doors closed, glow on. State machine ramps fade-in → hold → doors
	# open + glow fades, then settles to PROXIMITY. Fresh F5 (no
	# in_transit) skips this and opens in PROXIMITY.
	if _gs.get("in_transit"):
		if _player:
			_player.global_position = ARRIVAL_POSITION
			if _player.has_method("set_facing_yaw"):
				_player.set_facing_yaw(deg_to_rad(_c.CAMERA_YAW_DEG_INITIAL))
		_door_state = DOOR_STATE_ARRIVING
		_state_t = 0.0
		_doors_open_t = 0.0
		_glow_t = 1.0
		_apply_glow()
		_apply_door_offsets()
		_fade_rect.color.a = 1.0
		_fade_rect.visible = true
		_gs.set("in_transit", false)
	else:
		_apply_glow()


func _process(delta: float) -> void:
	if _player == null:
		return
	if _door_state == DOOR_STATE_PROXIMITY:
		_update_proximity_state(delta)
	elif _door_state == DOOR_STATE_CHOOSING:
		_update_choosing_state(delta)
	elif _door_state == DOOR_STATE_DEPARTING:
		_update_departing_state(delta)
	elif _door_state == DOOR_STATE_ARRIVING:
		_update_arriving_state(delta)
	_apply_door_offsets()
	_apply_glow()


func _update_proximity_state(delta: float) -> void:
	var pos: Vector3 = _player.global_position
	var d: float = Vector2(pos.x, pos.z).length()
	var in_range: bool = d <= INTERACT_RADIUS
	# In PROXIMITY, show the "E" + "Travel to X" pair, hide the chooser.
	_prompt_root.visible = in_range
	_prompt_e.visible = in_range
	_prompt_label.visible = in_range
	if _chooser_label:
		_chooser_label.visible = false
	# Doors hover open while the player is in range whether or not there's
	# a destination (lets the player walk into the elevator on every floor).
	var target_door: float = 1.0 if in_range else 0.0
	var rate: float = 1.0 / _c.ELEVATOR_DOOR_OPEN_DURATION
	_doors_open_t = move_toward(_doors_open_t, target_door, rate * delta)
	# Glow decays back to baseline.
	_glow_t = move_toward(_glow_t, 0.0, delta / 0.4)
	if in_range and Input.is_action_just_pressed(&"interact"):
		# 0 destinations: nothing to do (defensive; should never ship live).
		# 1 destination: skip the chooser, depart directly.
		# 2+ destinations: enter CHOOSING and wait for a number-key pick.
		if _dests.size() == 1:
			_chosen_dest = _dests[0]
			_begin_departing()
		elif _dests.size() > 1:
			_door_state = DOOR_STATE_CHOOSING
			_state_t = 0.0


# Player is parked at the elevator and the chooser is visible. Picks are
# polled via the existing `seed_select_N` InputMap actions (already bound
# to KEY_1..KEY_6 in project.godot) AND via the _input fallback for keys
# beyond 6. Polling works reliably regardless of input-event dispatch
# quirks (some Mac keyboard layouts route number keys through unicode
# rather than keycode, which broke the original _input-only handler).
# ESC returns to PROXIMITY; walking out of range also cancels.
func _update_choosing_state(delta: float) -> void:
	var pos: Vector3 = _player.global_position
	var d: float = Vector2(pos.x, pos.z).length()
	if d > INTERACT_RADIUS + 0.2:
		_door_state = DOOR_STATE_PROXIMITY
		_state_t = 0.0
		return
	# Hide the standard "E" + "Travel" pair, show only the chooser.
	_prompt_root.visible = true
	_prompt_e.visible = false
	_prompt_label.visible = false
	if _chooser_label:
		_chooser_label.visible = true
	# Polled fallback: seed_select_N is bound to KEY_N for N in 1..6. The
	# action names are misleading here ("seed_select" inside the elevator
	# doesn't make sense) — but rebinding would mean a new InputMap entry
	# AND the same bindings, so reusing them is the pragmatic call. Phase 1
	# never has more than 2 destinations per floor; this caps at 6.
	for i in range(min(_dests.size(), 6)):
		var action_name := StringName("seed_select_%d" % (i + 1))
		if InputMap.has_action(action_name) and Input.is_action_just_pressed(action_name):
			_chosen_dest = _dests[i]
			_begin_departing()
			return
	if Input.is_action_just_pressed(&"ui_cancel"):
		_door_state = DOOR_STATE_PROXIMITY
		_state_t = 0.0
		return
	# Keep doors fully open and glow at baseline (no travel yet).
	_doors_open_t = move_toward(_doors_open_t, 1.0, delta / _c.ELEVATOR_DOOR_OPEN_DURATION)
	_glow_t = move_toward(_glow_t, 0.0, delta / 0.4)


func _update_departing_state(delta: float) -> void:
	# Phase 1 (0 .. DEPART_DOOR_CLOSE): doors close, glow ramps yellow.
	# Phase 2 (.. DEPART_HOLD added): doors stay shut, glow at full.
	# Phase 3 (.. DEPART_FADE added): screen fades to black, then change_scene.
	_state_t += delta
	_prompt_root.visible = false
	var t1: float = DEPART_DOOR_CLOSE
	var t2: float = t1 + DEPART_HOLD
	var t3: float = t2 + DEPART_FADE
	if _state_t < t1:
		_doors_open_t = 1.0 - clampf(_state_t / DEPART_DOOR_CLOSE, 0.0, 1.0)
		_glow_t = clampf(_state_t / DEPART_DOOR_CLOSE, 0.0, 1.0)
	elif _state_t < t2:
		_doors_open_t = 0.0
		_glow_t = 1.0
	elif _state_t < t3:
		_doors_open_t = 0.0
		_glow_t = 1.0
		var fade_p: float = clampf((_state_t - t2) / DEPART_FADE, 0.0, 1.0)
		_fade_rect.visible = true
		_fade_rect.color = Color(0.0, 0.0, 0.0, fade_p)
	else:
		_perform_swap()


func _update_arriving_state(delta: float) -> void:
	# Phase 1 (0 .. ARRIVE_FADE): screen fades from black; doors closed,
	# glow on. Phase 2 (.. ARRIVE_HOLD added): screen clear; hold the
	# closed/glowing pose for a beat. Phase 3 (.. ARRIVE_DOOR_OPEN added):
	# doors open, glow fades to baseline. Then back to PROXIMITY.
	_state_t += delta
	_prompt_root.visible = false
	var t1: float = ARRIVE_FADE
	var t2: float = t1 + ARRIVE_HOLD
	var t3: float = t2 + ARRIVE_DOOR_OPEN
	if _state_t < t1:
		_doors_open_t = 0.0
		_glow_t = 1.0
		var fade_p: float = 1.0 - clampf(_state_t / ARRIVE_FADE, 0.0, 1.0)
		_fade_rect.visible = true
		_fade_rect.color = Color(0.0, 0.0, 0.0, fade_p)
	elif _state_t < t2:
		_fade_rect.visible = false
		_doors_open_t = 0.0
		_glow_t = 1.0
	elif _state_t < t3:
		_fade_rect.visible = false
		var p: float = clampf((_state_t - t2) / ARRIVE_DOOR_OPEN, 0.0, 1.0)
		_doors_open_t = p
		_glow_t = 1.0 - p
	else:
		_door_state = DOOR_STATE_PROXIMITY
		_state_t = 0.0


func _begin_departing() -> void:
	_door_state = DOOR_STATE_DEPARTING
	_state_t = 0.0
	_gs.set("in_transit", true)


# Secondary number-key handler for >6-destination floors (Phase 1 caps at
# 2 per floor, so the polled fallback in _update_choosing_state handles
# everything; this is here as a belt-and-suspenders for future floors with
# more options, and works regardless of which input-dispatch path the
# host environment routes number keys through).
func _input(event: InputEvent) -> void:
	if _door_state != DOOR_STATE_CHOOSING:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	# Try keycode (layout-aware), then physical_keycode (layout-independent).
	var idx: int = _keycode_to_index(int(key_event.keycode))
	if idx < 0:
		idx = _keycode_to_index(int(key_event.physical_keycode))
	if idx >= 0 and idx < _dests.size():
		_chosen_dest = _dests[idx]
		_begin_departing()
		get_viewport().set_input_as_handled()


# Maps a KEY_1..KEY_9 keycode to a 0..8 destination index. Returns -1 if
# the keycode isn't a top-row number key.
func _keycode_to_index(kc: int) -> int:
	if kc >= int(KEY_1) and kc <= int(KEY_9):
		return kc - int(KEY_1)
	return -1


func _apply_glow() -> void:
	if _inner_mat == null:
		return
	# Lerp the inner-core material between baseline blue dim and a hot
	# yellow during travel. The seams between door panels (and the gaps
	# between chamfer panels) let this light leak through visibly.
	var travel_emission := Color(1.0, 0.78, 0.20)   # warm yellow
	var travel_energy: float = 4.5
	_inner_mat.emission = _inner_mat_base_emission.lerp(travel_emission, _glow_t)
	_inner_mat.emission_energy_multiplier = lerpf(_inner_mat_base_energy, travel_energy, _glow_t)


func _perform_swap() -> void:
	# Final step of DEPARTING state — change_scene_to_file is deferred,
	# so the new scene's _ready picks up GameState.in_transit and runs
	# the inverse animation (fade-in → hold → doors open + glow fades).
	var path: String = String(_chosen_dest.get("scene", target_scene_path))
	if path == "":
		return
	get_tree().change_scene_to_file(path)


# Reads the destinations export + legacy single-target fields and writes
# the normalized list to _dests. Always non-null after _ready. If both
# inputs are empty, _dests stays empty and the elevator becomes a no-op
# (defensive only; floors that need an elevator stop wire at least one
# destination via the .tscn).
func _normalize_destinations() -> void:
	_dests.clear()
	for entry in destinations:
		if not (entry is Dictionary):
			continue
		var scene_path: String = String(entry.get("scene", ""))
		if scene_path == "":
			continue
		_dests.append({
			"scene": scene_path,
			"label": String(entry.get("label", "")),
			"direction": String(entry.get("direction", "up")),
		})
	if _dests.is_empty() and target_scene_path != "":
		_dests.append({
			"scene": target_scene_path,
			"label": target_label,
			"direction": direction,
		})


func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "ElevatorPrompt"
	_prompt_root.position = Vector3(0, 2.6, 0)
	_prompt_root.visible = false
	add_child(_prompt_root)

	_prompt_e = Label3D.new()
	_prompt_e.text = "E"
	_prompt_e.font_size = 96
	_prompt_e.outline_size = 12
	_prompt_e.modulate = Color(1.0, 0.92, 0.55, 1.0)
	_prompt_e.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_prompt_e.pixel_size = 0.005
	_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_e.no_depth_test = true
	_prompt_e.position = Vector3(0, 0.32, 0)
	_prompt_root.add_child(_prompt_e)

	_prompt_label = Label3D.new()
	# With multiple destinations, the top label reads "Travel" — the
	# chooser label below it enumerates the options. With a single
	# destination, the top label reads "↑ Travel to X" (legacy behaviour).
	if _dests.size() > 1:
		_prompt_label.text = "Travel"
	elif _dests.size() == 1:
		var only: Dictionary = _dests[0]
		var arrow := "↑" if String(only.get("direction", "up")) == "up" else "↓"
		_prompt_label.text = "%s  Travel to %s" % [arrow, only.get("label", "")]
	else:
		_prompt_label.text = "Travel"
	_prompt_label.font_size = 56
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_prompt_label.pixel_size = 0.005
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, 0.0, 0)
	_prompt_root.add_child(_prompt_label)

	# Chooser list — visible only during CHOOSING. The standard "E" + "Travel"
	# pair are hidden in that state, so the chooser owns the visual space
	# above the elevator. Heading + one line per destination + ESC hint.
	if _dests.size() > 1:
		_chooser_label = Label3D.new()
		var lines: PackedStringArray = PackedStringArray()
		lines.append("TRAVEL TO")
		lines.append("")
		for i in range(_dests.size()):
			var dest: Dictionary = _dests[i]
			var arrow_d := "↑" if String(dest.get("direction", "up")) == "up" else "↓"
			lines.append("[%d]   %s   %s" % [i + 1, arrow_d, dest.get("label", "")])
		lines.append("")
		lines.append("[ESC] cancel")
		_chooser_label.text = "\n".join(lines)
		_chooser_label.font_size = 64
		_chooser_label.outline_size = 10
		_chooser_label.modulate = Color(1.0, 0.92, 0.55, 1.0)
		_chooser_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		_chooser_label.pixel_size = 0.005
		_chooser_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_chooser_label.no_depth_test = true
		# Position centred at the same height as the standard E prompt
		# (since the E + Travel labels are hidden in CHOOSING).
		_chooser_label.position = Vector3(0, 0.0, 0)
		_chooser_label.visible = false
		_prompt_root.add_child(_chooser_label)


func _build_doors() -> void:
	# Eight panels — two per cardinal face. Each panel slides outward
	# along its face's tangent axis from the closed centre point. Width =
	# half the chamfered side length minus a small visual gap; spans the
	# full elevator height. Built as MeshInstance3D children of this
	# handler (not the elevator core) so the slide tween owns the
	# transform without competing with the static core.
	var size: float = float(_c.ELEVATOR_RADIUS) * 2.0 * _c.GARDEN_PLOT_SIZE
	var chamfer: float = _c.ELEVATOR_CHAMFER
	var height: float = _c.WALL_HEIGHT * _c.ELEVATOR_HEIGHT_MULT
	var side_length: float = size - 2.0 * chamfer
	var panel_w: float = side_length * 0.5 - 0.04   # 0.04 m gap at the meeting line
	var face_pad: float = 0.02   # outboard offset so doors sit slightly proud of the core face

	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.40, 0.46, 0.55)
	door_mat.metallic = 0.6
	door_mat.roughness = 0.35
	door_mat.emission_enabled = true
	door_mat.emission = Color(0.30, 0.55, 0.85)
	door_mat.emission_energy_multiplier = 0.18

	var faces := [
		{"name": "N", "centre": Vector3(0, 0, -size * 0.5 - face_pad), "tangent": Vector3(1, 0, 0)},
		{"name": "S", "centre": Vector3(0, 0, size * 0.5 + face_pad), "tangent": Vector3(1, 0, 0)},
		{"name": "E", "centre": Vector3(size * 0.5 + face_pad, 0, 0), "tangent": Vector3(0, 0, 1)},
		{"name": "W", "centre": Vector3(-size * 0.5 - face_pad, 0, 0), "tangent": Vector3(0, 0, 1)},
	]
	for face in faces:
		for slot_sign in [-1, 1]:
			var pivot := Node3D.new()
			pivot.name = "Door_%s_%s" % [String(face.name), "L" if slot_sign < 0 else "R"]
			# Closed pose: panel centred at half its width from the meeting
			# line, on the +/- tangent side.
			var closed_offset: Vector3 = face.tangent * (panel_w * 0.5 * float(slot_sign))
			var base: Vector3 = face.centre + closed_offset
			pivot.position = base + Vector3(0, height * 0.5, 0)
			add_child(pivot)
			var panel := MeshInstance3D.new()
			panel.name = "Panel"
			var pm := BoxMesh.new()
			pm.size = Vector3(panel_w, height, _c.ELEVATOR_DOOR_THICKNESS)
			panel.mesh = pm
			panel.material_override = door_mat
			# Rotate so the box's local +X aligns with the face's tangent.
			# tangent = (1,0,0): no rotation needed. tangent = (0,0,1):
			# rotate Y by 90°.
			if abs(face.tangent.z) > 0.5:
				panel.rotation.y = PI * 0.5
			pivot.add_child(panel)
			_door_panels.append({
				"pivot": pivot,
				"base": base + Vector3(0, height * 0.5, 0),
				"tangent": face.tangent,
				"slot_sign": slot_sign,
			})


func _apply_door_offsets() -> void:
	# Slide each panel outward along its tangent by ELEVATOR_DOOR_OPEN
	# _OFFSET × _doors_open_t × slot_sign. Closed = at base; fully open =
	# offset by the full slide distance.
	var slide: float = _c.ELEVATOR_DOOR_OPEN_OFFSET * _doors_open_t
	for entry in _door_panels:
		var pivot: Node3D = entry.pivot
		var slide_offset: Vector3 = entry.tangent * (slide * float(entry.slot_sign))
		pivot.position = entry.base + slide_offset


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100   # above any HUD layer
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)
