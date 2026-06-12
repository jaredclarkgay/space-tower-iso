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

# Emitted whenever the Director issues a directive (see §"Director→mouth channel"
# below). Passive mouths (the HUD objective line) listen here; the spoken delivery
# is routed to a single mouth by issue_directive().
signal directive_issued(directive: Dictionary)

var current_phase: Phase = Phase.EMPTY_LOT

@onready var _gs: Node = get_node("/root/GameState")

# --- Director→mouth channel (vision.md §1-2) ------------------------------
# The Director is the brain: it owns WHAT the player needs next. It does not speak
# in its own voice — it speaks through *mouths*. A directive is mouth-agnostic data
# (lines + objective + a telemetry id); the Director decides which to issue and
# when, and a routable channel picks a mouth to render it. Cody is the primary
# mouth; the HUD is a passive objective/toast mouth. New mouths (environment, a PA,
# another character) register without rewiring the spine.

# The directive library — the Director owns the CONTENT of direction; mouths only
# render it. (Keep the player-facing words here, not buried in a speaker.)
const DIRECTIVES := {
	"power_utilities": {
		"id": "power_utilities",
		"speaker": "cody",
		"lines": [
			"Welcome. Status: Garden unpowered. Nothing takes root.",
			"Go down to Utility. Bring all six sources online.",
			"I'll know the moment you do.",
		],
		"objective": "Go to the Utility floor — bring all six sources online.",
		"telemetry_beat": "director_beat",
	},
	# Gate-lift payoff (floor_population_spec Step 3): power's on, so the Garden can
	# now be BUILT OUT. This invites PLACEMENT, not planting — planting opens later,
	# when the floor crosses ALIVE. Closes the ~15s "now what?" gap after the gate.
	"garden_live": {
		"id": "garden_live",
		"speaker": "cody",
		"lines": [
			"Power confirmed — all six. The Garden's live.",
			"Now let's build it out — drop your first planter bed.",
		],
		"objective": "Place planter beds to bring the Garden alive.",
		"telemetry_beat": "director_beat",
	},
	# Threshold crossed (floor_population_spec Step 3): the Garden bloomed. Cody
	# acknowledges the moment and hands off to the crop loop — planting is now open.
	"garden_alive": {
		"id": "garden_alive",
		"speaker": "cody",
		"lines": [
			"There it is — that's a garden now.",
			"Go ahead and plant.",
		],
		"objective": "Plant your first crop.",
		"telemetry_beat": "director_beat",
	},
	# P pressed before the floor can take a plant — a quick toast naming the reason.
	# Two reasons depending on how far the player is: unpowered (gate not lifted) vs.
	# powered-but-barren (no bed placed yet). The site picks which id to issue.
	"plant_locked": {
		"id": "plant_locked",
		"speaker": "hud",        # a quick toast, not a full Cody beat
		"transient": true,
		"lines": ["Unpowered. Roots need the grid. Utility floor."],
		"telemetry_beat": "director_beat",
	},
	"plant_locked_barren": {
		"id": "plant_locked_barren",
		"speaker": "hud",
		"transient": true,
		"lines": ["No soil yet. Place planter beds to wake the Garden."],
		"telemetry_beat": "director_beat",
	},
}

# Registered mouths: nodes with a `mouth_id` and `deliver_directive(d) -> bool`,
# sorted highest-priority first. Cody registers at high priority; the HUD low.
var _mouths: Array = []
var active_directive: Dictionary = {}


func register_mouth(node: Object, priority: int = 0) -> void:
	for m in _mouths:
		if m.node == node:
			return
	_mouths.append({"node": node, "priority": priority})
	_mouths.sort_custom(func(a, b): return int(a.priority) > int(b.priority))


func unregister_mouth(node: Object) -> void:
	_mouths = _mouths.filter(func(m): return m.node != node)


# Issue a directive (by id, or a literal dict). The Director decides WHAT; this
# routes the SPOKEN delivery to a mouth (the directive's named speaker, else the
# highest-priority one that accepts it) and notifies every mouth via the signal so
# passive ones (the HUD objective) can mirror it regardless of who speaks.
func issue_directive(directive_or_id) -> void:
	var d: Dictionary = directive_or_id if directive_or_id is Dictionary \
		else DIRECTIVES.get(directive_or_id, {})
	if d.is_empty():
		push_warning("issue_directive: unknown directive '%s'" % str(directive_or_id))
		return
	if not bool(d.get("transient", false)):
		active_directive = d
	directive_issued.emit(d)
	var tel: Node = get_node_or_null("/root/Telemetry")
	if tel and d.has("telemetry_beat"):
		tel.call("record", String(d.telemetry_beat), {"id": d.get("id", "")})
	var want: String = String(d.get("speaker", ""))
	for m in _mouths:
		var node: Object = m.node
		if not is_instance_valid(node):
			continue
		if want != "" and String(node.get("mouth_id")) != want:
			continue
		if node.has_method("deliver_directive") and bool(node.call("deliver_directive", d)):
			return


# Called when the sixth Utility source goes active (opening_sequence_spec Step 5).
# Lifts the interiors gate — the felt payoff — which now unlocks PLACEMENT (the
# floor-population mechanic), and issues Cody's "let's build it out" invite.
# One-shot; safe to call repeatedly.
func complete_utilities() -> void:
	if bool(_gs.interiors_unlocked):
		return
	_gs.interiors_unlocked = true
	var tel: Node = get_node_or_null("/root/Telemetry")
	if tel:
		tel.call("record", "utilities_complete", {})
		tel.call("record", "gate_lifted", {})
	issue_directive("garden_live")


# Called by the Garden when population crosses the ALIVE threshold (the bloom).
# Cody acknowledges it through the mouth channel — the same routing as the opener,
# not bespoke dialogue. One-shot; the floor guards on garden.alive so this fires once.
func confirm_garden_alive() -> void:
	issue_directive("garden_alive")

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
