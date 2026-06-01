extends Button

# Schematics button hidden by default. Polls GameState.plants_harvested
# each frame; once the player crosses UNLOCK_THRESHOLD it (and its
# divider) reveals with a bouncy "moment" — alpha 0 → 1 plus scale
# 0.5 → 1.0 with TRANS_BACK / EASE_OUT for an overshoot.
#
# The unlock check runs only until _shown flips true, then _process is
# disabled — no per-frame cost after the reveal.

@onready var _gs: Node = get_node("/root/GameState")

@export var divider_path: NodePath
@export var unlock_threshold: int = 10

var _divider: Control
var _shown: bool = false


func _ready() -> void:
	visible = false
	if divider_path:
		_divider = get_node(divider_path)
		_divider.visible = false


func _process(_delta: float) -> void:
	if _shown:
		set_process(false)
		return
	if _gs.plants_harvested >= unlock_threshold:
		_shown = true
		_reveal()
		set_process(false)


func _reveal() -> void:
	# Make divider appear softly first, then bounce the button in.
	if _divider:
		_divider.visible = true
		_divider.modulate.a = 0.0
		create_tween().tween_property(_divider, "modulate:a", 1.0, 0.4)

	visible = true
	# Wait a frame so layout finishes computing size before we read it
	# for the pivot offset.
	await get_tree().process_frame
	pivot_offset = size * 0.5
	modulate.a = 0.0
	scale = Vector2(0.5, 0.5)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
