extends SceneTree
## Проверяет реальный цикл через сцену и кнопки UI; не трогает пользовательский слот.
## Отдельный процесс: --script res://tests/economy_test.gd -- --verify-save

const MineData = preload("res://scripts/data/mine_location.gd")
const SaveService = preload("res://scripts/simulation/save_service.gd")
const SLOT := "res://.godot/economy_test_save.json"
const MINE_SLOT := "res://.godot/economy_test_mine.json"
var failures := 0
var checks := 0
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	scene._unhandled_input(event)

func approach(point: Vector2) -> void:
	scene.player.position = point + Vector2(0, 64)
	await frames()

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	scene.player.get_node("Camera2D").reset_smoothing()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/economy_" + name + ".png")

func _verify_final() -> void:
	check(scene.world_state.location_id == "town", "Saved location restored")
	check(scene.player.position.distance_to(MineData.SMITH_POSITION + Vector2(0, 64)) < 0.1, "Exact saved position restored")
	check(scene.world_state.money == 48, "Final money restored: 48")
	check(scene.world_state.inventory.count("test_iron_ore") == 1, "Remaining iron restored: 1")
	check(scene.world_state.inventory.count("test_copper_ore") == 2, "Remaining copper restored: 2")
	check(scene.world_state.character_name == "Тестовый персонаж" and scene.player.facing_row == 2, "Character identity and facing restored")
	check(not scene.economy.window.visible and scene.player.input_enabled, "Load closes windows and unlocks player")
	check(scene.economy.balance.text.contains("48"), "HUD shows loaded money")
	for deposit_id in MineData.DEPOSITS:
		check(scene.world_state.resources[deposit_id] == 0, "Depleted resource restored: " + deposit_id)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await frames()
	if "--verify-save" in OS.get_cmdline_user_args():
		check(scene.load_game(SLOT), "Fresh process loads saved game")
		await frames()
		_verify_final()
		await _finish()
		return
	check(InputMap.action_get_events("inventory")[0].physical_keycode == KEY_I, "Inventory key I")
	check(InputMap.action_get_events("save_game")[0].physical_keycode == KEY_K, "Save key K")
	check(InputMap.action_get_events("load_game")[0].physical_keycode == KEY_L, "Load key L")
	check(scene.world_state.money == 0 and scene.world_state.inventory.items.is_empty(), "New game starts empty")
	check(not scene.load_game("res://.godot/nonexistent_slot.json"), "Missing save handled")
	action("inventory")
	check(scene.economy.window.visible and not scene.player.input_enabled, "I opens inventory and stops movement")
	check(scene.economy.rows.get_child_count() == 0, "Empty inventory shows clean slots")
	action("ui_cancel")
	check(not scene.economy.window.visible and scene.player.input_enabled, "Escape closes inventory")
	await approach(MineData.TOWN_ENTRANCE)
	action("interact")
	await frames()
	check(scene.world_state.location_id == "mine", "E enters mine from town")
	check(scene.get_node("TestMap").scene_file_path == "res://scenes/locations/mine.tscn", "Mine scene instantiated")
	check(not scene.npc.visible and scene.npc.collision_layer == 0, "Town NPC removed from mine physics")
	check(not scene.get_node("TreeCanopies").visible, "Town tree layer hidden in mine")
	check(scene.player.get_node("Camera2D").limit_right == 1152, "Camera limits match mine")
	check(not scene.can_interact(), "Town dialogue unavailable in mine")
	scene.economy.notice_time = 0.0
	scene.economy.notice.hide()
	await capture("mine")
	await approach(MineData.DEPOSITS["iron_01"]["position"])
	check(scene.interaction_target().get("id") == "iron_01", "Ore vein reachable")
	for i in range(3):
		action("interact")
	check(scene.world_state.inventory.count("test_iron_ore") == 6, "Three mining actions yield six iron")
	check(scene.world_state.resources["iron_01"] == 0, "Vein depleted")
	action("interact")
	check(scene.world_state.inventory.count("test_iron_ore") == 6, "Depleted vein cannot duplicate ore")
	await approach(MineData.DEPOSITS["iron_02"]["position"])
	action("interact")
	await approach(MineData.DEPOSITS["copper_01"]["position"])
	action("interact")
	check(scene.world_state.inventory.count("test_iron_ore") == 8 and scene.world_state.inventory.count("test_copper_ore") == 1, "Two item stacks accumulate")
	# Луч до жилы проходит сквозь центральную скалу: добыча должна блокироваться.
	scene.player.position = Vector2(580, 460)
	await frames()
	check(not scene._reachable(Vector2(580, 400), 30.0), "Mine wall blocks interaction ray")
	await approach(MineData.DEPOSITS["copper_01"]["position"])
	action("inventory")
	check(scene.economy.rows.get_child_count() == 2, "Inventory displays both item stacks")
	await capture("inventory")
	action("inventory")
	scene.world_state.character_name = "Тестовый персонаж"
	scene.player.facing_row = 3
	check(scene.save_game(MINE_SLOT), "Save inside mine writes to disk")
	var mine_position: Vector2 = scene.player.position
	scene.world_state.money = 99
	scene.world_state.inventory.remove("test_iron_ore", 8)
	scene.world_state.resources["iron_01"] = 3
	check(scene.load_game(MINE_SLOT), "Load inside mine succeeds")
	await frames()
	check(scene.world_state.money == 0 and scene.world_state.inventory.count("test_iron_ore") == 8, "Mine save restores money and inventory")
	check(scene.player.position == mine_position and scene.player.facing_row == 3, "Mine save restores position and facing")
	check(scene.world_state.resources["iron_01"] == 0 and scene.world_state.resources["iron_02"] == 1, "Mine save restores individual vein charges")
	scene.player.position = Vector2(125, 650)
	await frames()
	Input.action_press("move_left")
	await frames(20)
	Input.action_release("move_left")
	check(scene.player.position.x >= 107.9, "Mine wall blocks player")
	await approach(MineData.EXIT - Vector2(0, 128))
	# approach добавляет 64: персонаж находится на 64 пикселя севернее выхода.
	action("interact")
	await frames()
	check(scene.world_state.location_id == "town", "E returns to town")
	check(scene.npc.visible and scene.npc.collision_layer == 4, "Town NPC physics restored")
	check(scene.get_node("TestMap").get_child_count() == 19, "Original town colliders preserved")
	check(scene.get_node("TreeCanopies").visible, "Tree foreground preserved")
	await approach(MineData.SMITH_POSITION)
	action("interact")
	scene.social_ui.trade_button.pressed.emit()
	check(scene.economy.mode == "trade" and not scene.player.input_enabled, "Blacksmith opens trade window")
	check(scene.economy.rows.get_child_count() == 2, "Shop shows both accepted ores")
	await capture("trade_stock")
	var before: Dictionary = scene.world_state.to_save()
	scene.player.position = Vector2(864, 816)
	scene._sell("test_iron_ore", 1)
	check(scene.world_state.to_save() == before, "Trade request with stocked ore rejected away from merchant")
	await approach(MineData.SMITH_POSITION)
	# Список отсортирован: медь, железо. Нажимаем реальные кнопки интерфейса.
	scene.economy.rows.get_child(1).get_child(2).pressed.emit()
	check(scene.world_state.money == 5 and scene.world_state.inventory.count("test_iron_ore") == 7, "Sell-one button exchanges ore for money")
	scene.economy.rows.get_child(0).get_child(3).pressed.emit()
	check(scene.world_state.money == 8 and scene.world_state.inventory.count("test_copper_ore") == 0, "Sell-all button respects copper price")
	check(scene.economy.rows.get_child(0).get_child(2).disabled, "Empty stack sale button disabled")
	scene.economy.rows.get_child(1).get_child(3).pressed.emit()
	check(scene.world_state.money == 43 and scene.world_state.inventory.items.is_empty(), "Selling all iron empties inventory and pays exact total")
	before = scene.world_state.to_save()
	for request in [["test_iron_ore", 1], ["test_iron_ore", -1], ["unknown", 1]]:
		check(scene.world_state.sell("test_smith", request[0], request[1]) == 0, "Invalid sale rejected: " + str(request))
	check(scene.world_state.to_save() == before, "Invalid sales leave state unchanged")
	await capture("trade")
	action("ui_cancel")
	await approach(MineData.TOWN_ENTRANCE)
	action("interact")
	await frames()
	check(scene.world_state.resources["iron_01"] == 0, "Re-entering mine does not respawn ore")
	await approach(MineData.DEPOSITS["iron_02"]["position"])
	action("interact")
	await approach(MineData.DEPOSITS["copper_01"]["position"])
	action("interact")
	action("interact")
	await approach(MineData.EXIT - Vector2(0, 128))
	action("interact")
	await frames()
	await approach(MineData.SMITH_POSITION)
	action("interact")
	scene.social_ui.trade_button.pressed.emit()
	scene.economy.rows.get_child(1).get_child(2).pressed.emit()
	scene.player.facing_row = 2
	check(scene.save_game(SLOT), "Final character and world saved")
	check(scene.save_game(SLOT) and FileAccess.file_exists(SLOT + ".bak"), "Saving again preserves backup")
	# Мутация и загрузка проверяют восстановление, а не только сериализацию.
	scene.world_state.money = 999
	scene.world_state.inventory.items.clear()
	scene.world_state.resources["iron_01"] = 3
	scene.change_location("mine", MineData.SPAWN)
	check(scene.load_game(SLOT), "Load restores town from mine")
	await frames()
	_verify_final()
	before = scene.world_state.to_save()
	var corrupt := FileAccess.open("res://.godot/economy_corrupt.json", FileAccess.WRITE)
	corrupt.store_string("{bad json")
	corrupt.close()
	check(not scene.load_game("res://.godot/economy_corrupt.json"), "Corrupt JSON rejected")
	for change in [
		{"version": 99}, {"money": -1}, {"money": 1.5}, {"location": "unknown"},
		{"position": [0, 0]}, {"position": [NAN, 5]}, {"inventory": {"unknown": 1}},
		{"inventory": {"test_iron_ore": -5}}, {"resources": {}},
	]:
		var invalid: Dictionary = before.duplicate(true)
		invalid.merge(change, true)
		check(not scene.world_state.apply_save(invalid), "Invalid save data rejected: " + str(change.keys()))
	check(scene.world_state.to_save() == before, "Failed loads never partially mutate current game")
	check(not SaveService.save_game(scene.world_state, "res://.godot/no_such_directory/save.json").is_empty(), "Write failure reported")
	scene.economy.show_notice("Игра загружена · баланс и остатки ресурсов восстановлены")
	await capture("loaded")
	await _finish()

func _finish() -> void:
	scene.queue_free()
	await process_frame
	print("ECONOMY TEST FINISHED: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
