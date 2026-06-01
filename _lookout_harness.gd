extends Node3D

# Verifies the Sky Lounge look-out: teleports the player to a window, screenshots
# the interior (glass + sky + prompt), triggers the look-out camera, screenshots
# the exterior vantage (the placeholder cityscape), then exits and screenshots
# the ease-back. Uses the tower's OWN iso_camera (no override camera).

const SHOT_DIR := "res://_shots/lookout/"
var _tower: Node
var _c: Node
var _gs: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_tower = load("res://scenes/tower/tower.tscn").instantiate()
	add_child(_tower)
	_c = get_node("/root/Constants")
	_gs = get_node("/root/GameState")
	await _wait(50)

	var player: Node3D = _tower.get_node("Player")
	var sky: Node = _tower.get_node("Floors/SkyLounge")
	var cam: Camera3D = _tower.get_node("CameraPivot/Camera3D")
	cam.make_current()

	# Teleport onto the Sky Lounge (level 5, y≈30) just inside the +x window.
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var surface_y: float = 5.0 * float(_c.FLOOR_3D_STORY_HEIGHT) + float(_c.FLOOR_3D_TOP_Y)
	player.global_position = Vector3(half - 1.4, surface_y + 0.1, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	await _wait(45)
	print("on sky lounge: player.y=%.2f cityscape.vis=%s" % [
		player.global_position.y, str(_tower.get_node("Cityscape").visible)])
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "1_interior.png")

	# Trigger the look-out at the +x window.
	sky.call("_enter_look_out", Vector3(1, 0, 0))
	await _wait(55)
	print("looking_out=%s anchor=%s" % [str(_gs.get("looking_out")), str(_gs.get("look_out_anchor"))])
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "2_lookout.png")

	# Orbit a touch (simulate holding R) then shoot again.
	Input.action_press(&"camera_rotate_right")
	await _wait(30)
	Input.action_release(&"camera_rotate_right")
	await _wait(6)
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "3_lookout_orbited.png")

	# Exit — ease back inside.
	_gs.set("looking_out", false)
	await _wait(60)
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "4_back.png")

	get_tree().quit()


func _wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
