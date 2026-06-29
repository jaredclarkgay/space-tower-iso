extends RefCounted

# Shared "floor chrome" builders — the room frame any floor uses so they all
# read as part of the same building: slab, perimeter walls (low base + posts
# + translucent glass + top trim), the extension grid blueprint past the
# walls, and the central elevator/spine core.
#
# Used by utility today; the garden's iso_floor.gd will migrate over in a
# follow-up refactor (it currently has its own inline copies of these
# functions). All builders take a parent Node3D + Constants autoload ref so
# they don't need any scene-specific state.
#
# Loaded via preload, NOT class_name, to dodge the headless-import class
# registration issue (F-010): callers do
#   const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
#   FloorChrome.build_walls(self, _c)


# Builds the floor slab (StaticBody3D with collision) at y = 0. Mesh top
# face sits at y = 0 so the player walks on it. Slab thickness extends
# downward.
# `shaft_half` > 0 cuts a central square hole (half-extent `shaft_half`) for the
# elevator to travel through; the slab is then built as 4 rectangular pieces
# around it. 0 = solid slab (one box), the default.
static func build_slab(parent: Node3D, c: Node, color: Color = Color(0.18, 0.18, 0.20),
		shaft_half: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = "SlabBody"
	# Layer 2 = "regular floor". The tower (tower_controller.gd) toggles this
	# body's collision_layer per the player's current floor: floors ABOVE you
	# are switched off so a jump arcs straight up through the ceiling and falls
	# back to the SAME floor (you never land on the floor above — vertical
	# travel is stairs + elevator). The Canopy slab is built separately on
	# layer 1 and is never toggled, so it stays a solid glass ceiling. See F-023.
	parent.add_child(body)
	var mat := _flat_material(color)
	var thick: float = c.FLOOR_3D_SLAB_THICKNESS
	var full: float = c.FLOOR_3D_SIZE
	var half: float = full * 0.5
	var y: float = -thick * 0.5

	if shaft_half <= 0.0:
		_add_slab_piece(body, mat, Vector3(full, thick, full), Vector3(0, y, 0))
		return

	var s: float = shaft_half
	var strip: float = half - s          # depth/width of each piece beyond the hole
	# North + south strips run the full x width.
	_add_slab_piece(body, mat, Vector3(full, thick, strip), Vector3(0, y, -(s + strip * 0.5)))
	_add_slab_piece(body, mat, Vector3(full, thick, strip), Vector3(0, y, s + strip * 0.5))
	# East + west strips fill only the hole's z band.
	_add_slab_piece(body, mat, Vector3(strip, thick, 2.0 * s), Vector3(-(s + strip * 0.5), y, 0))
	_add_slab_piece(body, mat, Vector3(strip, thick, 2.0 * s), Vector3(s + strip * 0.5, y, 0))

	# Invisible "shaft grate" across the opening so the player can't fall down the
	# open shaft when the car is parked elsewhere — they stand here and call/ride
	# the elevator instead. Collision-ONLY (no mesh), so it never blocks the view
	# of the cabin moving in the shaft. It's a child of SlabBody, so the tower
	# gates it exactly like the slab (off for floors above → a jump still passes up
	# through the shaft, and a ride owns the player's transform so it passes too).
	var grate := CollisionShape3D.new()
	grate.name = "ShaftGrate"
	var grate_shape := BoxShape3D.new()
	grate_shape.size = Vector3(2.0 * s, thick, 2.0 * s)
	grate.shape = grate_shape
	grate.position = Vector3(0, y, 0)
	body.add_child(grate)


# One shaft-wall panel on a cardinal face. `pos_xz` is the panel centre on the XZ
# plane (y ignored); width runs along `tangent`, thickness along `normal`.
static func _add_shaft_panel(body: StaticBody3D, mat: Material, pos_xz: Vector3,
		tangent: Vector3, normal: Vector3, width: float, thickness: float,
		y_center: float, y_height: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "ShaftWall"
	var box := BoxMesh.new()
	box.size = Vector3(
		absf(tangent.x) * width + absf(normal.x) * thickness,
		y_height,
		absf(tangent.z) * width + absf(normal.z) * thickness,
	)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = Vector3(pos_xz.x, y_center, pos_xz.z)
	body.add_child(mesh)


static func _add_slab_piece(body: StaticBody3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	body.add_child(mesh)
	_add_slab_collision(body, size, pos)


# Collision-only slab piece (no mesh) — used by build_slab_tiled, where the visual
# is a grid of separate tiles but the physics stays a few solid boxes.
static func _add_slab_collision(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = size
	col.shape = col_shape
	col.position = pos
	body.add_child(col)


# Like build_slab, but the VISUAL deck is a grid of individual tiles (a "Tiles"
# node of small box meshes) so the construction sequence can print it tile-by-tile
# (a radial sweep out from the shaft). Collision stays the same few solid boxes as
# build_slab — strips around the shaft, or one box when solid — plus the shaft
# grate. Tiles whose centre falls inside the shaft square are skipped.
static func build_slab_tiled(parent: Node3D, c: Node, color: Color = Color(0.18, 0.18, 0.20),
		shaft_half: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = "SlabBody"
	parent.add_child(body)
	var thick: float = c.FLOOR_3D_SLAB_THICKNESS
	var full: float = c.FLOOR_3D_SIZE
	var half: float = full * 0.5
	var y: float = -thick * 0.5
	var s: float = shaft_half

	# --- Collision (no mesh) — identical footprint to build_slab.
	if s <= 0.0:
		_add_slab_collision(body, Vector3(full, thick, full), Vector3(0, y, 0))
	else:
		var strip: float = half - s
		_add_slab_collision(body, Vector3(full, thick, strip), Vector3(0, y, -(s + strip * 0.5)))
		_add_slab_collision(body, Vector3(full, thick, strip), Vector3(0, y, s + strip * 0.5))
		_add_slab_collision(body, Vector3(strip, thick, 2.0 * s), Vector3(-(s + strip * 0.5), y, 0))
		_add_slab_collision(body, Vector3(strip, thick, 2.0 * s), Vector3(s + strip * 0.5, y, 0))
		# Invisible shaft grate (see build_slab) so the open shaft can't be fallen down.
		var grate := CollisionShape3D.new()
		grate.name = "ShaftGrate"
		var grate_shape := BoxShape3D.new()
		grate_shape.size = Vector3(2.0 * s, thick, 2.0 * s)
		grate.shape = grate_shape
		grate.position = Vector3(0, y, 0)
		body.add_child(grate)

	# --- Visual tiles, gridded over the footprint minus the shaft.
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	body.add_child(tiles)
	var mat := _flat_material(color)
	var tile: float = float(c.CONSTRUCT_SLAB_TILE)
	var n: int = int(ceil(full / tile))
	var step: float = full / float(n)
	var gap: float = 0.06                     # thin seam so the grid reads
	for ix in range(n):
		for iz in range(n):
			var cx: float = -half + (float(ix) + 0.5) * step
			var cz: float = -half + (float(iz) + 0.5) * step
			if s > 0.0 and absf(cx) < s and absf(cz) < s:
				continue                       # skip the shaft hole
			var t := MeshInstance3D.new()
			t.name = "Tile_%d_%d" % [ix, iz]
			var tm := BoxMesh.new()
			tm.size = Vector3(step - gap, thick, step - gap)
			t.mesh = tm
			t.material_override = mat
			t.position = Vector3(cx, y, cz)
			tiles.add_child(t)


# Builds 4 perimeter walls. Each wall: low solid base + collision spanning
# full height + vertical posts at WALL_POST_SPACING + thin top trim +
# translucent glass spanning the gap between base and trim.
# `seal` raises the (invisible) collision to WALL_SEAL_HEIGHT so the player can't
# clear the wall with a charged jump. Leave it off for the basement (underground,
# no fall-out) and grade floors with doorways (the Garden), where it would bleed
# into the doorway opening above. Doored walls never seal (they have an opening).
static func build_walls(parent: Node3D, c: Node, doorways: bool = false, seal: bool = true, seal_height: float = 0.0) -> void:
	var half: float = c.FLOOR_3D_SIZE * 0.5
	for side in ["+x", "-x", "+z", "-z"]:
		if doorways:
			_build_one_wall_doored(parent, c, side, half)
		else:
			_build_one_wall(parent, c, side, half, seal, seal_height)


# One wall piece (mesh, collision, or both). `a` is the centre offset ALONG the
# wall; `thk` runs perpendicular (into the room). Mirrors the cardinal-axis math
# the solid wall uses, so doored + solid walls line up exactly.
static func _wall_piece(body: StaticBody3D, mat: Material, along_x: bool, perp: float,
		a: float, along_len: float, y_center: float, y_height: float, thk: float,
		collide_only: bool) -> void:
	var pos: Vector3 = Vector3(a, y_center, perp) if along_x else Vector3(perp, y_center, a)
	var size: Vector3 = Vector3(along_len, y_height, thk) if along_x else Vector3(thk, y_height, along_len)
	if collide_only:
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = size
		col.shape = cs
		col.position = pos
		body.add_child(col)
	else:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		m.mesh = box
		m.material_override = mat
		m.position = pos
		body.add_child(m)


# A perimeter wall with a centred doorway: two solid side pieces (mesh + collision)
# flank an open gap, framed by jambs + a lintel. The gap has NO collision so the
# player walks straight through. Used by the ground floor (the Garden, Floor 1).
static func _build_one_wall_doored(parent: Node3D, c: Node, side: String, half: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall_" + side
	parent.add_child(body)
	var along_x: bool = side in ["+z", "-z"]
	var perp: float = half if side in ["+x", "+z"] else -half
	var length: float = c.FLOOR_3D_SIZE
	var thick: float = c.WALL_THICKNESS
	var dw: float = c.DOOR_WIDTH
	var dh: float = c.DOOR_HEIGHT
	var side_len: float = (length - dw) * 0.5
	var side_ctr: float = (dw + side_len) * 0.5
	var wall_mat := _flat_material(Color(0.32, 0.32, 0.36))
	var frame_mat := _flat_material(Color(0.30, 0.30, 0.34))
	var glass_h: float = c.WALL_HEIGHT - c.WALL_BASE_HEIGHT - 0.12

	for sgn in [-1.0, 1.0]:
		var a: float = sgn * side_ctr
		_wall_piece(body, wall_mat, along_x, perp, a, side_len, c.WALL_BASE_HEIGHT * 0.5, c.WALL_BASE_HEIGHT, thick, false)  # base
		_wall_piece(body, null, along_x, perp, a, side_len, c.WALL_HEIGHT * 0.5, c.WALL_HEIGHT, thick, true)               # collision (full height)
		_wall_piece(body, _make_window_material(), along_x, perp, a, side_len - 0.4, c.WALL_BASE_HEIGHT + glass_h * 0.5, glass_h, 0.05, false)  # glass

	# Door frame: jambs flanking the opening + a lintel above it (mesh only).
	for sgn in [-1.0, 1.0]:
		_wall_piece(body, frame_mat, along_x, perp, sgn * dw * 0.5, 0.18, dh * 0.5, dh, thick * 1.1, false)
	var lintel_h: float = c.WALL_HEIGHT - dh
	_wall_piece(body, frame_mat, along_x, perp, 0.0, dw, dh + lintel_h * 0.5, lintel_h, thick * 1.1, false)

	# Top trim spanning the full wall (matches the solid wall's cap).
	_wall_piece(body, _flat_material(Color(0.28, 0.28, 0.32)), along_x, perp, 0.0, length, c.WALL_HEIGHT - 0.06, 0.12, thick * 1.05, false)

	# Spandrel band (see _build_one_wall) — closes the gap up to the slab above so the
	# doored floor reads as part of the same tight structure as the solid-walled floors.
	var span_h: float = float(c.FLOOR_3D_STORY_HEIGHT) - float(c.WALL_HEIGHT)
	if span_h > 0.01:
		_wall_piece(body, _flat_material(Color(0.30, 0.30, 0.34)), along_x, perp, 0.0, length, c.WALL_HEIGHT + span_h * 0.5, span_h, thick * 1.02, false)


# Builds a faint blueprint-style grid extending outward from each wall —
# 6 perpendicular lines per side fading from solid to transparent over 2 m,
# plus a perpendicular crossbar at the solid/fade boundary that closes the
# rectangle around the room.
static func build_extension_grid(parent: Node3D, c: Node) -> void:
	var half: float = c.FLOOR_3D_SIZE * 0.5
	var y_offset := 0.005
	var pane_count: int = int(c.EXTENSION_PANE_COUNT)
	var pane_step: float = c.FLOOR_3D_SIZE / float(pane_count)
	var pane_positions: Array = []
	for k in range(pane_count):
		pane_positions.append(-half + (float(k) + 0.5) * pane_step)

	var line_mesh := _make_extension_line_mesh(c)
	var line_mat := _make_extension_line_material()
	var bar_mat := _make_extension_crossbar_material(c)

	for s in ["+x", "-x", "+z", "-z"]:
		var rot_y := 0.0
		var origin: Vector3
		match s:
			"+x":
				rot_y = 0.0
				origin = Vector3(half, y_offset, 0)
			"-x":
				rot_y = PI
				origin = Vector3(-half, y_offset, 0)
			"+z":
				rot_y = -PI * 0.5
				origin = Vector3(0, y_offset, half)
			"-z":
				rot_y = PI * 0.5
				origin = Vector3(0, y_offset, -half)

		for offset in pane_positions:
			var line := MeshInstance3D.new()
			line.name = "GridExtLine"
			line.mesh = line_mesh
			line.material_override = line_mat
			match s:
				"+x", "-x":
					line.position = origin + Vector3(0, 0, offset)
				"+z", "-z":
					line.position = origin + Vector3(offset, 0, 0)
			line.rotation.y = rot_y
			parent.add_child(line)

		var solid_dist: float = c.EXTENSION_LINE_SOLID_LENGTH
		var bar_length: float = c.FLOOR_3D_SIZE + 2.0 * solid_dist
		var bar := MeshInstance3D.new()
		bar.name = "GridExtCrossbar"
		var box := BoxMesh.new()
		match s:
			"+x":
				box.size = Vector3(0.04, 0.01, bar_length)
				bar.position = Vector3(half + solid_dist, y_offset, 0)
			"-x":
				box.size = Vector3(0.04, 0.01, bar_length)
				bar.position = Vector3(-half - solid_dist, y_offset, 0)
			"+z":
				box.size = Vector3(bar_length, 0.01, 0.04)
				bar.position = Vector3(0, y_offset, half + solid_dist)
			"-z":
				box.size = Vector3(bar_length, 0.01, 0.04)
				bar.position = Vector3(0, y_offset, -half - solid_dist)
		bar.mesh = box
		bar.material_override = bar_mat
		parent.add_child(bar)


# Builds the central elevator / spine core (the static shaft each floor
# shares — the ride-able car itself is scenes/shared/elevator_platform.gd).
# Octagonal cross-section (square with 45° chamfered corners). Chamfered
# corners are flat panels where the spine pipes run; cardinal faces are the
# open doorways the car passes through. Returns a Dictionary of the geometry;
# today only `corners` (spine-pipe mounts) + `inner_mat` are consumed, but
# the full set is kept so a future caller can build against the faces:
#   {
#     "core": StaticBody3D,             # the elevator root
#     "size": float,                    # outer square side length
#     "chamfer": float,                 # corner cut length
#     "height": float,                  # full elevator visual height
#     "side_length": float,             # cardinal face length after chamfer
#     "cardinals": [{"normal": Vector3, "tangent": Vector3, "centre": Vector3}, ...],
#     "corners":   {"NW": {"centre": Vector3, "tangent": Vector3}, ...},
#   }
# Doors are NOT built here — handler builds them with the geometry data.
static func build_elevator_core(parent: Node3D, c: Node) -> Dictionary:
	var size: float = float(c.ELEVATOR_RADIUS) * 2.0 * c.GARDEN_PLOT_SIZE
	var chamfer: float = c.ELEVATOR_CHAMFER
	# Capped at WALL_HEIGHT so the core tops out flush with the perimeter walls
	# instead of poking above them. The top-down iso view hides the floor above,
	# so anything taller than the walls (the old full-STORY core) reads as a shaft
	# "floating into the floor above." The <1 m gap below the next floor's slab
	# tucks under that slab when the tower is stacked, so the shaft still reads as
	# continuous. (It used to be STORY = 6 m — see F-022 — and before that
	# WALL_HEIGHT × ELEVATOR_HEIGHT_MULT ≈ 7.5 m, which clipped the player's hat.)
	var height: float = float(c.WALL_HEIGHT)
	var side_length: float = size - 2.0 * chamfer

	var body := StaticBody3D.new()
	body.name = "ElevatorCore"
	parent.add_child(body)

	# --- Floor + ceiling caps (octagonal prism)
	# Built as 8 wedge-shaped triangles around the centre, top + bottom.
	# Easier: two separate cylinder MeshInstance3D nodes with 8 sides.
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.28, 0.30, 0.36)
	cap_mat.roughness = 0.55
	cap_mat.metallic = 0.4

	# No top "halo ring" cap: in the stacked tower the cores tile into one
	# continuous shaft, so a per-floor cap would sit mid-shaft (and the
	# floor-below's cap used to land at head height — see F-022).

	# Inner translucent core column — spans the full story so stacked floors'
	# columns meet flush, reading as one continuous shaft top to bottom.
	var inner := MeshInstance3D.new()
	inner.name = "InnerCore"
	var inner_mesh := CylinderMesh.new()
	inner_mesh.top_radius = side_length * 0.5
	inner_mesh.bottom_radius = side_length * 0.5
	inner_mesh.height = height
	inner_mesh.radial_segments = 8
	inner.mesh = inner_mesh
	# Glass shaft column — same feel as the Canopy glass, so you can watch the
	# elevator cabin rise + fall through it. The grey chamfer corners + door-frame
	# beams (below) stay opaque; only this enclosing tube is glass.
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.80, 0.86, 0.92, 0.18)
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.roughness = 0.10
	inner_mat.metallic = 0.0
	# A whisper of blue inner light so the tube reads as live, not dead glass.
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(0.45, 0.66, 0.90)
	inner_mat.emission_energy_multiplier = 0.10
	inner.material_override = inner_mat
	inner.position.y = height * 0.5
	inner.rotation.y = PI * 0.125
	body.add_child(inner)

	# --- Chamfered corner panels (4) — pipes will mount on these. Each
	# panel also carries a thin collision shape so the player can't walk
	# through the elevator's corners; the cardinal-face areas have NO
	# collision so the player can walk INTO the elevator through the doors.
	for corner in ["NW", "NE", "SE", "SW"]:
		var sx: float = -1.0 if corner == "NW" or corner == "SW" else 1.0
		var sz: float = -1.0 if corner == "NW" or corner == "NE" else 1.0
		var cx: float = sx * (size * 0.5 - chamfer * 0.5)
		var cz: float = sz * (size * 0.5 - chamfer * 0.5)
		var yaw_for_corner: float
		match corner:
			"NW": yaw_for_corner = PI * 0.25
			"NE": yaw_for_corner = -PI * 0.25
			"SE": yaw_for_corner = PI * 0.25
			"SW": yaw_for_corner = -PI * 0.25
		var panel := MeshInstance3D.new()
		panel.name = "Chamfer_" + corner
		var pm := BoxMesh.new()
		pm.size = Vector3(chamfer * sqrt(2.0), height, 0.08)
		panel.mesh = pm
		panel.material_override = cap_mat
		panel.position = Vector3(cx, height * 0.5, cz)
		panel.rotation.y = yaw_for_corner
		body.add_child(panel)
		# Collision shape — thin slab matching the chamfer panel.
		var col := CollisionShape3D.new()
		col.name = "ChamferCol_" + corner
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(chamfer * sqrt(2.0), height, 0.08)
		col.shape = col_shape
		col.position = Vector3(cx, height * 0.5, cz)
		col.rotation.y = yaw_for_corner
		body.add_child(col)

	# --- Cardinal-face shaft walls (4). Each face gets a framed DOORWAY: two side
	# jambs + a lintel above, leaving a central opening. This is what makes the
	# shaft read as an enclosed elevator shaft on EVERY floor — previously the
	# cardinal faces were bare, so any floor without the car parked at it (tube-
	# reached upper floors, or a served floor with the car elsewhere) showed an
	# open, skeletal shaft. Visual only (no collision) so walking onto the car +
	# the car's own doors are unaffected; the central opening stays clear.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.33, 0.35, 0.41)
	wall_mat.metallic = 0.45
	wall_mat.roughness = 0.5
	# Landing-door material — opaque metal (reads as a closed elevator door),
	# a touch lighter than the shaft frame so the door is legible against it.
	var landing_mat := StandardMaterial3D.new()
	landing_mat.albedo_color = Color(0.38, 0.42, 0.49)
	landing_mat.metallic = 0.55
	landing_mat.roughness = 0.32
	var door_h: float = minf(2.8, height - 0.4)
	var door_w: float = side_length * 0.72
	var jamb_w: float = (side_length - door_w) * 0.5
	var wall_thk: float = 0.1
	for spec in [
		{"tangent": Vector3(1, 0, 0), "normal": Vector3(0, 0, 1), "centre": Vector3(0, 0, -size * 0.5)},
		{"tangent": Vector3(1, 0, 0), "normal": Vector3(0, 0, 1), "centre": Vector3(0, 0, size * 0.5)},
		{"tangent": Vector3(0, 0, 1), "normal": Vector3(1, 0, 0), "centre": Vector3(size * 0.5, 0, 0)},
		{"tangent": Vector3(0, 0, 1), "normal": Vector3(1, 0, 0), "centre": Vector3(-size * 0.5, 0, 0)},
	]:
		var tang: Vector3 = spec.tangent
		var norm: Vector3 = spec.normal
		var ctr: Vector3 = spec.centre
		# Two jambs flanking the opening.
		for sgn in [-1.0, 1.0]:
			var t_off: float = sgn * (door_w + jamb_w) * 0.5
			_add_shaft_panel(body, wall_mat, ctr + tang * t_off, tang, norm, jamb_w, wall_thk, height * 0.5, height)
		# Lintel above the opening.
		var lintel_h: float = height - door_h
		_add_shaft_panel(body, wall_mat, ctr, tang, norm, door_w, wall_thk, door_h + lintel_h * 0.5, lintel_h)

		# --- LANDING DOOR filling the opening. Before this, the cardinal opening was a
		# clear gap: any floor the car wasn't parked at showed the open shaft straight
		# down the glass to the cabin below (the operator's "floor disappearing / car
		# below" report). The car's own doors travel WITH the car, so they can't cover a
		# floor it has left. This per-floor door is OPAQUE + CLOSED by default (occludes
		# the shaft + the drop); the elevator slides it open ONLY for the floor the car
		# rests at (group "elevator_landing", driven in _apply_landing_doors). Visual-only,
		# like the shaft walls — boarding + the car transform are untouched; the ShaftGrate
		# still catches falls.
		var land := Node3D.new()
		land.name = "LandingDoor"
		land.position = ctr                      # face centre, AT the floor origin y (car-match anchor)
		land.set_meta("door_h", door_h)
		land.add_to_group("elevator_landing")
		body.add_child(land)
		var leaf := MeshInstance3D.new()
		leaf.name = "Leaf"
		var leaf_mesh := BoxMesh.new()
		# Wide along the face tangent, tall = door_h, thin along the face normal.
		leaf_mesh.size = Vector3(door_w, door_h, wall_thk * 0.9) if absf(tang.x) > 0.5 \
			else Vector3(wall_thk * 0.9, door_h, door_w)
		leaf.mesh = leaf_mesh
		leaf.material_override = landing_mat
		# Just proud of the face plane; closed spans 0..door_h above the floor origin.
		leaf.position = norm * (wall_thk * 0.5 + 0.02) + Vector3(0, door_h * 0.5, 0)
		land.add_child(leaf)

	# --- Geometry-data dict. Cardinal faces (N/S/E/W) — kept for any future
	# caller that builds against the open doorways; unused by the car today.
	var cardinals := []
	for spec in [
		{"name": "N", "normal": Vector3(0, 0, -1), "tangent": Vector3(1, 0, 0), "centre_offset": Vector3(0, 0, -size * 0.5)},
		{"name": "S", "normal": Vector3(0, 0, 1), "tangent": Vector3(1, 0, 0), "centre_offset": Vector3(0, 0, size * 0.5)},
		{"name": "E", "normal": Vector3(1, 0, 0), "tangent": Vector3(0, 0, 1), "centre_offset": Vector3(size * 0.5, 0, 0)},
		{"name": "W", "normal": Vector3(-1, 0, 0), "tangent": Vector3(0, 0, 1), "centre_offset": Vector3(-size * 0.5, 0, 0)},
	]:
		cardinals.append(spec)

	var corners := {}
	for corner in ["NW", "NE", "SE", "SW"]:
		var sx: float = -1.0 if corner == "NW" or corner == "SW" else 1.0
		var sz: float = -1.0 if corner == "NW" or corner == "NE" else 1.0
		var cx: float = sx * (size * 0.5 - chamfer * 0.5)
		var cz: float = sz * (size * 0.5 - chamfer * 0.5)
		# Tangent runs along the chamfer face — clockwise around the elevator.
		var tangent_dir: Vector3
		match corner:
			"NW": tangent_dir = Vector3(1, 0, -1).normalized()
			"NE": tangent_dir = Vector3(1, 0, 1).normalized()
			"SE": tangent_dir = Vector3(-1, 0, 1).normalized()
			"SW": tangent_dir = Vector3(-1, 0, -1).normalized()
		corners[corner] = {
			"centre": Vector3(cx, 0, cz),
			"tangent": tangent_dir,
			"normal": Vector3(sx, 0, sz).normalized(),
		}

	return {
		"core": body,
		"size": size,
		"chamfer": chamfer,
		"height": height,
		"side_length": side_length,
		"cardinals": cardinals,
		"corners": corners,
		"inner_mat": inner_mat,
	}


# Passive spine pipes — visual-only renderer used by floors that don't own
# the connect/activate flow. Reads GameState.utility to determine each
# pipe's state at scene-load time. Cold pipes are always present; the
# emissive fill cylinder is drawn only when pipe_active[id] is true,
# already at full height. No tweens, no per-frame state.
static func build_passive_spine_pipes(parent: Node3D, c: Node, gs: Node, elevator_data: Dictionary) -> void:
	var pipe_height: float = c.UTILITY_SPINE_PIPE_TOP_Y - c.UTILITY_SPINE_PIPE_BASE_Y
	var pipe_mid_y: float = (c.UTILITY_SPINE_PIPE_BASE_Y + c.UTILITY_SPINE_PIPE_TOP_Y) * 0.5
	var chamfer_width: float = c.ELEVATOR_CHAMFER * sqrt(2.0)
	var slot_offset: float = chamfer_width * 0.22
	var corners: Dictionary = elevator_data.get("corners", {})
	for sys in c.UTILITY_SYSTEMS:
		var corner_spec: Array = c.UTILITY_PIPE_CORNERS[sys.id]
		var corner_name: String = corner_spec[0]
		var slot: int = corner_spec[1]
		var corner: Dictionary = corners.get(corner_name, {})
		if corner.is_empty():
			continue
		var centre: Vector3 = corner.centre
		var tangent: Vector3 = corner.tangent
		var normal: Vector3 = corner.normal
		var outboard: float = c.UTILITY_SPINE_PIPE_RADIUS + 0.06
		var count: int = int(c.UTILITY_CORNER_COUNTS.get(corner_name, 1))
		var slot_pos: float = 0.0 if count == 1 else (slot_offset if slot == 1 else -slot_offset)
		var pipe_pos: Vector3 = centre + tangent * slot_pos + normal * outboard
		var base_col: Color = sys.base_color
		var active: bool = bool(gs.utility.pipe_active.get(sys.id, false))

		var cold := MeshInstance3D.new()
		cold.name = "PassivePipe_" + sys.id
		var cold_mesh := CylinderMesh.new()
		cold_mesh.top_radius = c.UTILITY_SPINE_PIPE_RADIUS
		cold_mesh.bottom_radius = c.UTILITY_SPINE_PIPE_RADIUS
		cold_mesh.height = pipe_height
		cold.mesh = cold_mesh
		var cold_mat := StandardMaterial3D.new()
		cold_mat.albedo_color = base_col * c.UTILITY_SOURCE_COLD_MULT
		cold_mat.roughness = 0.5
		cold_mat.metallic = 0.4
		cold.material_override = cold_mat
		cold.position = pipe_pos + Vector3(0, pipe_mid_y, 0)
		parent.add_child(cold)

		# The lit "fill" overlay is ALWAYS built now (was build-time only). In the
		# stacked tower every floor is built at startup, before any utility is
		# online, so a build-time check always saw inactive and the lit state
		# never climbed past Floor 0. Instead we build it for every system and
		# toggle visibility live: it joins the "passive_spine_fill" group tagged
		# with its system id, and tower_controller drives `visible` from
		# GameState.utility.pipe_active each frame, so activating a utility lights
		# its riser continuously all the way up the shaft.
		var fill := MeshInstance3D.new()
		fill.name = "PassiveFill_" + sys.id
		var fill_mesh := CylinderMesh.new()
		fill_mesh.top_radius = c.UTILITY_SPINE_PIPE_RADIUS * 1.05
		fill_mesh.bottom_radius = c.UTILITY_SPINE_PIPE_RADIUS * 1.05
		fill_mesh.height = pipe_height
		fill.mesh = fill_mesh
		var fill_mat := StandardMaterial3D.new()
		fill_mat.albedo_color = base_col
		fill_mat.emission_enabled = true
		fill_mat.emission = sys.glow_color
		fill_mat.emission_energy_multiplier = 1.6
		fill.material_override = fill_mat
		fill.position = pipe_pos + Vector3(0, pipe_mid_y, 0) + normal * 0.005
		fill.visible = active
		fill.set_meta("sys_id", sys.id)
		fill.add_to_group("passive_spine_fill")
		parent.add_child(fill)


# --- Internal --------------------------------------------------------------

static func _build_one_wall(parent: Node3D, c: Node, side: String, half: float, seal: bool = true, seal_height: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall_" + side
	parent.add_child(body)
	var wall_along_x: bool = side in ["+z", "-z"]
	var perp_pos: float = half if side in ["+x", "+z"] else -half
	var length: float = c.FLOOR_3D_SIZE
	var thick: float = c.WALL_THICKNESS
	# Collision can reach higher than the visible wall so a jump can't clear it.
	# An explicit seal_height caps it (e.g. the basement tops out at the floor
	# above, not into its doorways).
	var coll_h: float = seal_height if seal_height > 0.0 else (float(c.WALL_SEAL_HEIGHT) if seal else float(c.WALL_HEIGHT))

	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_size: Vector3
	if wall_along_x:
		base_size = Vector3(length, c.WALL_BASE_HEIGHT, thick)
	else:
		base_size = Vector3(thick, c.WALL_BASE_HEIGHT, length)
	var bm := BoxMesh.new()
	bm.size = base_size
	base.mesh = bm
	base.material_override = _flat_material(Color(0.32, 0.32, 0.36))
	base.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_BASE_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(base)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	if wall_along_x:
		col_shape.size = Vector3(length, coll_h, thick)
	else:
		col_shape.size = Vector3(thick, coll_h, length)
	col.shape = col_shape
	col.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		coll_h * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(col)

	var post_count := int(length / c.WALL_POST_SPACING) + 1
	for k in range(post_count):
		var t: float = float(k) / float(post_count - 1)
		var along: float = -length * 0.5 + t * length
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % k
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.18, c.WALL_HEIGHT - c.WALL_BASE_HEIGHT, 0.18)
		post.mesh = post_mesh
		post.material_override = _flat_material(Color(0.38, 0.38, 0.42))
		post.position = Vector3(
			along if wall_along_x else perp_pos,
			(c.WALL_BASE_HEIGHT + c.WALL_HEIGHT) * 0.5,
			perp_pos if wall_along_x else along,
		)
		body.add_child(post)

	var trim := MeshInstance3D.new()
	trim.name = "TopTrim"
	var trim_mesh := BoxMesh.new()
	if wall_along_x:
		trim_mesh.size = Vector3(length, 0.12, thick * 1.05)
	else:
		trim_mesh.size = Vector3(thick * 1.05, 0.12, length)
	trim.mesh = trim_mesh
	trim.material_override = _flat_material(Color(0.28, 0.28, 0.32))
	trim.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_HEIGHT - 0.06,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(trim)

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var glass_mesh := BoxMesh.new()
	var glass_h: float = c.WALL_HEIGHT - c.WALL_BASE_HEIGHT - 0.12
	if wall_along_x:
		glass_mesh.size = Vector3(length - 0.4, glass_h, 0.05)
	else:
		glass_mesh.size = Vector3(0.05, glass_h, length - 0.4)
	glass.mesh = glass_mesh
	glass.material_override = _make_window_material()
	glass.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_BASE_HEIGHT + glass_h * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(glass)

	# Spandrel band — fills the gap between the window head (WALL_HEIGHT) and the
	# slab of the floor directly above (one story up). Without it each floor's walls
	# stop ~0.8 m short of the ceiling, so the stack reads as slabs floating with a
	# gap between them. The opaque band makes the floors a continuous, tight tower.
	var span_h: float = float(c.FLOOR_3D_STORY_HEIGHT) - float(c.WALL_HEIGHT)
	if span_h > 0.01:
		var span := MeshInstance3D.new()
		span.name = "Spandrel"
		var span_mesh := BoxMesh.new()
		if wall_along_x:
			span_mesh.size = Vector3(length, span_h, thick * 1.02)
		else:
			span_mesh.size = Vector3(thick * 1.02, span_h, length)
		span.mesh = span_mesh
		span.material_override = _flat_material(Color(0.30, 0.30, 0.34))
		span.position = Vector3(
			0.0 if wall_along_x else perp_pos,
			float(c.WALL_HEIGHT) + span_h * 0.5,
			perp_pos if wall_along_x else 0.0,
		)
		body.add_child(span)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


static func _make_window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.5
	return m


static func _make_extension_line_mesh(c: Node) -> ArrayMesh:
	var thick := 0.04
	var solid_len: float = c.EXTENSION_LINE_SOLID_LENGTH
	var total_len: float = c.EXTENSION_GRID_LENGTH
	var peak: float = c.EXTENSION_LINE_PEAK_ALPHA

	var verts := PackedVector3Array([
		Vector3(0.0,       0, -thick * 0.5), Vector3(0.0,       0, thick * 0.5),
		Vector3(solid_len, 0, -thick * 0.5), Vector3(solid_len, 0, thick * 0.5),
		Vector3(total_len, 0, -thick * 0.5), Vector3(total_len, 0, thick * 0.5),
	])
	var solid := Color(1, 1, 1, peak)
	var fade := Color(1, 1, 1, 0.0)
	var colors := PackedColorArray([solid, solid, solid, solid, fade, fade])
	var indices := PackedInt32Array([
		0, 1, 2,  1, 3, 2,
		2, 3, 4,  3, 5, 4,
	])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _make_extension_line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _make_extension_crossbar_material(c: Node) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, c.EXTENSION_LINE_PEAK_ALPHA)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
