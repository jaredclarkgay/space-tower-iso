extends RefCounted

# Procedural, genome-driven tree geometry for the Arboretum.
#
# A tree's appearance + behaviour derive from a *genome* (Dictionary of
# continuous float genes) layered on an *archetype* (apple-ish / pine-ish —
# shared gene space, different gene means + crown shape + base colour). Two
# pines look related but distinct because they share an archetype but draw
# their genes with per-gene variance. Cross-breeding (Phase 3) just blends two
# genomes through the same builder.
#
# All per-tree randomness (lean direction, branch placement, asymmetry axis)
# is seeded from the tree's `rng_seed`, so a tree looks IDENTICAL across floor
# swaps and save/load. The genome itself is generated once and stored in
# GameState.arboretum.trees, so it never drifts.
#
# Floor 2 renders trees with their base at FLOOR_3D_TOP_Y (~0.2 m). Floor 3
# renders the SAME trees offset by -FLOOR_3D_STORY_HEIGHT (-3 m) so the visible
# portion above Floor 3's slab is exactly the part poking above Floor 2's
# ceiling. Floor 3's slab has a hole at each tree position; lean is clamped so
# the trunk always clears that hole.
#
# Loaded via preload, NOT class_name (per F-010).

const VARIETY_COUNT := 2

# --- Genome definition ---------------------------------------------------
#
# Every gene is a continuous float. Multiplier genes centre on 1.0; offset
# genes centre on 0.0. Bounds are clamped on every write (founder draw + every
# mutation) so even a big mutation can't make a zero-size / invisible tree.
const GENE_BOUNDS := {
	"vigor": Vector2(0.7, 1.3),            # overall size + rate multiplier
	"trunk_height": Vector2(0.6, 1.4),     # trunk length bias
	"trunk_girth": Vector2(0.6, 1.4),      # trunk radius bias
	"crown_size": Vector2(0.6, 1.4),       # crown diameter bias
	"crown_density": Vector2(0.3, 1.0),    # foliage fullness → O2 + colour
	"crown_asymmetry": Vector2(0.0, 0.6),  # lopsidedness
	"lean": Vector2(0.0, 1.0),             # lean magnitude (0 = upright)
	"branch_count": Vector2(0.0, 1.0),     # secondary branch density (0..5)
	"hue_shift": Vector2(-0.08, 0.08),     # foliage hue offset from archetype
	"o2_efficiency": Vector2(0.6, 1.4),    # oxygen per unit leaf area (breeding target)
	"maturation_rate": Vector2(0.7, 1.3),  # time-axis scale on growth curve
	"senescence_onset": Vector2(0.7, 1.0), # life fraction before O2 declines
}

# Defaults used for any gene an archetype doesn't override.
const DEFAULT_MEAN := {
	"vigor": 1.0, "trunk_height": 1.0, "trunk_girth": 1.0, "crown_size": 1.0,
	"crown_density": 0.7, "crown_asymmetry": 0.12, "lean": 0.15, "branch_count": 0.4,
	"hue_shift": 0.0, "o2_efficiency": 1.0, "maturation_rate": 1.0, "senescence_onset": 0.9,
}
# Gaussian sigma (in gene units) for the founder draw around the mean.
# Deliberately wide so two founders of the same archetype read as obviously
# different individuals (not ±10% clones). Bounds-clamping keeps them valid.
const DEFAULT_SIGMA := {
	"vigor": 0.15, "trunk_height": 0.22, "trunk_girth": 0.18, "crown_size": 0.24,
	"crown_density": 0.22, "crown_asymmetry": 0.20, "lean": 0.40, "branch_count": 0.32,
	"hue_shift": 0.050, "o2_efficiency": 0.18, "maturation_rate": 0.16, "senescence_onset": 0.06,
}

# Archetypes share the gene space; they differ in gene means, crown shape
# (discrete — inherited from the dominant parent on breeding), trunk colour,
# and base foliage colour.
# `crown_aspect` is a static archetype property (height/width ratio of the
# crown) — <1 squashes wide (broad apple canopy), >1 stretches tall (pine).
const ARCHETYPES := [
	{   # 0 — apple-ish: rounded, BROAD crown, short fat trunk, warm bright green
		"crown_shape": "sphere",
		"crown_aspect": 0.78,
		"trunk_color": Color(0.45, 0.30, 0.18),
		"foliage_base": Color(0.42, 0.68, 0.28),
		"mean": {"crown_size": 1.24, "crown_density": 0.64, "trunk_girth": 1.15,
				 "trunk_height": 0.90, "branch_count": 0.60},
	},
	{   # 1 — pine-ish: conical, NARROW crown, tall thin trunk, dark cool green
		"crown_shape": "cone",
		"crown_aspect": 1.20,
		"trunk_color": Color(0.30, 0.21, 0.13),
		"foliage_base": Color(0.15, 0.42, 0.22),
		"mean": {"trunk_height": 1.32, "crown_size": 0.72, "crown_density": 0.90,
				 "trunk_girth": 0.82, "branch_count": 0.28, "lean": 0.12},
	},
]

const _FOUNDER_SEED_SALT := 0x9E3779B9   # de-correlates founder-draw RNG from phenotype RNG


# --- Genome helpers ------------------------------------------------------

static func archetype_for(variety: int) -> Dictionary:
	return ARCHETYPES[variety % VARIETY_COUNT]


static func clamp_gene(gene: String, value: float) -> float:
	var b: Vector2 = GENE_BOUNDS[gene]
	return clampf(value, b.x, b.y)


static func _mean_for(arch: Dictionary, gene: String) -> float:
	return float(arch.get("mean", {}).get(gene, DEFAULT_MEAN[gene]))


# Founder genome: each gene = archetype mean + Gaussian noise (per-gene sigma),
# clamped to bounds. Seeded off rng_seed (salted) so a migrated legacy tree
# always regenerates the SAME genome.
static func make_founder_genome(variety: int, rng_seed: int) -> Dictionary:
	var arch := archetype_for(variety)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed ^ _FOUNDER_SEED_SALT
	var g: Dictionary = {}
	for gene in GENE_BOUNDS:
		g[gene] = clamp_gene(gene, _mean_for(arch, gene) + rng.randfn(0.0, float(DEFAULT_SIGMA[gene])))
	return g


# Full founder tree-state dict for a fresh plant. Additive over the legacy
# {variety, planted_at_msec, world_pos} shape — never repurposes those keys.
# `now_msec` is the current SIM-clock time (GameState.sim_time_msec); `stagger`
# delays growth start so a batch of founders ripples in one after another.
static func new_tree_state(variety: int, world_pos: Vector3, now_msec: float, stagger: float = 0.0) -> Dictionary:
	var seed_val := randi()
	return {
		"variety": variety % VARIETY_COUNT,
		"planted_at_msec": now_msec,
		"growth_start_msec": now_msec + stagger,
		"world_pos": world_pos,
		"genome": make_founder_genome(variety, seed_val),
		"rng_seed": seed_val,
		"generation": 0,
		"parents": [],
		"o2_rate": 0.0,
		"fertile": false,
		"last_seed_msec": 0,
	}


# Migration: any tree dict missing the genome (old save, pre-genome plant)
# gets a founder genome from its `variety` archetype plus a fresh rng_seed.
# Idempotent — safe to call every time a tree is read. Mutates `tree` in place.
static func ensure_genome(tree: Dictionary) -> Dictionary:
	if not tree.has("rng_seed") or int(tree.get("rng_seed", 0)) == 0:
		tree["rng_seed"] = randi()
	if not tree.has("genome") or not (tree["genome"] is Dictionary) or tree["genome"].is_empty():
		tree["genome"] = make_founder_genome(int(tree.get("variety", 0)), int(tree["rng_seed"]))
	# Backfill newer fields so the dict shape is complete for Phase 2/3.
	if not tree.has("growth_start_msec"): tree["growth_start_msec"] = float(tree.get("planted_at_msec", 0))
	if not tree.has("generation"): tree["generation"] = 0
	if not tree.has("parents"): tree["parents"] = []
	if not tree.has("o2_rate"): tree["o2_rate"] = 0.0
	if not tree.has("fertile"): tree["fertile"] = false
	if not tree.has("last_seed_msec"): tree["last_seed_msec"] = 0
	return tree


# --- Growth --------------------------------------------------------------

# Normalised maturity progress in [0,1] using the saturating-exponential curve.
# `maturation_rate` scales the time axis (faster gene → reaches maturity sooner).
#
# To use the alternate Gompertz (establishment-lag) feel instead, replace the
# final two lines with:
#   var B := float(c.TREE_GOMPERTZ_B); var C := float(c.TREE_GOMPERTZ_C)
#   var raw := func(x): return exp(-B * exp(-C * x))
#   return (raw.call(u) - raw.call(0.0)) / (raw.call(1.0) - raw.call(0.0))
static func growth_t_for(tree: Dictionary, c: Node, now_msec: float) -> float:
	ensure_genome(tree)
	var u: float = _life_frac(tree, c, now_msec, true)
	if u <= 0.0:
		return 0.0
	var k: float = float(c.TREE_GROWTH_CURVE_K)
	return (1.0 - exp(-k * u)) / (1.0 - exp(-k))


# Raw fraction of the maturation window elapsed, measured on the SIM clock from
# the tree's growth_start (which may be staggered after planting). Negative
# elapsed (not started yet) reads as 0. `clamped` caps at 1.0 for the growth
# curve; uncapped (can exceed 1.0) it drives Phase-2 senescence.
static func _life_frac(tree: Dictionary, c: Node, now_msec: float, clamped: bool) -> float:
	var mat: float = float(tree.get("genome", {}).get("maturation_rate", 1.0))
	var window_ms: float = float(c.TREE_GROWTH_DURATION_MS) / maxf(mat, 0.01)
	var start_ms: float = float(tree.get("growth_start_msec", tree.get("planted_at_msec", 0)))
	var elapsed_ms: float = now_msec - start_ms
	var f: float = maxf(elapsed_ms, 0.0) / window_ms
	return clampf(f, 0.0, 1.0) if clamped else f


# --- Geometry ------------------------------------------------------------
#
# A tree is built ONCE at its genome's MATURE form into two merged meshes —
# a branch mesh (bark) and a foliage mesh — held under a "Grow" node. Each
# vertex carries CUSTOM0 = (growth-origin.xyz, birth): the point it grows FROM
# and when in [0,1] it should start appearing. Phase A doesn't read that yet —
# it fakes growth with a temporary ground-anchored scale on the Grow node.
# Phase B swaps that scale for a vertex shader that eases each vertex from its
# origin using CUSTOM0, with NO mesh rebuild.

const BRANCH_SIDES := 6
const FOLIAGE_TIER_SIDES := 9
const FOLIAGE_BLOB_RINGS := 5
const FOLIAGE_BLOB_SEGS := 7

# Baked growth-order birth times (consumed by the reveal shader). Spaced so a
# child element is born roughly as its parent finishes revealing (span ~0.24),
# avoiding geometry that floats before its parent reaches it.
const _BIRTH_TRUNK := 0.0
const _BIRTH_PER_LEVEL := 0.20   # each recursion level is born this much later
const _BIRTH_FOLIAGE := 0.70

# One shared reveal Shader for every tree (lazily compiled). Per-tree variation
# rides on per-tree ShaderMaterials (albedo) + the `growth` uniform — the
# Compatibility-renderer stand-in for Forward+ per-instance uniforms.
static var _reveal_shader: Shader = null


# Builds a single tree as a child of `parent`. `tree` is its GameState dict
# (carries genome + rng_seed); `world_position` is the base in parent space.
# Returns a refs dict the caller stores so update() can drive growth per frame.
static func build(parent: Node3D, c: Node, tree: Dictionary, world_position: Vector3) -> Dictionary:
	ensure_genome(tree)
	var g: Dictionary = tree["genome"]
	var variety: int = int(tree.get("variety", 0)) % VARIETY_COUNT
	var arch := archetype_for(variety)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(tree.get("rng_seed", 0))

	var root := Node3D.new()
	root.name = "Tree_v%d" % variety
	root.position = world_position
	# Lean: tilt the whole tree about a fixed per-tree horizontal axis. Angle
	# clamped so the trunk stays inside the Floor 3 canopy hole at the slab.
	var lean_dir: float = rng.randf() * TAU
	var lean_tilt: float = _safe_lean_tilt(float(g["lean"]), c)
	if lean_tilt > 0.0001:
		root.transform.basis = Basis(Vector3(cos(lean_dir), 0.0, sin(lean_dir)), lean_tilt)
	parent.add_child(root)

	var asym_dir: float = rng.randf() * TAU

	var branch_st := SurfaceTool.new()
	branch_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	branch_st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var fol_st := SurfaceTool.new()
	fol_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	fol_st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

	# Floor-3 canopy slab in this tree's LOCAL frame, plus the open radius around
	# the trunk. The generators keep all branch/foliage geometry clear of the
	# slab "band" (only the trunk passes through, within the hole) so nothing
	# clips the canopy floor — branches live below it (Floor 2) or above (Floor 3).
	var slab_y: float = float(c.FLOOR_3D_STORY_HEIGHT) - world_position.y
	var hole_r: float = float(c.FLOOR_4_TREE_HOLE_RADIUS)
	var band: float = 0.55
	if String(arch.crown_shape) == "sphere":
		_gen_deciduous(branch_st, fol_st, c, g, rng, asym_dir, slab_y, band, hole_r)
	else:
		_gen_conifer(branch_st, fol_st, c, g, rng, asym_dir, slab_y, band, hole_r)

	# Per-tree materials (albedo) sharing ONE reveal Shader. update() drives the
	# `growth` uniform each frame from the sim clock; the shader unfolds each
	# vertex from its baked CUSTOM0 origin (developmental, not inflation).
	var bark_mat := _make_reveal_material(arch.trunk_color, 0.95, c)
	var branch_mi := MeshInstance3D.new()
	branch_mi.name = "Branches"
	branch_mi.mesh = branch_st.commit()
	branch_mi.material_override = bark_mat
	root.add_child(branch_mi)

	var fol_mat := _make_reveal_material(_foliage_color(arch, g), 0.9, c)
	var fol_mi := MeshInstance3D.new()
	fol_mi.name = "Foliage"
	fol_mi.mesh = fol_st.commit()
	fol_mi.material_override = fol_mat
	root.add_child(fol_mi)

	return {
		"root": root,
		"branch_mi": branch_mi,
		"foliage_mi": fol_mi,
		"mats": [bark_mat, fol_mat],
		"variety": variety,
	}


# Drives the tree's developmental growth by pushing `growth_t` (sim-clock,
# saturating-exp curve) into the shared reveal shader's per-tree `growth`
# uniform. The shader eases each vertex from its baked origin once growth passes
# the vertex's birth time — trunk → limbs → foliage. No mesh work per frame.
static func update(refs: Dictionary, _c: Node, _tree: Dictionary, growth_t: float) -> void:
	var t: float = clampf(growth_t, 0.0, 1.0)
	for m in refs.get("mats", []):
		m.set_shader_parameter("growth", t)


# Builds a per-tree ShaderMaterial on the shared reveal shader.
static func _make_reveal_material(albedo: Color, roughness: float, c: Node) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _get_reveal_shader()
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("span", float(c.TREE_REVEAL_SPAN))
	m.set_shader_parameter("wind_strength", float(c.TREE_WIND_STRENGTH))
	m.set_shader_parameter("growth", 0.0)
	return m


# Lazily compiles the one shared reveal+wind shader. Growth eases each vertex
# from CUSTOM0.xyz (its growth origin) using CUSTOM0.a (birth). Wind sways on
# real TIME (NOT the sim clock) so speeding up growth never makes sway shimmy.
static func _get_reveal_shader() -> Shader:
	if _reveal_shader != null:
		return _reveal_shader
	var sh := Shader.new()
	sh.code = "\n".join([
		"shader_type spatial;",
		"render_mode cull_disabled;",
		"",
		"uniform vec4 albedo : source_color = vec4(0.3, 0.5, 0.25, 1.0);",
		"uniform float roughness : hint_range(0.0, 1.0) = 0.9;",
		"uniform float growth = 0.0;          // 0..1 developmental progress (sim clock)",
		"uniform float span = 0.24;           // reveal duration per element",
		"uniform float wind_strength = 0.035;",
		"",
		"void vertex() {",
		"	vec3 origin = CUSTOM0.xyz;",
		"	float birth = CUSTOM0.a;",
		"	float sg = smoothstep(birth, birth + span, growth);",
		"	VERTEX = origin + (VERTEX - origin) * sg;        // unfold from origin",
		"",
		"	float tip = clamp(VERTEX.y * 0.12, 0.0, 1.0);    // sway more toward the top",
		"	float phase = origin.x * 1.7 + origin.z * 1.3;",
		"	VERTEX.x += sin(TIME * 1.2 + phase) * wind_strength * tip * sg;",
		"	VERTEX.z += cos(TIME * 1.0 + phase) * wind_strength * 0.7 * tip * sg;",
		"}",
		"",
		"void fragment() {",
		"	ALBEDO = albedo.rgb;",
		"	ROUGHNESS = roughness;",
		"}",
	])
	_reveal_shader = sh
	return _reveal_shader


# --- Skeleton generation -------------------------------------------------

# Resolves a computed tree height OUT of the slab "straddle zone" so every tree
# is either a clean Floor-3 sapling (crown below the slab) or a clean Floor-4
# canopy tree (crown above it) — never an awkward straddler that would clip the
# canopy floor. Returns [height, reaches_canopy].
#
# Also caps the trunk so even a max-genome tree's crown stays UNDER the floor
# above the Canopy (Residential): a canopy-reaching tree settles its crown on the
# Canopy deck (a few metres above the slab), never poking up through Floor 4.
static func _resolve_height(h: float, slab_y: float, band: float) -> Array:
	var short_max: float = slab_y - band - 1.0
	var tall_min: float = slab_y + 1.5
	# Trunk top at most ~3 m above the slab; the crown + foliage then sit
	# comfortably below the next floor's surface (~6 m above the slab).
	var tall_max: float = slab_y + 3.0
	if h > short_max and h < tall_min:
		h = short_max if h < (short_max + tall_min) * 0.5 else tall_min
	h = minf(h, tall_max)
	return [h, h >= tall_min]


# True when a position sits inside the slab band but outside the trunk hole —
# i.e. it would pierce the canopy floor. Branches/foliage here are dropped.
static func _in_band(p: Vector3, slab_y: float, band: float, hole_r: float) -> bool:
	return absf(p.y - slab_y) < band and Vector2(p.x, p.z).length() > hole_r


# Deciduous (apple): a leader trunk that passes up through the hole, a rounded
# crown ABOVE the slab band, and (for canopy-reaching trees) a few low limbs on
# Floor 2, all kept clear of the band.
static func _gen_deciduous(bst: SurfaceTool, fst: SurfaceTool, c: Node, g: Dictionary,
		rng: RandomNumberGenerator, asym_dir: float, slab_y: float, band: float, hole_r: float) -> void:
	var vigor: float = float(g["vigor"])
	var girth: float = float(c.TREE_TRUNK_RADIUS_MAX) * vigor * float(g["trunk_girth"])
	var crown_r: float = float(c.TREE_CROWN_DIAMETER_MAX) * 0.5 * vigor * float(g["crown_size"])
	var asym: float = float(g["crown_asymmetry"])
	var asym_vec := Vector3(cos(asym_dir), 0.0, sin(asym_dir))
	var n_primary := 3
	var max_level: int = 1 + int(round(float(g["branch_count"]) * 2.0))   # 1..3

	var hr := _resolve_height(float(c.TREE_TRUNK_HEIGHT_MAX) * vigor * float(g["trunk_height"]), slab_y, band)
	var h: float = hr[0]
	var reaches: bool = hr[1]
	# Tall trees branch above the band; short ones branch at their own mid-trunk.
	var canopy_start: float = (slab_y + band + 0.3) if reaches else (h * 0.42)

	_emit_tube(bst, Vector3.ZERO, Vector3(0, canopy_start, 0), girth, girth * 0.55, BRANCH_SIDES, Vector3.ZERO, _BIRTH_TRUNK)

	# Low Floor-3 limbs (only when there's clear room below the band).
	if reaches:
		var low_h: float = slab_y - band - 1.0
		if low_h > 1.4:
			var n_low: int = 2 + (1 if float(g["branch_count"]) > 0.5 else 0)
			for i in range(n_low):
				var lang: float = TAU * float(i) / n_low + rng.randf() * 0.6
				var lelev: float = deg_to_rad(lerpf(26.0, 44.0, rng.randf()))
				var ldir := Vector3(cos(lang) * cos(lelev), sin(lelev), sin(lang) * cos(lelev)).normalized()
				var llen: float = crown_r * lerpf(0.40, 0.65, rng.randf())
				_decid_branch(bst, fst, Vector3(0, low_h, 0), ldir, llen, girth * 0.45, 1, 1, crown_r, rng, slab_y, band, hole_r)

	# Upper crown.
	var base := Vector3(0, canopy_start, 0)
	for i in range(n_primary):
		var ang: float = TAU * float(i) / n_primary + rng.randf() * 0.5
		var elev: float = deg_to_rad(lerpf(36.0, 56.0, rng.randf()))
		var dir := Vector3(cos(ang) * cos(elev), sin(elev), sin(ang) * cos(elev)).normalized()
		var lop: float = 1.0 + asym * Vector3(cos(ang), 0.0, sin(ang)).dot(asym_vec) * 0.8
		var limb_len: float = crown_r * lerpf(0.85, 1.15, rng.randf()) * lop
		_decid_branch(bst, fst, base, dir, limb_len, girth * 0.6, 1, max_level, crown_r, rng, slab_y, band, hole_r)


static func _decid_branch(bst: SurfaceTool, fst: SurfaceTool, base: Vector3, dir: Vector3,
		length: float, radius: float, level: int, max_level: int, crown_r: float,
		rng: RandomNumberGenerator, slab_y: float, band: float, hole_r: float) -> void:
	var tip := base + dir * length
	# Anti-clipping safety net: drop any branch (and its subtree) that would land
	# in the slab band outside the hole.
	if _in_band(tip, slab_y, band, hole_r):
		return
	_emit_tube(bst, base, tip, radius, radius * 0.62, BRANCH_SIDES, base, _BIRTH_PER_LEVEL * level)
	if level >= max_level:
		var fr: float = crown_r * lerpf(0.30, 0.44, rng.randf())
		_emit_sphere(fst, tip, fr, FOLIAGE_BLOB_RINGS, FOLIAGE_BLOB_SEGS, tip, _BIRTH_FOLIAGE)
		return
	var n_child: int = 2 + (1 if rng.randf() < 0.5 else 0)
	for _j in range(n_child):
		var child_dir := _rand_cone(dir, deg_to_rad(38.0), rng)
		child_dir = (child_dir + Vector3.UP * 0.25).normalized()   # bias upward
		_decid_branch(bst, fst, tip, child_dir, length * lerpf(0.55, 0.70, rng.randf()),
				radius * 0.62, level + 1, max_level, crown_r, rng, slab_y, band, hole_r)


# Conifer (pine): a full-height leader trunk + stacked foliage tiers. Tiers sit
# ABOVE the slab band for canopy-reaching trees (bare trunk through the hole),
# or low for short trees — never in the band.
static func _gen_conifer(bst: SurfaceTool, fst: SurfaceTool, c: Node, g: Dictionary,
		rng: RandomNumberGenerator, asym_dir: float, slab_y: float, band: float, hole_r: float) -> void:
	var vigor: float = float(g["vigor"])
	var girth: float = float(c.TREE_TRUNK_RADIUS_MAX) * vigor * float(g["trunk_girth"])
	var crown_r: float = float(c.TREE_CROWN_DIAMETER_MAX) * 0.5 * vigor * float(g["crown_size"])
	var asym: float = float(g["crown_asymmetry"])

	var hr := _resolve_height(float(c.TREE_TRUNK_HEIGHT_MAX) * vigor * float(g["trunk_height"]), slab_y, band)
	var h: float = hr[0]
	var reaches: bool = hr[1]

	_emit_tube(bst, Vector3.ZERO, Vector3(0, h, 0), girth, girth * 0.22, BRANCH_SIDES, Vector3.ZERO, _BIRTH_TRUNK)

	var n_tiers: int = 3 + int(round(float(g["branch_count"]) * 3.0))   # 3..6
	var tier_start: float = (slab_y + band + 0.3) if reaches else (h * 0.22)
	var tier_top: float = h * 0.96
	if tier_top <= tier_start:
		return
	var asym_vec := Vector3(cos(asym_dir), 0.0, sin(asym_dir))
	for k in range(n_tiers):
		var f: float = float(k) / float(maxi(n_tiers - 1, 1))   # 0 bottom .. 1 top
		var ht: float = lerpf(tier_start, tier_top, f)
		var r: float = crown_r * (1.0 - f * 0.82) * lerpf(0.90, 1.05, rng.randf())
		var tier_h: float = (tier_top - tier_start) / float(n_tiers) * 1.7
		var off := asym_vec * (asym * r * 0.4)
		var apex := Vector3(0, ht, 0) + off
		if _in_band(apex, slab_y, band, hole_r):
			continue
		_emit_tube(fst, apex, Vector3(0, ht + tier_h, 0) + off,
				r, 0.0, FOLIAGE_TIER_SIDES, Vector3(0, ht, 0), lerpf(0.2, 0.8, f))


# --- Mesh emission (smooth normals + CUSTOM0 = origin.xyz, birth) --------

static func _vtx(st: SurfaceTool, origin: Vector3, birth: float, normal: Vector3, pos: Vector3) -> void:
	st.set_custom(0, Color(origin.x, origin.y, origin.z, birth))
	st.set_normal(normal)
	st.add_vertex(pos)


# Tapered tube from p0(r0) to p1(r1). r1 = 0 makes a cone. Radial normals.
static func _emit_tube(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
		sides: int, origin: Vector3, birth: float) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var tan := dir.cross(up).normalized()
	var bit := dir.cross(tan).normalized()
	for i in range(sides):
		var a0: float = TAU * float(i) / sides
		var a1: float = TAU * float(i + 1) / sides
		var d0 := tan * cos(a0) + bit * sin(a0)
		var d1 := tan * cos(a1) + bit * sin(a1)
		var v00 := p0 + d0 * r0
		var v01 := p0 + d1 * r0
		var v10 := p1 + d0 * r1
		var v11 := p1 + d1 * r1
		_vtx(st, origin, birth, d0, v00)
		_vtx(st, origin, birth, d0, v10)
		_vtx(st, origin, birth, d1, v11)
		_vtx(st, origin, birth, d0, v00)
		_vtx(st, origin, birth, d1, v11)
		_vtx(st, origin, birth, d1, v01)


# UV sphere foliage blob. Normals point out from center.
static func _emit_sphere(st: SurfaceTool, center: Vector3, radius: float, rings: int, segs: int,
		origin: Vector3, birth: float) -> void:
	for ri in range(rings):
		var lat0: float = PI * (float(ri) / rings - 0.5)
		var lat1: float = PI * (float(ri + 1) / rings - 0.5)
		var y0 := sin(lat0)
		var y1 := sin(lat1)
		var c0 := cos(lat0)
		var c1 := cos(lat1)
		for si in range(segs):
			var lon0: float = TAU * float(si) / segs
			var lon1: float = TAU * float(si + 1) / segs
			var n00 := Vector3(c0 * cos(lon0), y0, c0 * sin(lon0))
			var n01 := Vector3(c0 * cos(lon1), y0, c0 * sin(lon1))
			var n10 := Vector3(c1 * cos(lon0), y1, c1 * sin(lon0))
			var n11 := Vector3(c1 * cos(lon1), y1, c1 * sin(lon1))
			_vtx(st, origin, birth, n00, center + n00 * radius)
			_vtx(st, origin, birth, n10, center + n10 * radius)
			_vtx(st, origin, birth, n11, center + n11 * radius)
			_vtx(st, origin, birth, n00, center + n00 * radius)
			_vtx(st, origin, birth, n11, center + n11 * radius)
			_vtx(st, origin, birth, n01, center + n01 * radius)


# Random direction within `max_angle` of `dir` (cosine-uniform on the cap).
static func _rand_cone(dir: Vector3, max_angle: float, rng: RandomNumberGenerator) -> Vector3:
	var phi: float = rng.randf() * TAU
	var costheta: float = lerpf(cos(max_angle), 1.0, rng.randf())
	var sintheta: float = sqrt(maxf(1.0 - costheta * costheta, 0.0))
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var tan := dir.cross(up).normalized()
	var bit := dir.cross(tan).normalized()
	return (dir * costheta + (tan * cos(phi) + bit * sin(phi)) * sintheta).normalized()


# --- Phenotype helpers ---------------------------------------------------

# Lean tilt (radians): gene-scaled, then clamped by geometry so the trunk
# still passes through the OPEN tile gap on Floor 3 (a full plot = ±0.5*plot)
# where it crosses the slab (~STORY_HEIGHT up). Budgeting against the open tile
# rather than the cosmetic rim radius leaves far more room for visible lean.
static func _safe_lean_tilt(lean01: float, c: Node) -> float:
	var gene_tilt: float = deg_to_rad(float(c.TREE_LEAN_MAX_DEG)) * clampf(lean01, 0.0, 1.0)
	var gap_half: float = 0.5 * float(c.GARDEN_PLOT_SIZE)
	var lateral_budget: float = maxf(gap_half - float(c.TREE_TRUNK_RADIUS_MAX), 0.05)
	var cross_h: float = maxf(float(c.FLOOR_3D_STORY_HEIGHT) - float(c.FLOOR_3D_TOP_Y), 0.5)
	var geo_max: float = asin(clampf(lateral_budget / cross_h, 0.0, 1.0))
	return minf(gene_tilt, geo_max)


# Foliage colour: archetype base hue + hue_shift, with saturation/value nudged
# by crown_density (denser reads richer) and brightness by vigor (healthier
# reads lighter). HSV so shifts look natural.
static func _foliage_color(arch: Dictionary, g: Dictionary) -> Color:
	var base: Color = arch.foliage_base
	var h: float = fposmod(base.h + float(g["hue_shift"]), 1.0)
	var density: float = float(g["crown_density"])
	var vigor: float = float(g["vigor"])
	var s: float = clampf(base.s + (density - 0.7) * 0.50, 0.0, 1.0)
	var v: float = clampf(base.v + (density - 0.7) * 0.25 + (vigor - 1.0) * 0.30, 0.0, 1.0)
	return Color.from_hsv(h, s, v, 1.0)
