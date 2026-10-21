extends SceneTree
## Запуск: Godot --headless --path <project> --script res://tests/smoke_test.gd

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _press_interact(scene: Node) -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	scene._unhandled_input(event)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "Main scene loads")
	if packed == null:
		quit(1)
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	await _frames(3)
	var player = scene.player
	var npc = scene.npc
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "F5 main scene configured")
	for action in ["move_up", "move_down", "move_left", "move_right", "interact"]:
		_check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Input binding: " + action)
	_check(scene.get_node("TestMap").get_child_count() == 19, "All map colliders created")
	_check(player.get_node("Camera2D").is_current(), "Following camera active")
	_check(not scene.can_interact(), "Cannot interact at distance")
	_press_interact(scene)
	_check(not scene.social_ui.window.visible, "Distant E does not open dialogue")
	player.position = Vector2(864, 900)
	await _frames(2)
	var start: Vector2 = player.position
	Input.action_press("move_right")
	await _frames(12)
	Input.action_release("move_right")
	_check(player.position.x > start.x + 25 and absf(player.position.y - start.y) < 1, "Movement responds to input")
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _frames(2)
	_check(is_equal_approx(player.velocity.length(), player.speed), "Diagonal movement is normalized")
	Input.action_release("move_right")
	Input.action_release("move_up")
	# Левое здание начинается на x=240; ступни не должны проникать в стену.
	player.position = Vector2(180, 400)
	await _frames(2)
	Input.action_press("move_right")
	await _frames(36)
	Input.action_release("move_right")
	_check(player.position.x > 200 and player.position.x <= 228.1, "Building blocks movement")
	player.position = Vector2(70, 720)
	await _frames(2)
	Input.action_press("move_left")
	await _frames(20)
	Input.action_release("move_left")
	_check(player.position.x >= 59.9, "World boundary blocks movement")
	player.position = npc.position + Vector2(0, 60)
	await _frames(3)
	_check(scene.can_interact() and scene.ui.prompt.visible, "Nearby NPC offers interaction")
	_press_interact(scene)
	_check(scene.social_ui.window.visible and not player.input_enabled, "E opens dialogue and locks movement")
	_check(scene.world_state.npc_records[npc.npc_id]["conversations"] == 1, "Conversation updates session state")
	start = player.position
	Input.action_press("move_down")
	await _frames(8)
	Input.action_release("move_down")
	_check(player.position.distance_to(start) < 0.1, "Player stays still during dialogue")
	_press_interact(scene)
	_check(not scene.social_ui.window.visible and player.input_enabled, "E closes dialogue and restores movement")
	_press_interact(scene)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	scene._unhandled_input(escape)
	_check(not scene.social_ui.window.visible and player.input_enabled, "Escape closes dialogue")
	_check(scene.world_state.npc_records[npc.npc_id]["conversations"] == 2, "Repeated interaction retains session state")
	player.position = npc.position + Vector2(0, 50)
	await _frames(2)
	Input.action_press("move_up")
	await _frames(20)
	Input.action_release("move_up")
	_check(player.position.y >= npc.position.y + 23.9, "NPC has physical collision")
	# Между персонажами препятствие: разговор через стену недоступен.
	player.position = Vector2(220, 400)
	npc.position = Vector2(280, 400)
	await _frames(3)
	_check(not scene.can_interact(), "Obstacle blocks interaction line of sight")
	_check(not scene.ui.prompt.visible, "Interaction prompt disappears out of reach")
	scene.queue_free()
	await process_frame
	print("SMOKE TEST FINISHED: ", failures, " failures")
	quit(0 if failures == 0 else 1)
