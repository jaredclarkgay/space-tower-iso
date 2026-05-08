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
@export var player_path: NodePath
var _player: Node3D

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
	# If we just travelled, run the fade-in. Otherwise skip — fresh F5
	# into the project shouldn't open with a black-to-clear ramp.
	if _gs.get("in_transit"):
		_fade_rect.color.a = 1.0
		_fade_rect.visible = true
		var tween := create_tween()
		tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
		tween.tween_callback(func(): _fade_rect.visible = false)
		_gs.set("in_transit", false)


func _process(_delta: float) -> void:
	if _player == null:
		return
	# Player position vs elevator centre (this Node3D is parented at floor
	# root; the elevator core is at world origin per FloorChrome).
	var pos: Vector3 = _player.global_position
	var d: float = Vector2(pos.x, pos.z).length()
	var in_range: bool = d <= INTERACT_RADIUS
	_prompt_root.visible = in_range
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
	_prompt_label.text = "Travel to %s" % target_label
	_prompt_label.font_size = 56
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_prompt_label.pixel_size = 0.005
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, 0.0, 0)
	_prompt_root.add_child(_prompt_label)


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
