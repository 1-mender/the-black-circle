extends "res://tests/conversation_test.gd"
const Prefs=preload("res://scripts/ui/interface_preferences.gd")
func press(action: String) -> void:
	var key:=InputEventAction.new()
	key.action=action
	key.pressed=true
	Input.parse_input_event(key)
	await settle()
	key=InputEventAction.new()
	key.action=action
	key.pressed=false
	Input.parse_input_event(key)
func press_key(code: Key) -> void:
	var key:=InputEventKey.new()
	key.physical_keycode=code
	key.keycode=code
	key.pressed=true
	Input.parse_input_event(key)
	await settle()
	key.pressed=false
	Input.parse_input_event(key)
func click(control: Control) -> void:
	await settle()
	if DisplayServer.get_name()=="headless":
		if control is CheckButton:
			control.button_pressed=not control.button_pressed
		else:
			control.pressed.emit()
		await settle()
		return
	var point:=control.get_global_rect().get_center()
	var move:=InputEventMouseMotion.new()
	move.position=point
	move.global_position=point
	Input.parse_input_event(move)
	await settle()
	var down:=InputEventMouseButton.new()
	down.position=point
	down.global_position=point
	down.button_index=MOUSE_BUTTON_LEFT
	down.pressed=true
	Input.parse_input_event(down)
	await settle()
	var up:=InputEventMouseButton.new()
	up.position=point
	up.global_position=point
	up.button_index=MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)
	await settle()
func run() -> void:
	var pref:=Prefs.new()
	pref.path="res://.godot/minimal_menu_preferences.cfg"
	pref.set_volume(1.0)
	pref.set_fullscreen(false)
	check(pref.set_interaction(true)==OK,"Tests write preferences only to an isolated workspace file")
	pref.set_fullscreen(true)
	var check_fullscreen:=Prefs.new()
	check_fullscreen.path=pref.path
	check_fullscreen.load_settings()
	check(check_fullscreen.fullscreen,"Display mode persists in independent interface settings")
	pref.set_fullscreen(false)
	var scene=load("res://scenes/main.tscn").instantiate()
	scene.preferences_path=pref.path
	scene.save_path="res://.godot/minimal_menu_save.json"
	root.add_child(scene)
	stage=scene
	await settle()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	check(scene.ui.quick_buttons.all(func(b:Button):return b.text.is_empty()),"HUD quick icons have no permanent numbers or captions")
	check(scene.ui.quick_buttons.all(func(b:Button):return not b.tooltip_text.is_empty()),"Names and bindings remain available on hover")
	check(not scene.city_button.visible and not scene.economy.save_button.visible and not scene.economy.load_button.visible,"Legacy HUD menu shortcuts are hidden")
	check(scene.economy.balance.text==str(scene.world_state.money),"Currency label contains just the amount")
	check(scene.get_node("TownMarkers").get_children().all(func(n:Node):return not n is Label or not n.visible),"Town has no permanent technical text markers")
	await click(scene.ui.menu_button)
	check(scene.menu_session and scene.game_menu.window.visible and scene.world_state.life.clock.paused,"HUD menu button opens the real menu and pauses the common clock")
	if not scene.menu_session:
		print("MENU CLICK DIAGNOSTIC: viewport=",root.size," button=",scene.ui.menu_button.get_global_rect()," hovered=",root.gui_get_hovered_control())
		quit(1)
		return
	var paused: Dictionary=scene.world_state.to_save()
	scene._physics_process(0.5)
	await settle()
	check(scene.world_state.to_save()==paused,"Open menu stops NPCs, economy, clock and combat")
	await press("pause_game")
	check(scene.world_state.life.clock.paused,"Space cannot accidentally resume behind the menu")
	check(scene.game_menu.buttons.size()==8,"Pause menu exposes all eight requested entries")
	await click(scene.game_menu.buttons["inventory"])
	await settle()
	check(scene.economy.window.visible and not scene.game_menu.window.visible and not scene.world_state.life.clock.paused and not scene.player.input_enabled,"Menu inventory opens usable items while the player remains in the window")
	scene.world_state.rpg.claim_kit(scene.world_state.economy)
	scene.economy.refresh(scene.world_state)
	scene.economy.inventory_view.select_item("test_sword","main_hand")
	await click(scene.economy.inventory_view.primary)
	check(scene.world_state.rpg.equipment.main_hand.is_empty() and scene.world_state.inventory.count("test_sword")==1,"Inventory from menu can remove equipment through the existing ledger")
	scene.economy.inventory_view.select_item("test_sword")
	await click(scene.economy.inventory_view.primary)
	check(scene.world_state.rpg.equipment.main_hand=="test_sword" and scene.world_state.inventory.count("test_sword")==0,"Inventory from menu can equip without duplicating an item")
	scene.world_state.rpg.fighter.hp=40
	var menu_heals:int=scene.world_state.inventory.count("test_heal")
	scene.economy.inventory_view.select_item("test_heal")
	await click(scene.economy.inventory_view.primary)
	check(scene.world_state.rpg.fighter.hp>40 and scene.world_state.inventory.count("test_heal")==menu_heals-1,"Inventory from menu can use a real healing item")
	await press_key(KEY_1)
	check(scene.world_state.rpg.quick[0]=="test_heal" and scene.world_state.rpg.fighter.hp<=80,"Inventory 1–4 binds an item rather than firing its combat action")
	scene._bind_quick(0,"attack")
	var search: LineEdit=scene.economy.inventory_view.search
	search.grab_focus()
	var letter:=InputEventKey.new()
	letter.physical_keycode=KEY_I
	letter.keycode=KEY_I
	letter.unicode=105
	letter.pressed=true
	Input.parse_input_event(letter)
	await settle()
	check(scene.economy.window.visible and search.text=="i","Inventory search consumes typed shortcut letters instead of closing the window")
	search.clear()
	await press("ui_cancel")
	check(scene.game_menu.window.visible and not scene.economy.window.visible and scene.menu_session and scene.world_state.life.clock.paused,"Esc restores menu pause after using inventory")
	scene._menu_action("inventory")
	await click(scene.ui.menu_button)
	await settle()
	check(scene.game_menu.window.visible and not scene.economy.window.visible and scene.world_state.life.clock.paused,"HUD menu button returns from inventory to the owning menu")
	await click(scene.game_menu.buttons["journal"])
	check(scene.social_ui.window.visible and scene.world_state.life.clock.paused,"Clicking Journal opens the real journal from the menu")
	await press("ui_cancel")
	await click(scene.game_menu.buttons["skills"])
	check(scene.skill_ui.window.visible and scene.world_state.life.clock.paused,"Clicking Character opens existing skills from the menu")
	await press("ui_cancel")
	await click(scene.game_menu.buttons["resume"])
	check(not scene.menu_session and not scene.world_state.life.clock.paused and scene.player.input_enabled,"Clicking Continue resumes the original running state and player input")
	scene.world_state.life.clock.paused=true
	scene._open_game_menu()
	scene._menu_action("inventory")
	check(scene.world_state.life.clock.paused,"An earlier tactical pause remains active in menu inventory")
	await press("ui_cancel")
	scene._menu_action("resume")
	check(scene.world_state.life.clock.paused,"An existing tactical pause survives nested menu windows")
	scene.world_state.life.clock.paused=false
	scene._open_game_menu()
	await click(scene.game_menu.buttons["settings"])
	check(scene.game_menu.page=="settings","Clicking Settings opens the real settings page")
	if scene.game_menu.page!="settings":
		print("SETTINGS CLICK DIAGNOSTIC: page=",scene.game_menu.page," menu=",scene.game_menu.window.visible," button=",scene.game_menu.buttons.get("settings")," hovered=",root.gui_get_hovered_control())
		quit(1)
		return
	await click(scene.game_menu.toggle)
	await settle()
	scene.game_menu.volume_slider.value=35.0
	await settle()
	var reload_pref:=Prefs.new()
	reload_pref.path=pref.path
	reload_pref.load_settings()
	check(not reload_pref.show_interaction and not scene.preferences.show_interaction,"Interaction preference persists without altering game save data")
	check(is_equal_approx(reload_pref.master_volume,0.35) and is_equal_approx(AudioServer.get_bus_volume_db(0),linear_to_db(0.35)),"Volume setting persists and changes the real master audio bus")
	await click(scene.game_menu.buttons["controls"])
	check(scene.game_menu.binding_text("inventory").contains("I") and scene.game_menu.binding_text("quick_1").contains("1"),"Controls page reads actual Input Map bindings")
	await press("ui_cancel")
	check(scene.game_menu.page=="settings" and scene.world_state.life.clock.paused,"Esc from controls navigates back without releasing pause")
	await press("ui_cancel")
	check(scene.game_menu.page=="pause","Esc from settings returns to pause menu")
	await click(scene.game_menu.buttons["main"])
	check(scene.game_menu.page=="confirm","Unsaved game requires confirmation before title screen")
	await click(scene.game_menu.buttons["back"])
	check(scene.game_menu.page=="pause","Cancelling title confirmation retains the game menu")
	await click(scene.game_menu.buttons["save"])
	var disk: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene.save_path))
	check(disk is Dictionary and not disk.life.clock.paused and scene.world_state.life.clock.paused,"Saving from menu serializes the original clock state, not the temporary menu pause")
	var saved_heals:int=scene.world_state.inventory.count("test_heal")
	var saved_sword:String=scene.world_state.rpg.equipment.main_hand
	await click(scene.game_menu.buttons["main"])
	check(scene.game_menu.page=="title","Unchanged saved state can go to title without a spurious prompt")
	var retained: Dictionary=scene.world_state.to_save()
	await settle()
	check(scene.world_state.to_save()==retained,"Title screen retains current character and world in memory")
	scene._menu_action("resume")
	scene.world_state.money+=7
	scene._open_game_menu()
	scene._menu_action("main")
	check(scene.game_menu.page=="confirm","Real changes after saving restore the unsaved-state confirmation")
	var money: int=scene.world_state.money
	scene._menu_action("title")
	scene._menu_action("resume")
	check(scene.world_state.money==money,"Going to title without saving never deletes current data")
	scene._open_game_menu()
	check(not scene.load_game("res://.godot/no_such_minimal_save.json") and scene.menu_session and scene.world_state.life.clock.paused,"Failed load keeps menu pause and current world")
	await click(scene.game_menu.buttons["load"])
	await settle()
	check(not scene.menu_session and not scene.world_state.life.clock.paused and not scene.game_menu.window.visible,"L restores saved pause state and exits menu ownership")
	check(scene.world_state.money==int(disk.money),"Menu loading uses the existing saved inventory and economy")
	check(scene.world_state.inventory.count("test_heal")==saved_heals and scene.world_state.rpg.equipment.main_hand==saved_sword,"Menu save and load restore items consumed or equipped from its inventory")
	approach(scene.world_state,"test_recluse")
	scene.player.position=scene.world_state.player_position
	scene._sync_residents(0,true)
	await settle()
	check(not scene.ui.prompt.visible,"Disabling E hints removes the prompt near an accessible resident")
	scene.preferences.set_interaction(true)
	await settle()
	check(scene.ui.prompt.visible and scene.ui.prompt.text.length()<45,"Enabled E hint is short and contextual")
	scene.change_location("arena",Vector2(720,480))
	scene.world_state.rpg.claim_kit(scene.world_state.economy)
	scene.world_state.combat.selected_id=""
	scene.world_state.rpg.fighter.facing=Vector2.LEFT
	await press("quick_1")
	check(scene.world_state.rpg.fighter.attack_elapsed>=0 and scene.world_state.rpg.fighter.facing.x<0,"Keyboard attack follows facing without needing mouse aim")
	check(scene.ui.quick_buttons[0].feedback_success and scene.ui.quick_buttons[0].feedback_kind=="attack","Accepted keyboard attack starts its own slot animation")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/quick_attack_feedback.png")
	await press("quick_1")
	check(not scene.ui.quick_buttons[0].feedback_success and scene.ui.quick_buttons[0].feedback_kind=="attack","Rejected attack uses subdued feedback instead of a success flash")
	await settle()
	check(scene.ui.quick_buttons[0].disabled and scene.ui.quick_buttons[0].cooldown_fraction>0,"Attacking displays cooldown overlay and inactive icon")
	scene.world_state.rpg.fighter=scene.world_state.rpg.new_fighter(scene.player.position)
	scene.world_state.rpg.fighter.facing=Vector2.LEFT
	await press("quick_2")
	check(scene.world_state.rpg.fighter.block_left>0,"Keyboard block still uses the existing combat action")
	check(scene.ui.quick_buttons[1].feedback_success and scene.ui.quick_buttons[1].feedback_kind=="block","Block starts shield-ring feedback")
	scene.ui.quick_buttons[1].feedback_age=0.2
	await click(scene.ui.quick_buttons[1])
	check(scene.ui.quick_buttons[1].feedback_success and scene.ui.quick_buttons[1].feedback_age<0.2,"Mouse click restarts the same block animation as its hotkey")
	scene._physics_process(0.001)
	check(scene.world_state.rpg.fighter.blocking and scene.world_state.rpg.fighter.facing.x<0,"Keyboard block preserves facing instead of following the mouse cursor")
	await press("quick_3")
	check(scene.world_state.rpg.fighter.dodge_left>0 and scene.world_state.rpg.fighter.stamina<100,"Keyboard dodge uses real stamina and cooldown")
	check(scene.ui.quick_buttons[2].feedback_success and scene.ui.quick_buttons[2].feedback_kind=="dodge","Dodge starts movement-streak feedback")
	scene.world_state.rpg.fighter.hp=40
	var heals: int=scene.world_state.inventory.count("test_heal")
	await press("quick_4")
	check(scene.world_state.rpg.fighter.hp>40 and scene.world_state.inventory.count("test_heal")==heals-1,"Keyboard healing consumes a real item")
	check(scene.ui.quick_buttons[3].feedback_success and scene.ui.quick_buttons[3].feedback_kind=="heal","Consumed healing item starts rising-drop feedback")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/quick_heal_feedback.png")
	await press("quick_4")
	check(not scene.ui.quick_buttons[3].feedback_success and scene.world_state.inventory.count("test_heal")==heals-1,"Unavailable healing neither flashes as successful nor consumes another item")
	check(scene.ui.quick_buttons[3].cooldown_fraction>0,"Healing cooldown has a visual indicator")
	for resolution in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=resolution
		root.size=resolution
		scene.change_location("town",scene.LocationData.PLAYER_SPAWN)
		scene.world_state.rpg.fighter=scene.world_state.rpg.new_fighter(scene.player.position)
		scene.economy.notice_time=0
		scene.economy.notice.hide()
		scene.ui.toast_left=0
		scene.ui.hint_left=0
		await settle()
		var bounds:=Rect2(Vector2.ZERO,Vector2(resolution))
		check(bounds.encloses(scene.ui.header.get_global_rect()) and bounds.encloses(scene.ui.vitals.get_global_rect()) and bounds.encloses(scene.ui.minimap.get_global_rect()) and bounds.encloses(scene.ui.quick_panel.get_global_rect()),"All HUD corners fit "+str(resolution))
		check(not scene.ui.vitals.get_global_rect().intersects(scene.ui.quick_panel.get_global_rect()) and not scene.ui.minimap.get_global_rect().intersects(scene.ui.quick_panel.get_global_rect()),"HUD corners remain separate "+str(resolution))
		await picture("minimal_normal_%dx%d"%[resolution.x,resolution.y])
		scene._open_game_menu()
		scene._menu_action("inventory")
		scene.world_state.rpg.fighter.hp=60
		scene.economy.refresh(scene.world_state)
		await settle()
		check(scene.economy.inventory_view.visible and scene.world_state.inventory.count("test_heal")>0,"Menu inventory remains usable at "+str(resolution))
		await picture("minimal_inventory_%dx%d"%[resolution.x,resolution.y])
		scene.economy.close_requested.emit()
		scene._menu_action("resume")
		scene.change_location("arena",Vector2(720,480))
		scene.world_state.rpg.fighter=scene.world_state.rpg.new_fighter(scene.player.position)
		scene.world_state.combat.select_at(scene.world_state.combat.enemies.melee_01.position)
		scene.world_state.combat.request_attack(scene.world_state,scene.world_state.combat.enemies.melee_01.position)
		scene.world_state.combat.advance(scene.world_state,0.12)
		scene.economy.notice_time=0
		scene.economy.notice.hide()
		scene.ui.toast_left=0
		scene.ui.hint_left=0
		await settle()
		check(not scene.ui.target_label.text.contains("прототип") and scene.ui.quick_buttons[0].cooldown_fraction>0,"Combat HUD is visual and free of prototype labels "+str(resolution))
		await picture("minimal_combat_%dx%d"%[resolution.x,resolution.y])
		scene._open_game_menu()
		await settle()
		check(bounds.encloses(scene.game_menu.panel.get_global_rect()),"Pause menu fits "+str(resolution))
		await picture("minimal_menu_%dx%d"%[resolution.x,resolution.y])
		scene._menu_action("settings")
		await settle()
		check(bounds.encloses(scene.game_menu.panel.get_global_rect()),"Settings page fits "+str(resolution))
		await picture("minimal_settings_%dx%d"%[resolution.x,resolution.y])
		scene._menu_action("controls")
		await settle()
		check(bounds.encloses(scene.game_menu.panel.get_global_rect()),"Controls page fits "+str(resolution))
		await picture("minimal_controls_%dx%d"%[resolution.x,resolution.y])
		scene._menu_action("resume")
	scene._open_game_menu()
	scene._menu_action("settings")
	scene.game_menu.fullscreen_toggle.button_pressed=true
	await settle()
	var screen_pref:=Prefs.new()
	screen_pref.path=pref.path
	screen_pref.load_settings()
	check(screen_pref.fullscreen and scene.preferences.fullscreen and (DisplayServer.get_name()=="headless" or root.mode==Window.MODE_FULLSCREEN),"Fullscreen switch persists and changes the game window mode")
	scene.game_menu.fullscreen_toggle.button_pressed=false
	await settle()
	check(not scene.preferences.fullscreen and (DisplayServer.get_name()=="headless" or root.mode==Window.MODE_WINDOWED),"Windowed mode restores through the same setting")
	scene._menu_action("resume")
	scene.world_state.life.clock.threatened=false
	scene._open_game_menu()
	scene._menu_action("inventory")
	check(scene.economy.inventory_view.visible and not scene.world_state.life.clock.paused,"Inventory can open before a new threat is detected")
	scene._physics_process(0.016)
	check(scene.world_state.life.clock.threatened and scene.world_state.life.clock.paused and scene.game_menu.window.visible and not scene.economy.inventory_view.visible,"New threat closes menu inventory before combat advances")
	scene._menu_action("inventory")
	check(scene.game_menu.window.visible and not scene.economy.inventory_view.visible and scene.world_state.life.clock.paused,"Known threat blocks reopening live inventory")
	scene._menu_action("resume")
	scene.queue_free()
	await settle()
	print("MINIMAL MENU TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
