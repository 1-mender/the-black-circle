extends SceneTree
## Не headless: рендер двух кадров для ручной визуальной проверки.
## Снимки в .godot/ не являются исходными ресурсами проекта.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/preview_world.png")
	scene.player.position = scene.npc.position + Vector2(0, 60)
	scene.player.get_node("Camera2D").reset_smoothing()
	await physics_frame
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	scene._unhandled_input(event)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/preview_dialogue.png")
	scene.queue_free()
	await process_frame
	quit()
