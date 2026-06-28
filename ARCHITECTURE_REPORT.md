# Architecture Report — building a branching-fidelity scene graph on Space Tower Iso

**Purpose.** A grounding map for an engineer building a NEW "developing Polaroid"
system — a non-destructive, branching **DAG** (source node → typed operator nodes
→ forks → branches) where every element carries `fidelity: float (0→1)` and a
`source: String`, evaluated and then **baked into the live `SceneTree`**. The
graph is the representation; the SceneTree is one render of its current resolved
state.

**Method.** Code-verified against the live repo (Godot 4.6) on the date of
writing. File paths + line refs + short excerpts throughout; "does not exist" is
stated explicitly where true. **`GameDirector` is treated as known** and is only
referenced where Section 6 needs the mouth channel — it is not re-documented.

**Orientation — the five facts that shape your build:**

1. **The codebase already lives by your core philosophy.** `GameState` is pure
   data; floor controllers *render* it; on re-entry they *rebuild geometry from
   state*. "The graph is the representation, the SceneTree is one render" is the
   existing idiom — your DAG is a new pure-data structure that fits it. (§1, §7)
2. **The genome is NOT your substrate.** It's a flat 12-scalar dict, not a node
   graph — no per-node metadata, no operators, no branching. You need a **new DAG
   layer alongside it**, but you should mirror its storage + evaluate-to-geometry
   idiom. (§2)
3. **There is no build-job pipeline and no in-game LLM.** Construction is direct
   imperative; the only AI is a dev-time hook. Both are greenfield you'll author,
   conforming to the autoload/GL/web constraints. (§3, §5)
4. **Hot-swapping a region of the live scene is an ESTABLISHED pattern.** Baking
   in `_ready()` then mutating `.visible` / material alpha / shader params / node
   surgery is how the whole game already works. Your bake-graph-into-SceneTree is
   not novel here. (§4, §7)
5. **GL Compatibility has no compositor** → no screen-space outlines. Every
   highlight is direct material emission. Per-object highlighting is doable but
   must be emissive-mesh/material, not post-process. (§6, §8)

---

## 1. GameState — the pure-data world model

**File:** `autoloads/game_state.gd`. **All world state is plain `var` + `Dictionary`
on the autoload — zero `Resource`/`class_name` types.** This is the single source
of truth that the iso scene renders.

Granularity is mixed: scalars (`food_count: int`, `cash: int`, `phase: int`,
`interiors_unlocked: bool`), scalar-backed structs (`player`, `camera`), per-key
dicts (`seed_pouch`, `dispenser_stock`, `utility`), and **per-entity collections
keyed by string grid-coords**. The two structured shapes you'll most want to copy:

```gdscript
# per-floor lifecycle (garden + any floor via floor_life)
var garden := { "populated": 0, "alive": false, "placed": [] as Array }   # L245
var floor_life := {}                                                       # id -> same shape

# per-entity collection: trees keyed by "ix,iz", each holds its own genome
var arboretum := { "water_connected": false, "sunlight_active": false,
                   "trees": {}, "next_variety": 0 }                        # L311
```

**Accessor helpers (the convention to follow):** state is reached through small
typed methods, not raw field pokes:

```gdscript
func floor_state(id: String) -> Dictionary        # L259  (lazily creates floor_life[id])
func floor_alive(id: String) -> bool              # L273
func garden_alive() -> bool                       # L278
func utilities_all_active() -> bool               # L283
```

**Sim clock:** `sim_time_msec` advances in `_process` (`L331`) scaled by
`sim_speed` — a monotonic in-world clock distinct from engine time. Growth and any
time-based fidelity progression should read this, not `Time`.

**Where the fidelity scene-graph should live.** Follow the `arboretum.trees`
precedent: a **new top-level dict on `GameState`** (e.g. `var polaroid := {}` or a
per-entity `"graph": {...}` field inside an entity's dict, keyed like trees).
Reasons: (a) it is pure data, matching the "GameState renders to SceneTree"
contract; (b) it persists across floor swaps for free (like `arboretum.trees`);
(c) it stays out of the genome (§2). Do **not** invent a `Resource` subclass just
for this unless you need editor authoring — the codebase's entire idiom is
plain-dict state + deterministic rebuild, and a `class_name Resource` would be the
first of its kind (see §8 `class_name` caveat). A dict-of-nodes DAG (`{node_id:
{type, inputs:[ids], fidelity, source, params}}`) is the idiomatic fit.

---

## 2. The genome system — and the verdict

**File:** `scenes/shared/arboretum_tree.gd`. The genome is the closest thing in the
repo to "an element carrying evolvable parameters," so it's the natural thing to
ask about — but structurally it is **not** what you need.

**What it actually is:** a flat `Dictionary<String, float>` of **exactly 12 named
scalar genes**, sampled once at planting from per-gene Gaussian bounds:

```gdscript
const GENE_BOUNDS := {                              # L32
    "vigor": Vector2(0.7,1.3), "trunk_height": Vector2(0.6,1.4),
    "trunk_girth": Vector2(0.6,1.4), "crown_size": Vector2(0.6,1.4),
    "crown_density": Vector2(0.3,1.0), "crown_asymmetry": Vector2(0.0,0.6),
    "lean": Vector2(0.0,1.0), "branch_count": Vector2(0.0,1.0),
    "hue_shift": Vector2(-0.08,0.08), "o2_efficiency": Vector2(0.6,1.4),
    "maturation_rate": Vector2(0.7,1.3), "senescence_onset": Vector2(0.7,1.0),
}
```

It's created by `make_founder_genome(variety, rng_seed)` (`L107`) — each gene an
independent clamped Gaussian draw — stored at `GameState.arboretum.trees[key].genome`,
and consumed **once** by `build()` (`L219`) → `_gen_deciduous()` / `_gen_conifer()`
(`L376`/`L456`), which read genes as **multipliers/offsets** on geometry params and
commit two immutable `SurfaceTool` meshes. After build, growth is a single
`growth_t` (0→1) pushed to a vertex shader uniform (`update()`, ~`L289`) — **the
genome is never re-read**.

**Verdict — NOT a viable substrate; build a new DAG layer alongside it.**
The genome is a flat parameter vector: no graph edges, no nesting, no per-gene
`source`/`fidelity`, no operator nodes, no branching, and a one-pass bake. Every
property your Polaroid needs (typed operator nodes, one node receiving multiple
modifiers, forking into branches, per-node fidelity+source, selective/staged
re-evaluation) is absent and cannot be retrofitted onto a `{string: float}` dict
without becoming a different structure. **Conclusion:** add a parallel
`graph`/`genome_dag` layer (stored like §1 suggests) that models nodes + edges +
fidelity + source, and **emits a flat parameter set as its resolved leaf** — i.e.
the existing genome becomes one possible *output* of evaluating your DAG, and the
proven `build()`→mesh path stays the renderer. You reuse the evaluation idiom; you
do not reuse the genome's shape.

---

## 3. The build / place path (and the absent job pipeline)

**Geometry is 100% programmatic.** Builders live in `scenes/shared/floor_chrome.gd`
(static `build_slab/walls/elevator_core/...`) using `BoxMesh`/`CylinderMesh`/
`SphereMesh`/`ArrayMesh` + `StandardMaterial3D`/`ShaderMaterial`, parented via
`MeshInstance3D.new()` + `add_child`. No imported meshes anywhere (§4).

**How new content enters the live scene at runtime** — two patterns:

```gdscript
# (a) placement spawn callback — floor_lifecycle.place() delegates to the floor:
_cfg.spawn_component.call(anchor)                 # floor_lifecycle.gd ~L103
# Garden's impl builds + adds + tweens in:
func _spawn_planter_bed(anchor): ... bed.add_child(soil); add_child(bed)
     create_tween().tween_property(bed, "scale", ...)   # iso_floor.gd ~L715-750

# (b) floor raising in construction — geometry pre-built in _ready(), revealed by tween:
node.position.y = base_y - CONSTRUCT_RISE_DROP
create_tween().tween_property(node, "position:y", base_y, CONSTRUCT_RISE_DUR)  # tower_controller.gd ~L578
```

**There is NO build-job abstraction** — no job object, no payload schema, no
validation stage, no async queue. Every build is a direct function call at the
site. **This is greenfield for you.** A "developing Polaroid" that resolves
elements over time (and possibly from async/LLM output, §5) will want exactly the
thing that's missing: a job = `{target_node_id, operator, params, fidelity,
source}` → validate → apply → bake. Build it as its own module (e.g.
`scenes/shared/scene_build_queue.gd`), and have it call the same imperative
spawn/mesh primitives the floors already use, so output is consistent with
hand-built geometry.

---

## 4. Runtime assets + hot-swap — established, in your favor

**Creation:** all primitives + materials in code; **no `load()`/`preload()` of any
3D asset** (`.glb/.tres/.obj/.png`) exists — `preload` is used only for GDScript
modules. No LOD, no streaming.

**Hot-swap is the house style** (this is the key enabler for "bake the graph into
the SceneTree, re-bake on change"):

```gdscript
# live material alpha + mesh visibility swap (canopy glass)
_slab_mat.albedo_color.a = alpha; _tiles_node.visible = alpha > 0.01   # arboretum_canopy.gd ~L124
# live shader-param region glow (ceiling ping / wall bump) — set per frame
# floor visibility + collision gating per current floor
node.set_structure_visible(built); slab.collision_layer = 2 if at_or_below else 0  # tower_controller.gd ~L506-509
# light energy easing during a floor "bloom"
light.light_energy = pulse                                            # iso_floor.gd ~L98
```

**Verdict — replacing/regenerating a live region is NOT novel.** The established
recipe is: build static geometry in `_ready()`, then mutate `.visible`, material
alpha/`material_override`, shader uniforms, collision layers, or do node surgery
(`add_child`/`queue_free`/reparent) on state change. Your fidelity re-bake (swap a
low-fidelity subtree for a higher-fidelity one when a node resolves) follows this
directly. Note the one caveat the code reveals: the ghost preview re-instantiates a
`MeshInstance3D` and just **hides** the old one rather than freeing it (floor_lifecycle)
— prefer `queue_free` of replaced subtrees to avoid leak accumulation in a system
that re-bakes often.

---

## 5. LLM integration — does not exist (in-game)

**No runtime model calls anywhere** in `scenes/` or `autoloads/` — no
`HTTPRequest`, no API/model code (grep-verified empty). The game is fully
deterministic and offline.

The only AI is **dev-time**: `agent/capture_session.sh` backgrounds a **headless
Claude** on `SessionEnd`/`PreCompact` to distill takeaways into `agent/`. It is
off the game's critical path and never runs in-session. Do not mistake it for a
gameplay hook.

**If you add in-game model calls,** they must conform to: (a) an **autoload**
owning an `HTTPRequest` (persistent across scene loads — the autoloads are the
only globals, §8); (b) **GL Compatibility + web export** — assume no persistent
sockets, make every request stateless + timeout-guarded; (c) **GDScript only**, no
plugins; (d) a **deterministic local fallback** for every call (the game must stay
playable offline). Map model output onto **GameState writes / DAG-node mutations**,
never directly into ad-hoc scene pokes — route it through the build queue (§3) so
generated content is validated and baked the same way as everything else, and so a
fork/divergence (your core mechanic) is just another node with `source:"llm"` and a
`fidelity` value.

---

## 6. Interaction, highlights, and the (missing) environment mouth

**Targeting = nearest-in-radius, Y-gated, priority-ordered. No raycast / click-pick.**
`scenes/garden/iso_player.gd` (~`L399`) scans candidates in fixed priority
(dispenser > robot > tubes > plots), each exposing:

```gdscript
func is_interactable_at(player_world_pos, radius) -> bool:
    var in_range = global_position.distance_to(player_world_pos) <= radius
    var on_floor = absf(player_world_pos.y - global_position.y) < 3.0   # blocks cross-floor
    return in_range                                                     # iso_dispenser.gd ~L85
```

`[E]` prompts are `Label3D` billboards kept readable across zoom by
`scenes/shared/label_scaler.gd` (scales `pixel_size ∝ ortho_size`). **For a
tappable Polaroid element you will likely need true picking** (a camera-ray to a
collider, or a per-element interact-radius) — the nearest-in-radius model works for
sparse fixed props but not for picking one of many arbitrary graph-elements.
Adding a raycast picker is novel but small.

**Highlights are all ad-hoc emissive — there is NO reusable helper.** Examples:
the dispenser selection frame (an emissive `BoxMesh` overlay pulsed via
`emission_energy_multiplier`, `iso_dispenser.gd ~L347`), Cody's LED, spine-pipe
fills, and the placement **ghost** (translucent unshaded `BoxMesh`,
`floor_lifecycle.gd ~L69`). **GL Compatibility has no compositor**, so screen-space
outline/silhouette passes are unavailable (§8). A reusable
`highlight(node, color, style)` that attaches/tween an emissive overlay (the
dispenser-frame approach) would be genuinely new and is the right primitive for
"surface a divergence on this element."

**The environment is NOT a mouth.** Only two mouths register:

```gdscript
gd.register_mouth(self, 10)   # Cody  (iso_robot.gd L101)
gd.register_mouth(self, 0)    # HUD   (tower_hud.gd L128)
```

`tower_controller` **polls** `GameDirector.current_phase` and GameState each frame
(it does not even connect `phase_changed`), and owns reactive effects
(`_ceiling_pulse`, `_wall_pulse` decays → calls `set_ceiling_ping()` etc.). So the
mouth channel today is **narrative-only**. Your idea — *register an "environment
mouth" that draws a glowing highlight on a specific object and makes it tappable* —
is a clean fit but **net-new**: implement a node with `mouth_id` +
`deliver_directive(d)` (so the Director can say "surface divergence on element X"),
register it at a priority between Cody (10) and HUD (0), and have it own (a) the
reusable highlight overlay above and (b) registration of that element as a pick
target. This is the single most leveraged new seam for the Polaroid's
"divergences are surfaced, not auto-corrected" requirement.

---

## 7. Baking / caching — the pattern you'll reuse wholesale

The repo's universal pattern is **state in `GameState` → geometry rebuilt from
state on demand**, which is exactly "graph is representation, SceneTree is one
render":

```gdscript
# placed components cached as data, then re-rendered:
st.placed.append({"type": component_type, "coord": anchor})            # floor_lifecycle.gd ~L106
# trees: genome persists; geometry re-baked on floor re-entry:
for key in _gs.arboretum.trees:
    _tree_refs[key] = ArboretumTree.build(self, _c, tree, world_pos)   # arboretum_ground.gd ~L248
# utility pipe fills tagged into a group, visibility driven from state each frame
fill.add_to_group("passive_spine_fill")                                # floor_chrome.gd ~L530
```

Two reusable moves for you: (1) keep a per-entity **refs cache** (like
`_tree_refs`) mapping `graph_node_id → {root, meshes, mats}` so a re-bake can
`queue_free` the old subtree and rebuild only the changed branch; (2) make
evaluation **deterministic from stored data + a seed** (trees use `rng_seed`) so a
baked render is reproducible and a fork is just a new seed/branch in the data.

---

## 8. Constraints — and what makes the hard parts hard

- **Godot 4.6, GDScript only.** No C#, no GDExtension, no plugins.
- **Renderer: GL Compatibility** (`project.godot`: `("4.6","GL Compatibility")`).
  **Web export must remain possible.**
- **The 7 autoloads are the only globals** (in load order): `Constants`,
  `GameState`, `SaveManager`, `AudioManager`, `GameDirector`, `TimeOfDay`,
  `Telemetry`. A new persistent subsystem (build queue, LLM client, the DAG store
  if you don't hang it on GameState) should be an 8th autoload, registered in
  `project.godot`.
- **`class_name` caveat:** see `agent/rules/gdscript_class_name_caveats.md` — the
  repo prefers `preload` over global `class_name` for the headless-import harness.
  Prefer plain dicts + `preload`'d helper scripts over new `class_name Resource`
  types.
- **Verify visually with the windowed screenshot harness** (`agent/rules/godot_screenshot_harness.md`),
  never `--headless`, for anything rendered.

**Hard flags for this project specifically:**

| Want | Constraint | Consequence |
|---|---|---|
| Per-object **outline/highlight** | GL Compatibility → **no compositor / screen-space passes** | Must use **emissive overlay mesh or material emission** per object (the dispenser-frame pattern). A reusable highlight helper is new work. |
| **Tappable** arbitrary graph element | Interaction is nearest-in-radius, **no picking** | Add a raycast/collider picker; the radius model won't disambiguate many elements. |
| **Runtime geometry swap** of a fidelity region | No morph targets / shader blend assets; programmatic only | Use the established hot-swap recipe (build in `_ready`/on-demand, then `.visible`/material/queue_free node surgery). Feasible — already the norm. |
| **LLM-driven** content | No in-game net layer; web-export + offline | New autoload `HTTPRequest`, stateless+timeout, **deterministic fallback required**. |
| A **DAG store** | All state is plain dict on autoloads | Store as a dict (on GameState or an 8th autoload), not a `Resource`, to match idiom. |

---

## Where the new system plugs in (synthesis)

1. **DAG store** — new pure-data structure (dict of typed nodes with
   `inputs[]`, `fidelity`, `source`, `params`), on `GameState` or an 8th autoload,
   persisted/rebuilt like `arboretum.trees`. (§1, §2, §7)
2. **Evaluator** — resolves the DAG to a flat parameter set per element (the
   genome becomes one *output* of this, not the substrate). Deterministic from
   data + seed. (§2, §7)
3. **Build queue** — the missing job pipeline: `{target, operator, params,
   fidelity, source}` → validate → apply via the existing imperative mesh
   primitives → bake; the channel through which both player forks and LLM output
   mutate the scene. (§3, §5)
4. **Re-bake** — on a node resolving to higher fidelity, `queue_free` the old
   subtree and rebuild that branch only, using a refs cache. Established pattern.
   (§4, §7)
5. **Environment mouth + highlight helper** — a registered mouth (priority 0–10)
   that draws an emissive highlight on a divergent element and makes it pickable,
   so the Director can "surface divergence, not auto-correct." Net-new but clean.
   (§6)
6. **Optional LLM autoload** — stateless, fallback-guarded, output routed through
   the build queue as `source:"llm"` nodes. (§5)

The throughline: the engine already separates *truth (data)* from *render
(SceneTree)* and already hot-swaps regions — so your branching, non-destructive,
re-bakeable graph is **with the grain**. The two things genuinely missing are a
**build-job pipeline** and a **pickable/highlightable environment mouth**; the
genome is a near-miss you should sit *beside*, not on top of.
