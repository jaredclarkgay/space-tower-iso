extends Node

# GameDirector — the narrative-arc sequencer (the 7-step build spine).
# Owns WHERE in the arc the game is and the rules that advance it.
# GameState stays pure data ("what is true in the world"); GameDirector is
# "what should happen next and when". Reads + mirrors GameState; never stores a
# parallel copy of world state. Consumers react to phase_changed(phase):
# tower_hud (objective line), floor controllers, tower_controller (environment).
#
# TWO AXES — keep them separate:
#   - Phase (this enum) is the LINEAR narrative spine: it advances forward,
#     pass-through, one beat at a time, and never loops in real play.
#   - Time-of-day is a CYCLIC, always-on layer that lives ELSEWHERE (the clock),
#     not here. TEMPORAL is only the linear MOMENT the clock switches on; the
#     day/night cycle is NOT a phase value and must not be modelled as one.

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

# Readable name for a phase value (debug/logging).
func phase_name(p: int) -> String:
	var names: Array = Phase.keys()
	return String(names[p]) if p >= 0 and p < names.size() else "PHASE_%d" % p


# DEBUG/sequencing helper: step to the next phase. The modulo WRAP is debug-only
# (so the dev key can cycle the whole enum) — real play is a forward pass-through
# and never loops. Phase.size() keeps the wrap correct if the enum gains a beat.
# The mid/late phases (BUILD_STRUCTURE..TEMPORAL) are no-op transitions for now
# (no gates yet).
func advance_phase() -> void:
	set_phase((current_phase + 1) % Phase.size())


func _mirror() -> void:
	_gs.phase = current_phase
