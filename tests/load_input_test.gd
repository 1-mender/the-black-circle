extends SceneTree
## Проверка настоящих событий клавиатуры и кнопок, включая движение после загрузки.

const SLOT := "res://.godot/load_input_test.json"
var failures := 0
var checks := 0
var scene: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code)
	key(code, false)
	await frames()

func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.save_path = SLOT
	await frames()
	for action in ["save_game", "load_game"]:
		for event in InputMap.action_get_events(action):
			check(event.physical_keycode not in [KEY_F6, KEY_F9], "No editor shortcut conflict: " + action)
	scene.player.position = Vector2(864, 900)
	scene.world_state.money = 17
	await tap(KEY_K)
	check(FileAccess.file_exists(SLOT), "Physical K saves game")
	for mode in ["world", "inventory", "dialogue", "trade", "mine"]:
		scene.close_windows()
		if mode == "inventory":
			await tap(KEY_I)
		elif mode == "dialogue":
			scene.player.position = scene.npc.position + Vector2(0, 60)
			await frames()
			await tap(KEY_E)
		elif mode == "trade":
			scene.player.position = scene.smith.position + Vector2(0, 60)
			await frames()
			await tap(KEY_E)
			scene.social_ui.trade_button.pressed.emit()
		elif mode == "mine":
			scene.change_location("mine", Vector2(576, 696))
		scene.world_state.money = 99
		await tap(KEY_L)
		check(scene.world_state.money == 17 and scene.world_state.location_id == "town", "Physical L restores saved state from " + mode)
		check(not paused and scene.player.input_enabled and not scene.economy.window.visible and not scene.social_ui.window.visible, "No pause or modal input lock after loading from " + mode)
		var start: Vector2 = scene.player.position
		key(KEY_D)
		await frames(12)
		key(KEY_D, false)
		check(scene.player.position.x > start.x + 25, "Physical D moves after loading from " + mode)
		await tap(KEY_I)
		check(scene.economy.window.visible, "Inventory responds after loading from " + mode)
		await tap(KEY_ESCAPE)
		check(not scene.economy.window.visible, "Escape responds after loading from " + mode)
	scene.world_state.money = 23
	scene.economy.save_button.pressed.emit()
	scene.world_state.money = 99
	scene.economy.load_button.pressed.emit()
	await frames()
	check(scene.world_state.money == 23, "HUD buttons save and load")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/load_controls.png")
	scene.queue_free()
	await process_frame
	print("LOAD INPUT TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
