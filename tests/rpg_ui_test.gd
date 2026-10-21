extends SceneTree
var checks := 0
var failures := 0
var capture := false
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle() -> void:
	for _i in range(4):
		await process_frame
	if capture:
		await RenderingServer.frame_post_draw
func inside(control: Control, viewport: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= -1 and rect.position.y >= -1 and rect.end.x <= viewport.x + 1 and rect.end.y <= viewport.y + 1
func shot(name: String) -> void:
	if capture:
		root.get_texture().get_image().save_png("res://.godot/rpg_ui_" + name + ".png")
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await settle()
	scene.world_state.rpg.fighter.hp = 37
	scene.world_state.rpg.fighter.stamina = 64
	scene.ui.refresh_rpg(scene.world_state)
	check(scene.ui.hp_bar.value == 37 and scene.ui.stamina_bar.value == 64, "Visual vitals still track real health and stamina")
	check(not scene.ui.hp_bar.show_percentage and not scene.ui.stamina_bar.show_percentage and scene.ui.vitals.find_children("*", "Label", true, false).is_empty(), "Gameplay vitals contain no permanent numeric labels")
	scene.ui.hp_bar.set_vital(22, 100)
	check(scene.ui.hp_bar.value == 22 and scene.ui.hp_bar.damage_flash > 0.0 and scene.ui.hp_bar.ghost_ratio >= scene.ui.hp_bar.display_ratio, "Damage starts flash and delayed reservoir trail")
	var displayed_before: float = scene.ui.hp_bar.display_ratio
	scene.ui.hp_bar._process(0.1)
	check(scene.ui.hp_bar.display_ratio < displayed_before, "Displayed health moves toward the real value")
	scene.ui.hp_bar.set_vital(55, 100)
	check(scene.ui.hp_bar.value == 55 and scene.ui.hp_bar.restore_flash > 0.0 and scene.ui.hp_bar.ripple_age == 0.0, "Recovery starts liquid ripple without changing the real value")
	scene.world_state.rpg.fighter.hp = 100
	scene.world_state.rpg.fighter.stamina = 100
	scene.world_state.life.clock.paused = true
	for resolution in [Vector2i(1152,720), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.content_scale_size = Vector2i.ZERO
		root.size = resolution
		await settle()
		var view := root.get_visible_rect().size
		var suffix := "%dx%d" % [resolution.x, resolution.y]
		scene.ui.refresh_rpg(scene.world_state, "Стрелок · прототип\nHP 45 / 45\nПодготовка атаки!", false)
		await settle()
		for control in [scene.ui.header, scene.ui.vitals, scene.ui.quick_panel, scene.ui.target_panel]:
			check(inside(control, view), "HUD within viewport " + suffix+" "+str(control.get_global_rect()))
		check(not scene.ui.vitals.get_global_rect().intersects(scene.ui.quick_panel.get_global_rect()), "Vitals do not overlap quick slots " + suffix)
		check(not scene.ui.header.get_global_rect().intersects(scene.ui.target_panel.get_global_rect()), "Target below header " + suffix)
		scene.economy.show_notice("Рядом опасность: ускорение отключено, скорость 1×")
		await settle()
		check(inside(scene.economy.notice, view) and not scene.economy.notice.get_global_rect().intersects(scene.ui.quick_panel.get_global_rect()), "Notification beside quick slots " + suffix)
		for control in [scene.ui.location_label, scene.time_ui.clock_button, scene.economy.balance, scene.economy.save_button, scene.economy.load_button]:
			check(not control.visible or scene.ui.header.get_global_rect().encloses(control.get_global_rect()), "Header child fits " + suffix + " " + str(control.get_class()))
		shot(suffix + "_hud")
		if capture:
			scene.world_state.rpg.fighter.hp = 32
			scene.world_state.rpg.fighter.stamina = 27
			scene.ui.refresh_rpg(scene.world_state)
			await settle()
			scene.world_state.rpg.fighter.hp = 76
			scene.world_state.rpg.fighter.stamina = 81
			scene.ui.refresh_rpg(scene.world_state)
			await process_frame
			shot(suffix + "_vitals_recovering")
			scene.world_state.rpg.fighter.hp = 100
			scene.world_state.rpg.fighter.stamina = 100
			scene.ui.refresh_rpg(scene.world_state)
		scene.time_ui.clock_button.pressed.emit()
		await settle()
		check(scene.time_ui.clock_panel.visible and inside(scene.time_ui.clock_panel, view), "Click clock opens time controls " + suffix)
		check(not scene.time_ui.clock_panel.get_global_rect().intersects(scene.ui.header.get_global_rect()), "Time controls below header " + suffix)
		shot(suffix + "_clock")
		scene.time_ui.clock_button.pressed.emit()
		scene.ui.help_panel.show()
		await settle()
		check(inside(scene.ui.help_panel, view), "Help fits " + suffix)
		scene.ui.help_panel.hide()
		scene.economy.open_inventory(scene.world_state)
		await settle()
		check(inside(scene.economy.window, view), "Inventory fits " + suffix)
		check(not scene.ui.vitals.visible or not scene.economy.window.get_global_rect().intersects(scene.ui.vitals.get_global_rect()), "Inventory above health " + suffix)
		check(not scene.economy.window.get_global_rect().intersects(scene.ui.quick_panel.get_global_rect()), "Inventory above quick slots " + suffix)
		shot(suffix + "_empty_inventory")
		scene.world_state.life.clock.paused = false
		scene._claim_kit()
		scene.world_state.life.clock.paused = true
		scene.economy.selected_item = "test_sword"
		scene.economy.refresh(scene.world_state)
		await settle()
		check(inside(scene.economy.window, view), "Equipment and item card fit " + suffix)
		check(scene.economy.window.get_global_rect().encloses(scene.economy.actions.get_global_rect()), "Item actions not clipped " + suffix)
		shot(suffix + "_equipment")
		scene.economy.close_window()
		scene.workshop.open(scene.world_state)
		await settle()
		check(inside(scene.workshop.window, view), "Workshop fits " + suffix)
		check(not scene.ui.vitals.visible or not scene.workshop.window.get_global_rect().intersects(scene.ui.vitals.get_global_rect()), "Workshop above vitals " + suffix)
		shot(suffix + "_workshop")
		scene.workshop.close()
		scene.change_location("arena", scene.Arena.SPAWN)
		scene.world_state.combat.selected_id = "melee_01"
		scene.world_state.combat.request_attack(scene.world_state, scene.world_state.combat.enemies.melee_01.position)
		scene.ui.location_label.text = scene.Arena.LOCATION_NAME
		await settle()
		check(inside(scene.ui.header, view), "Long arena location header fits " + suffix)
		check(scene.ui.target_panel.visible and inside(scene.ui.target_panel, view), "Real selected target and queued action fit " + suffix)
		shot(suffix + "_arena")
		scene.change_location("town", scene.LocationData.PLAYER_SPAWN)
		scene.time_ui.debug_enabled = true
		scene.time_ui.refresh(scene.world_state.life, "town", false)
		await settle()
		check(inside(scene.time_ui.debug_panel, view), "J debug fits " + suffix)
		check(not scene.time_ui.debug_panel.get_global_rect().intersects(scene.ui.vitals.get_global_rect()), "J debug above vitals " + suffix)
		shot(suffix + "_debug")
		scene.time_ui.debug_enabled = false
		scene.time_ui.refresh(scene.world_state.life, "town", false)
	for action in ["attack", "block", "dodge", "combat_speed", "pause_game", "quick_1", "quick_2", "quick_3", "quick_4", "inventory", "interact", "save_game", "load_game", "npc_debug"]:
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Input Map bound: " + action)
	# Actual drag/drop uses the same validation as keyboard bindings.
	var data := {"item_id": "test_heal"}
	check(scene.ui.quick_buttons[0]._can_drop_data(Vector2.ZERO, data), "Quick slot accepts item drag")
	scene.ui.quick_buttons[0]._drop_data(Vector2.ZERO, data)
	check(scene.world_state.rpg.quick[0] == "test_heal", "Drop binds existing consumable without transferring ownership")
	scene.queue_free()
	await process_frame
	print("RPG UI TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
