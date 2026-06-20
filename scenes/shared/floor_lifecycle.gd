extends RefCounted

# FloorLifecycle — the reusable blank-shell → lush lifecycle (floor_population_spec
# "OVERNIGHT SLICE": generalize the lifecycle). A floor DECLARES its content
# (palette, valid slots, alive threshold, provisional bloom) and this module owns
# the SHARED machinery every populatable floor uses identically:
#   - the lifecycle state (populated / alive / placed), read/written through
#     GameState.floor_state(id) so every floor mirrors the same shape;
#   - the place verb (find_slot → update_ghost → place);
#   - the grid-snapped placement ghost (translucent footprint preview);
#   - the ALIVE transition (threshold cross → flip alive → run the floor's bloom);
#   - telemetry — component_placed / floor_alive, each carrying the floor LEVEL so
#     agent/analysis/session_summary.py can read any floor's placement funnel.
#
# Mirrors how FloorChrome is shared and only content differs (rules/
# godot_shared_module_pattern.md): chrome is static geometry, so it's static funcs;
# the lifecycle is STATEFUL (the ghost mesh, the per-floor config) so it's an
# instanced helper a floor owns — `var _lifecycle := FloorLifecycle.new(self, ...)`.
#
# The floor stays the source of truth for its CONTENT via the config Callables:
#   is_populatable() -> bool          the floor's gate (e.g. Garden: powered & !alive)
#   snap_anchor(local_pos) -> Vector2i nearest grid cell (pure grid math)
#   is_valid_anchor(anchor) -> bool    is this a legal slot (in-grid, not taken)
#   slot_local_pos(anchor) -> Vector3  local-frame centre of the slot
#   spawn_component(anchor) -> void    build the component visuals + any activation
#   on_alive() -> void                 the provisional bloom (felt moment)
# and the scalar declarations: floor_id, level, threshold, component_type,
# ghost_span, ghost_color.

var _floor: Node3D
var _gs: Node
var _c: Node
var _tel: Node
var _cfg: Dictionary

var _ghost: MeshInstance3D = null


func _init(floor_node: Node3D, gs: Node, c: Node, tel: Node, cfg: Dictionary) -> void:
	_floor = floor_node
	_gs = gs
	_c = c
	_tel = tel
	_cfg = cfg


# "Is this floor alive" — the single call gates elsewhere read.
func is_alive() -> bool:
	return bool(_gs.floor_state(_cfg.floor_id).get("alive", false))


# Snap the player's position to the nearest grid cell and offer it as a slot if
# that cell is a legal anchor and within reach. Grid-snapped, never free-form: the
# slot IS a cell. Returns the anchor Vector2i, or null when no legal slot / not in
# the populating phase (so the caller is self-gating).
func find_slot(world_pos: Vector3, reach: float) -> Variant:
	if not bool(_cfg.is_populatable.call()):
		return null
	var local_pos: Vector3 = _floor.to_local(world_pos)
	var anchor: Vector2i = _cfg.snap_anchor.call(local_pos)
	if not bool(_cfg.is_valid_anchor.call(anchor)):
		return null
	var center: Vector3 = _cfg.slot_local_pos.call(anchor)
	if (center - local_pos).length() > reach:
		return null
	return anchor


# Show / move (or hide) the translucent placement ghost at a candidate anchor. The
# player drives this each frame with the slot it computed (null = hide). Lazily built.
func update_ghost(anchor_or_null) -> void:
	if anchor_or_null == null:
		if _ghost != null:
			_ghost.visible = false
		return
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		_ghost.name = "PlacementGhost"
		var gm := BoxMesh.new()
		var span: float = float(_cfg.ghost_span)
		gm.size = Vector3(span, 0.06, span)
		_ghost.mesh = gm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = _cfg.ghost_color
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost.material_override = gmat
		_floor.add_child(_ghost)
	var c: Vector3 = _cfg.slot_local_pos.call(anchor_or_null)
	_ghost.position = Vector3(c.x, 0.22, c.z)
	_ghost.visible = true


# Place a component anchored at grid `coord`. Public so a future Builder-Cody can
# call it exactly like the player. Spawns the component (content callback), advances
# the lifecycle, fires telemetry, and crosses into ALIVE if this is the threshold
# placement. Returns success.
func place(anchor: Vector2i) -> bool:
	if not bool(_cfg.is_populatable.call()):
		return false
	if not bool(_cfg.is_valid_anchor.call(anchor)):
		return false
	_cfg.spawn_component.call(anchor)
	var st: Dictionary = _gs.floor_state(_cfg.floor_id)
	st.populated = int(st.populated) + 1
	(st.placed as Array).append({"type": String(_cfg.component_type), "coord": anchor})
	if _tel:
		_tel.record("component_placed", {
			"floor": String(_cfg.floor_id),
			"level": int(_cfg.level),
			"type": String(_cfg.component_type),
			"placed": int(st.populated),
		})
	if int(st.populated) >= int(_cfg.threshold) and not bool(st.alive):
		_go_alive()
	return true


# Cross into ALIVE: flip the flag, emit the funnel-crossing telemetry (carrying the
# level), then run the floor's own provisional bloom. One-shot — place() guards it.
func _go_alive() -> void:
	var st: Dictionary = _gs.floor_state(_cfg.floor_id)
	st.alive = true
	if _tel:
		_tel.record("floor_alive", {
			"floor": String(_cfg.floor_id),
			"level": int(_cfg.level),
			"populated": int(st.populated),
		})
	_cfg.on_alive.call()
