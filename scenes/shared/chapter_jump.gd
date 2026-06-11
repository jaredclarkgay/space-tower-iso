extends CanvasLayer

# Dev "chapter jump" overlay — an always-clickable dropdown the operator uses to
# jump straight to any narrative beat / floor from ANY state (exterior, mid-
# cinematic, in dialogue, on any floor) so they don't sit through the opener while
# iterating. UI input is independent of the frozen player input, so this works even
# while the cinematic owns the camera and the player is held.
#
# Self-contained: its own high CanvasLayer (always on top, always receives clicks),
# gated behind Constants.DEV_CHAPTER_JUMP. The chapter list is the controller's
# CHAPTERS constant (single source of truth). Selecting a row calls
# jump_to_chapter(id) on the tower_controller (reached via its group).

const _LAYER := 100

var _c: Node
var _button: Button
var _menu: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	layer = _LAYER
	_c = get_node_or_null("/root/Constants")
	if _c == null or not bool(_c.get("DEV_CHAPTER_JUMP")):
		visible = false
		return
	_build_ui()


func _build_ui() -> void:
	# Root fills the screen but is mouse-transparent except over our widgets, so it
	# never eats clicks meant for the game world.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-center column: the button, and below it the (initially hidden) menu.
	# Anchored top-center, then offset so the fixed-width column is centered. A
	# VBoxContainer sized only by its minimum size (no preset fighting the layout)
	# so its children stack downward and the dropdown is never clipped to 0 height.
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.0
	col.anchor_bottom = 0.0
	col.offset_left = -90.0
	col.offset_right = 90.0
	col.offset_top = 8.0
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_END
	col.add_theme_constant_override("separation", 4)
	root.add_child(col)

	_button = Button.new()
	_button.text = "▾ CHAPTERS"
	_button.focus_mode = Control.FOCUS_NONE   # never steal Space/Enter from gameplay
	_button.custom_minimum_size = Vector2(180.0, 26.0)
	_button.add_theme_font_size_override("font_size", 13)
	_button.pressed.connect(_toggle_menu)
	col.add_child(_button)

	_panel = PanelContainer.new()
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	sb.border_color = Color(0.35, 0.38, 0.44)
	sb.set_border_width_all(1)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	_panel.add_theme_stylebox_override("panel", sb)
	col.add_child(_panel)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	_panel.add_child(_menu)


# Build the chapter rows lazily on first open. The overlay is a CHILD of the tower
# controller node, so its _ready runs BEFORE the controller's _ready (children
# ready bottom-up) — at _ready the controller isn't in its group yet. Deferring to
# first open guarantees chapter_list() resolves.
func _ensure_menu_built() -> void:
	if _menu == null or _menu.get_child_count() > 0:
		return
	var controller: Node = get_tree().get_first_node_in_group("tower_controller")
	var chapters: Array = controller.chapter_list() if controller and controller.has_method("chapter_list") else []
	for ch in chapters:
		var b := Button.new()
		b.text = String(ch.label)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(172.0, 22.0)
		b.add_theme_font_size_override("font_size", 12)
		var id: String = String(ch.id)
		b.pressed.connect(_on_chapter.bind(id))
		_menu.add_child(b)


func _toggle_menu() -> void:
	_ensure_menu_built()
	_panel.visible = not _panel.visible


# Public so a harness can pop the menu open for a screenshot.
func set_menu_open(open: bool) -> void:
	if open:
		_ensure_menu_built()
	if _panel:
		_panel.visible = open


func _on_chapter(id: String) -> void:
	var controller: Node = get_tree().get_first_node_in_group("tower_controller")
	if controller and controller.has_method("jump_to_chapter"):
		controller.jump_to_chapter(id)
	if _panel:
		_panel.visible = false
