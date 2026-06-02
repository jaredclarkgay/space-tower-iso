extends Node

# GameDirector — the narrative-arc sequencer (the 7-step build spine).
# Owns WHERE in the arc the game is and the rules that advance it.
# GameState stays pure data ("what is true in the world"); GameDirector is
# "what should happen next and when". Reads + mirrors GameState; never stores a
# parallel copy of world state. Consumers react to phase_changed(phase):
# tower_hud (objective line), floor controllers, tower_controller (environment).

enum Phase {
	EMPTY_LOT,        # new exterior opening beat (built in step 2)
	HIRE_PARTNER,     # new exterior beat: pick 1 of 5 helper NAMES (step 3)
	BUILD_STRUCTURE,  # construct-from-empty — deferred mechanic; stub transition
	BUILD_INTERIORS,
	ACTIVATE_FLOORS,
	SHARE,
	TEMPORAL,
}

signal phase_changed(phase: Phase)

var current_phase: Phase = Phase.EMPTY_LOT

@onready var _gs: Node = get_node("/root/GameState")

func _ready() -> void:
	_mirror()   # publish the initial phase into GameState for pollers

# Advance/set the phase, mirror into GameState, and notify consumers. The
# transition GATES (auto-advance rules reading GameState) land in later steps;
# this is the manual entry point the hire beat + debug affordance call.
func set_phase(p: Phase) -> void:
	if p == current_phase:
		return
	current_phase = p
	_mirror()
	phase_changed.emit(current_phase)

func _mirror() -> void:
	_gs.phase = current_phase
