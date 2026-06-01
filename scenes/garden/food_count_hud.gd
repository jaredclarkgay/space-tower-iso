extends Label

# Renders the player's backpack fill as "N / cap" in the Resources panel.
# Tints red on the slash text when at cap so the player can see at a glance
# why E presses are no-oping. Source of truth is GameState.backpack_count.

@onready var _gs: Node = get_node("/root/GameState")
@onready var _c: Node = get_node("/root/Constants")

const COLOR_NORMAL := Color(0.96, 0.78, 0.32, 1.0)
const COLOR_FULL := Color(1.00, 0.42, 0.36, 1.0)


func _process(_delta: float) -> void:
	var cap: int = _c.BACKPACK_CAPACITY
	var n: int = _gs.backpack_count
	text = "%d / %d" % [n, cap]
	modulate = COLOR_FULL if n >= cap else COLOR_NORMAL
