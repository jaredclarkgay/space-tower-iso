extends Node3D

# Floor 4 — RESIDENTIAL. Blank for now: no housing, no residents — just the
# building shell wired into the tower like every other floor (slab with the
# central elevator shaft cut through it, perimeter walls + glass, the extension
# grid, the elevator/spine core, the lit utility risers, and the four corner
# vacuum tubes). A future worldbuilding phase fills it with units + residents.
#
# Built in LOCAL space (slab top at local y=0); the tower offsets the node to
# its stacked height. Mirrors the chrome any solid floor uses — see
# scenes/shared/floor_chrome.gd and rules/stacked_tower_invariants.md (#4:
# shared builders are the unit of cross-floor consistency).

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const FLOOR_COLOR := Color(0.34, 0.30, 0.28)   # warm residential concrete

var _elevator_data: Dictionary = {}


func _ready() -> void:
	# Slab with the central shaft cut through it (same ±2 m hole as the Garden /
	# Arboretum), so the elevator car travels through and stops here (it serves
	# this floor) and the spine reads continuous. SlabBody name → the tower gates
	# its collision per the current floor like every solid floor.
	var shaft_half: float = float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE)
	FloorChrome.build_slab(self, _c, FLOOR_COLOR, shaft_half)
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, _elevator_data)
	# Corner vacuum tubes — a mid-stack floor, so they stay open and tile up into
	# the Sky Lounge's (not top-sealed).
	VacuumTube.build_corner_tubes(self, _c, false)
