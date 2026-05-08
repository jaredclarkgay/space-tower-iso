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
var _player: Node3D

# Where to place the player after arrival. Just south of the central
# elevator core so they exit through the "south door" facing the camera.
const ARRIVAL_POSITION := Vector3(0, 0.2, 3.0)

# Door panels — 8 total (2 per cardinal face). Each pair slides apart
# along the face's tangent axis when the player is in interaction range.
# Built procedurally from the elevator's geometry constants in _ready.
var _door_panels: Array = []   # list of {pivot: Node3D, base: Vector3, tangent: Vector3, slot_sign: int}
var _doors_open_t := 0.0       # 0 closed, 1 fully open

# Prompt above the elevator. Built once; visibility + position lerp.
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D

# Fade overlay — full-screen ColorRect on a CanvasLayer, alpha-tweened.
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect

const INTERACT_RADIUS := 2.6   # slightly outside the 4×4 elevator core
const FADE_DURATION := 0.4


func _ready() -> void:
	if player_path:
		_player = get_node(player_path)
	_build_prompt()
	_build_fade()
	_build_doors()
	# If we just travelled, run the fade-in and reposition the player at
	# the south door of the elevator. Otherwise skip — a fresh F5 into
	# the project shouldn't open on a black-to-clear ramp.
	if _gs.get("in_transit"):
		if _player:
			_player.global_position = ARRIVAL_POSITION
			if _player.has_method("set_facing_yaw"):
				_player.set_facing_yaw(deg_to_rad(_c.CAMERA_YAW_DEG_INITIAL))
		_fade_rect.color.a = 1.0
		_fade_rect.visible = true
		var tween := create_tween()
		tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
		tween.tween_callback(func(): _fade_rect.visible = false)
		_gs.set("in_transit", false)


func _process(delta: float) -> void:
	if _player == null:
		return
	var pos: Vector3 = _player.global_position
	var d: float = Vector2(pos.x, pos.z).length()
	var in_range: bool = d <= INTERACT_RADIUS
	_prompt_root.visible = in_range
	# Doors open as the player approaches; close when they walk away.
	# The interpolation rate maps 0→1 over ELEVATOR_DOOR_OPEN_DURATION.
	var target: float = 1.0 if in_range else 0.0
	var rate: float = 1.0 / _c.ELEVATOR_DOOR_OPEN_DURATION
	_doors_open_t = move_toward(_doors_open_t, target, rate * delta)
	_apply_door_offsets()
	if in_range and Input.is_action_just_pressed(&"interact"):
		_travel()


func _travel() -> void:
	if target_scene_path == "":
		return
	if not _gs.has_meta("_elevator_traveling"):
		_gs.set_meta("_elevator_traveling", false)
	if _gs.get_meta("_elevator_traveling", false):
		return
	_gs.set_meta("_elevator_traveling", true)
	_gs.set("in_transit", true)
	_fade_rect.visible = true
	_fade_rect.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(_perform_swap)


func _perform_swap() -> void:
	# `change_scene_to_file` is deferred — Godot tears down the current
	# tree at end of frame. Clear the gate flag last so a re-entry can
	# tween in cleanly.
	_gs.set_meta("_elevator_traveling", false)
	get_tree().change_scene_to_file(target_scene_path)


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
	var arrow := "↑" if direction == "up" else "↓"
	_prompt_label.text = "%s  Travel to %s" % [arrow, target_label]
	_prompt_label.font_size = 56
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_prompt_label.pixel_size = 0.005
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, 0.0, 0)
	_prompt_root.add_child(_prompt_label)


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
