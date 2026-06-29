extends RefCounted

# Per-component floor assembly. A floor is built as an ORDERED SEQUENCE of
# structural pieces — each its own named sub-node with its own parametric "grow"
# animation — instead of the whole floor node rising as one block.
#
# Order (core-first; see CLAUDE / the design sketch):
#   slab -> core -> risers -> walls -> tubes -> [content, separate] -> grid
# Logic: you need a deck to stand on (slab); the structural spine threads up
# (core); its veins run up the spine (risers); the shell encloses it (walls); the
# logistics network connects (tubes); the "could-extend" blueprint is a last,
# subtle flourish (grid).
#
# Mirrors scenes/shared/floor_lifecycle.gd: an INSTANCED helper a floor owns,
# fed a config dict. Most floors pass only {floor_color, shaft_half}; floors with
# bespoke walls (Garden doored, Sky Lounge glass) pass a `walls_build` Callable.
# Loaded via preload, NOT class_name (F-010):
#   const FloorConstruction = preload("res://scenes/shared/floor_construction.gd")
#
# THREE HORIZONS on one primitive (build_step):
#   1. now      — play_sequence(): the successive animations auto-run.
#   2. later    — build_next_animated(): the player triggers each step.
#   3. eventual — Cody calls build_step for a step he's been trained on.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

var _floor: Node3D
var _c: Node
var _gs: Node
var _tel: Node
var _steps: Array = []                 # [{id, grow, build:Callable}]
var _groups: Dictionary = {}           # id -> Node3D (the piece's sub-node)
var _done: Dictionary = {}             # id -> true
var _elevator_data: Dictionary = {}    # produced by the core step, read by risers


func _init(floor: Node3D, c: Node, gs: Node, tel: Node, cfg: Dictionary) -> void:
	_floor = floor
	_c = c
	_gs = gs
	_tel = tel
	_steps = _build_manifest(cfg)


# The structural manifest. cfg keys:
#   floor_color : Color   — the deck colour
#   shaft_half  : float   — central elevator-shaft half-extent (0 = solid slab)
#   tubes_top   : bool    — seal the vacuum-tube caps (top floor only)
#   order       : Array[String] — which steps, in order (default the standard six).
#                 Drop a step a floor lacks (e.g. Roof has no "walls"; Utility has
#                 no passive "risers" — its active spine is content).
#   <id>_build  : Callable(group) — override a step's builder for bespoke geometry
#                 (e.g. Garden's doored walls, Sky Lounge's glass walls). The id is
#                 one of slab/core/risers/walls/tubes/grid.
const _DEFAULT_ORDER := ["slab", "core", "risers", "walls", "tubes", "grid"]
const _GROW_KIND := {
	"slab": "tile_sweep", "core": "grow_up", "risers": "grow_up",
	"walls": "grow_up", "tubes": "grow_up", "grid": "grid_fade",
}


func _build_manifest(cfg: Dictionary) -> Array:
	var floor_color: Color = cfg.get("floor_color", Color(0.18, 0.18, 0.20))
	var shaft_half: float = float(cfg.get("shaft_half", 0.0))
	var tubes_top: bool = bool(cfg.get("tubes_top", false))
	# The default builder for each step (overridable via cfg["<id>_build"]).
	var defaults := {
		"slab": func(g: Node3D) -> void: FloorChrome.build_slab_tiled(g, _c, floor_color, shaft_half),
		"core": func(g: Node3D) -> void: _elevator_data = FloorChrome.build_elevator_core(g, _c),
		"risers": func(g: Node3D) -> void: FloorChrome.build_passive_spine_pipes(g, _c, _gs, _elevator_data),
		"walls": func(g: Node3D) -> void: FloorChrome.build_walls(g, _c),
		"tubes": func(g: Node3D) -> void: VacuumTube.build_corner_tubes(g, _c, tubes_top),
		"grid": func(g: Node3D) -> void: FloorChrome.build_extension_grid(g, _c),
	}
	var order: Array = cfg.get("order", _DEFAULT_ORDER)
	var steps: Array = []
	for id in order:
		var build: Callable = cfg.get(String(id) + "_build", defaults.get(id, Callable()))
		if not build.is_valid():
			continue
		steps.append({"id": String(id), "grow": String(_GROW_KIND.get(id, "grow_up")), "build": build})
	return steps


# --- Build paths -----------------------------------------------------------

# Build the whole floor immediately, no animation (dev boot, jump-to-floor, any
# non-construction entry). The default for a floor that isn't being raised live.
func build_all_instant() -> void:
	for step in _steps:
		var g: Node3D = _ensure_group(String(step.id))
		(step.build as Callable).call(g)
		_done[String(step.id)] = true


# Async: play the full successive-animation sequence (horizon 1). Each piece is
# built then grown in order, with a beat between pieces.
func play_sequence() -> void:
	for step in _steps:
		await build_step_animated(String(step.id))
		if is_instance_valid(_floor):
			await _floor.get_tree().create_timer(float(_c.CONSTRUCT_STEP_GAP)).timeout


# Build + grow a single step (the shared primitive for all three horizons). The
# geometry is built only if the group is empty (a floor that already
# build_all_instant'd just RE-ANIMATES its existing pieces — no rebuild, so the
# tower's cached slab/grid node refs stay valid). Then the piece grows into place.
func build_step_animated(id: String) -> void:
	var step: Dictionary = _step_by_id(id)
	if step.is_empty():
		return
	var g: Node3D = _ensure_group(id)
	if g.get_child_count() == 0:
		(step.build as Callable).call(g)
	await _grow(String(step.grow), g)
	_done[id] = true
	if _tel:
		_tel.record("floor_piece_built", {"piece": id})


# Build the next not-yet-built piece (horizon 2 — player/Cody triggered).
func build_next_animated() -> void:
	var id: String = next_pending()
	if id != "":
		await build_step_animated(id)


# Collapse every (already-built) piece to its pre-grow start state, without
# freeing anything. Call before a floor becomes visible in the build flow so it
# doesn't flash full for a frame before play_sequence animates it in.
func prime_collapsed() -> void:
	for step in _steps:
		var g: Node3D = _groups.get(String(step.id))
		if is_instance_valid(g):
			_set_collapsed(String(step.grow), g)
		_done.erase(String(step.id))


func reset() -> void:
	for id in _groups:
		var g = _groups[id]
		if is_instance_valid(g):
			g.queue_free()
	_groups.clear()
	_done.clear()
	_elevator_data = {}


# The elevator-core geometry the "core" step produced (chamfer corners etc.).
# Floors that build active content onto the core (e.g. Utility's live spine pipes)
# read this after build_all_instant().
func elevator_data() -> Dictionary:
	return _elevator_data


func is_complete() -> bool:
	return _done.size() >= _steps.size()


# Approximate wall-clock length of play_sequence() — used by the driver to time
# the hand-off after the top floor finishes assembling.
func approx_duration() -> float:
	var per: float = float(_c.CONSTRUCT_STEP_DUR) + float(_c.CONSTRUCT_STEP_GAP)
	return float(_steps.size()) * per + float(_c.CONSTRUCT_SLAB_SWEEP_DUR)


func next_pending() -> String:
	for step in _steps:
		if not _done.has(String(step.id)):
			return String(step.id)
	return ""


func step_ids() -> Array:
	var out: Array = []
	for step in _steps:
		out.append(String(step.id))
	return out


# --- Internals -------------------------------------------------------------

func _step_by_id(id: String) -> Dictionary:
	for step in _steps:
		if String(step.id) == id:
			return step
	return {}


func _ensure_group(id: String) -> Node3D:
	if _groups.has(id) and is_instance_valid(_groups[id]):
		return _groups[id]
	var g := Node3D.new()
	g.name = "Build_" + id.capitalize()
	_floor.add_child(g)
	_groups[id] = g
	return g


# Set a piece's collapsed pre-grow start state (no animation, no rebuild).
func _set_collapsed(kind: String, g: Node3D) -> void:
	match kind:
		"grow_up":
			g.scale.y = float(_c.CONSTRUCT_GROW_EPSILON)
		"tile_sweep":
			var tiles: Array = []
			_collect_named(g, "Tile_", tiles)
			var cs: float = float(_c.CONSTRUCT_TILE_COLLAPSE)
			for t in tiles:
				t.scale = Vector3(cs, cs, cs)
		"grid_fade":
			var meshes: Array = []
			_collect_named(g, "GridExt", meshes)
			for m in meshes:
				var dm: StandardMaterial3D = _grid_mat(m)
				if dm:
					dm.albedo_color.a = 0.0


# Parametric grow dispatch: collapse to the start state, then animate to rest.
# Idempotent — safe whether or not prime_collapsed already ran.
func _grow(kind: String, g: Node3D) -> void:
	if not is_instance_valid(_floor):
		return
	_set_collapsed(kind, g)
	match kind:
		"grow_up":
			await _grow_up(g)
		"tile_sweep":
			await _grow_tile_sweep(g)
		"grid_fade":
			await _grow_grid_fade(g)
		_:
			pass


# Vertical extrude: the piece's group rises out of the slab (scale.y about the
# floor origin, where the group sits). Used by core / risers / walls / tubes —
# all anchored at the deck and growing upward.
func _grow_up(g: Node3D) -> void:
	var tw := _floor.create_tween()
	tw.tween_property(g, "scale:y", 1.0, float(_c.CONSTRUCT_STEP_DUR)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished


# Deck print: the slab tiles pop in, staggered by distance from the shaft/centre,
# so the floor reads as printing outward from the core.
func _grow_tile_sweep(g: Node3D) -> void:
	var tiles: Array = []
	_collect_named(g, "Tile_", tiles)
	var max_d: float = 0.001
	for t in tiles:
		max_d = maxf(max_d, Vector2(t.position.x, t.position.z).length())
	var sweep: float = float(_c.CONSTRUCT_SLAB_SWEEP_DUR)
	var pop: float = float(_c.CONSTRUCT_SLAB_TILE_POP)
	for t in tiles:
		var d: float = Vector2(t.position.x, t.position.z).length()
		var delay: float = (d / max_d) * sweep
		var tw := _floor.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(t, "scale", Vector3.ONE, pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _floor.get_tree().create_timer(sweep + pop + 0.02).timeout


# Blueprint flourish: the extension grid eases its alpha in — slow + subtle, the
# last grace note that the floor "could extend outward someday".
func _grow_grid_fade(g: Node3D) -> void:
	var meshes: Array = []
	_collect_named(g, "GridExt", meshes)
	var dur: float = float(_c.CONSTRUCT_GRID_FADE_DUR)
	for m in meshes:
		var dm: StandardMaterial3D = _grid_mat(m)
		if dm == null:
			continue
		var orig_a: float = dm.get_meta("orig_a", dm.albedo_color.a)
		dm.albedo_color.a = 0.0
		var tw := _floor.create_tween()
		tw.tween_property(dm, "albedo_color:a", orig_a, dur).set_ease(Tween.EASE_OUT)
	await _floor.get_tree().create_timer(dur).timeout


# A per-mesh duplicated grid material whose original alpha is stashed in meta, so
# repeated collapse/grow cycles fade to the right target instead of to 0.
func _grid_mat(m: MeshInstance3D) -> StandardMaterial3D:
	var mat: Material = m.material_override
	if mat == null:
		return null
	if not (mat is StandardMaterial3D) or not mat.has_meta("orig_a"):
		var dm: StandardMaterial3D = mat.duplicate()
		dm.set_meta("orig_a", dm.albedo_color.a)
		m.material_override = dm
		return dm
	return mat as StandardMaterial3D


func _collect_named(node: Node, prefix: String, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with(prefix):
			out.append(child)
		_collect_named(child, prefix, out)
