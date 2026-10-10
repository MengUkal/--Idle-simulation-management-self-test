extends Node
func _ready() -> void:
	await get_tree().process_frame
	SaveManager.set_process(false)
	GameState.paragon_points = 30
	GameState.paragon_unlocked_boards = ["p1", "p2", "p3"]
	var panel: Node = load("res://scenes/paragon/paragon_panel.gd").new()
	add_child(panel)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/cap_paragon_themed.png")
	print("[capture] saved")
	get_tree().quit()
