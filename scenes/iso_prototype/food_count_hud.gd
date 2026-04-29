extends Label

# Polls GameState.food_count each frame and renders it as
# "Food: N" in the top-right HUD. Trivial; lives here so the
# label stays declarative in iso_prototype.tscn.

@onready var _gs: Node = get_node("/root/GameState")


func _process(_delta: float) -> void:
	# Just the number — the "Food" label is a sibling Label in the row.
	text = "%d" % _gs.food_count
