extends RefCounted

# Keeps Label3D nodes at constant screen-space size regardless of the
# orthographic camera's current zoom level.
#
# Why: at default ortho_size = 40 a 96 pt Label3D with pixel_size = 0.005
# reads as roughly 16 px on a 1080p display — fine zoomed in, invisible
# zoomed out. Pixel_size is in metres-per-glyph-pixel, so the on-screen
# height of a label is (font_size × pixel_size) ÷ ortho_size × screen_h.
# For constant on-screen height we need pixel_size ∝ ortho_size.
#
# Usage from a prompt-owning script's _process:
#   LabelScaler.update(_prompt_e, c.LABEL_BASE_PX_BIG, get_viewport().get_camera_3d(), c.CAMERA_ORTHO_SIZE_DEFAULT)
#
# Or for a batch of labels at the same base size:
#   LabelScaler.update_many([_prompt_e, _prompt_label, _chooser_label],
#     c.LABEL_BASE_PX_BIG, camera, c.CAMERA_ORTHO_SIZE_DEFAULT)


static func update(label: Label3D, base_pixel_size: float, camera: Camera3D, default_ortho_size: float) -> void:
	if label == null or camera == null:
		return
	var ortho: float = camera.size
	if ortho <= 0.0 or default_ortho_size <= 0.0:
		return
	label.pixel_size = base_pixel_size * (ortho / default_ortho_size)


static func update_many(labels: Array, base_pixel_size: float, camera: Camera3D, default_ortho_size: float) -> void:
	for l in labels:
		if l is Label3D:
			update(l, base_pixel_size, camera, default_ortho_size)
