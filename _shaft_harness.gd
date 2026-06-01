extends Node3D

# Verifies the shaft grate: standing over the elevator opening when the car is
# parked elsewhere should NOT drop the player down the shaft.

var _tower: Node
var _c: Node


func _ready() -> void:
	_tower = load("res://scenes/tower/tower.tscn").instantiate()
	add_child(_tower)
	_c = get_node("/root/Constants")
	await _wait(50)
	var player: Node3D = _tower.get_node("Player")
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)

	# Ground the player on Arboretum-ground (level 2) away from the shaft so the
	# tower registers current_level = 2 (and the car stays parked at the Garden).
	var lvl2_y: float = 2.0 * story + 0.3
	player.global_position = Vector3(6.0, lvl2_y, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	await _wait(40)
	print("grounded on lvl2: y=%.2f" % player.global_position.y)

	# Now step onto the shaft centre. With the grate, the player should stay on
	# this floor (~12 m); without it they'd plunge to the car/bottom (~6 m or less).
	player.global_position = Vector3(0.0, lvl2_y, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	await _wait(60)
	var y: float = player.global_position.y
	var floor_y: float = 2.0 * story
	print("over shaft after 60f: y=%.2f (floor=%.2f)  %s" % [
		y, floor_y, "HELD ✓" if absf(y - floor_y) < 0.6 else "FELL ✗"])
	get_tree().quit()


func _wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
