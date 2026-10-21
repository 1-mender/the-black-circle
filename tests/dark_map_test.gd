extends "res://tests/conversation_test.gd"
const Geometry=preload("res://scripts/data/map_geometry.gd")
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
func run() -> void:
	var world:=State.new()
	world.cartography.observe("mine",Vector2(480,300),world.adventure.gates)
	check(world.cartography.knows("mine",Vector2(480,300)),"The player's visible space is discovered")
	check(not world.cartography.knows("mine",Vector2(672,300)),"Mine wall conceals the space behind it")
	check(not world.cartography.known.has("adit_depths"),"Unvisited areas remain unknown")
	world.cartography.observe("mine",Vector2(672,300),world.adventure.gates)
	check(world.cartography.knows("mine",Vector2(672,300)),"Movement reveals newly reached terrain")
	check(world.cartography.knows("mine",Vector2(480,300)),"Previously explored terrain remains known")
	check(Service.save_game(world,"res://.godot/cartography.json").is_empty(),"Map uses a separate test save")
	var restored:=State.new()
	check(Service.load_game(restored,"res://.godot/cartography.json").is_empty() and restored.cartography.to_save()==world.cartography.to_save(),"Exploration survives real disk save/load")
	var old: Dictionary=world.to_save()
	old.erase("cartography")
	check(State.new().apply_save(old),"Previous saves load without cartography")
	var bad: Dictionary=world.to_save()
	bad.cartography={"mine":[1,1]}
	var before: Dictionary=restored.to_save()
	check(not restored.apply_save(bad) and restored.to_save()==before,"Invalid exploration fails atomically")
	bad.cartography={"secret_area":[1]}
	check(not restored.apply_save(bad),"Unknown map IDs cannot enter a save")
	bad.cartography={"mine":[100000]}
	check(not restored.apply_save(bad),"Exploration cannot exceed real area bounds")
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	stage=scene
	await settle()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	check(InputMap.has_action("world_map") and InputMap.action_get_events("world_map")[0].physical_keycode==KEY_M,"M opens the map without replacing old bindings")
	check(not scene.ui.location_label.visible,"Permanent region header is removed")
	check(scene.ui.header.get_theme_stylebox("panel").bg_color==UIStyle.BACKGROUND,"HUD uses shared graphite background")
	check(scene.economy.inventory_view.get_theme_stylebox("panel").bg_color==UIStyle.BACKGROUND,"Inventory uses the same background")
	for size in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		scene.change_location("town",Vector2(864,816))
		scene.ui.toast_left=0
		await settle()
		var bounds:=Rect2(Vector2.ZERO,Vector2(size))
		for control in [scene.ui.vitals,scene.ui.minimap,scene.ui.header,scene.ui.quick_panel]:
			check(bounds.encloses(control.get_global_rect()),"HUD fits "+str(size)+str(control.get_class()))
		check(scene.ui.minimap.get_global_rect().end.x<scene.ui.vitals.get_global_rect().position.x,"Map and vitals occupy separate bottom corners "+str(size))
		check(not scene.ui.header.get_global_rect().intersects(scene.ui.vitals.get_global_rect()),"Compact header does not cover vitals "+str(size))
		check(scene.ui.quick_buttons.all(func(b:Button):return b.icon!=null),"All four quick actions use existing icons "+str(size))
		await picture("dark_town_%dx%d"%[size.x,size.y])
		var first: Vector2=scene.ui.mini_view.map_point(Vector2(864,816))
		scene.player.position+=Vector2(96,0)
		scene.world_state.player_position=scene.player.position
		scene.ui.mini_view.refresh(scene.world_state)
		check(scene.ui.mini_view.map_point(Vector2(864,816))!=first,"Map follows actual movement "+str(size))
		scene._toggle_map()
		await settle()
		check(scene.ui.map_window.visible and not scene.player.input_enabled and bounds.encloses(scene.ui.map_window.get_global_rect()),"Large map opens and fits "+str(size))
		check(not scene.ui.minimap.visible,"Mini-map yields to modal windows "+str(size))
		await picture("dark_map_%dx%d"%[size.x,size.y])
		scene.close_windows()
		scene.change_location("mine",scene.MineData.SPAWN)
		scene.ui.toast_left=0
		await settle()
		check(scene.ui.mini_view.area=="mine" and Geometry.walls("mine",{}).size()==scene.MineData.solid_rects().size(),"Mine map uses actual mine geometry "+str(size))
		await picture("dark_mine_%dx%d"%[size.x,size.y])
		scene.time_ui.clock_button.pressed.emit()
		await settle()
		check(bounds.encloses(scene.time_ui.clock_panel.get_global_rect()) and not scene.time_ui.clock_panel.get_global_rect().intersects(scene.ui.header.get_global_rect()),"Expandable speeds fit beneath the header "+str(size))
		scene.time_ui.clock_panel.hide()
	for area in ["arena","adit_entry","adit_depths"]:
		scene.change_location(area,Vector2(240,816) if area=="adit_depths" else scene.Adit.SPAWN if area=="adit_entry" else scene.Arena.SPAWN)
		await settle()
		check(scene.ui.mini_view.area==area,"Map switches to "+area)
	var before_map: Dictionary=scene.world_state.cartography.to_save()
	check(scene.save_game("res://.godot/map_input.json") and scene.load_game("res://.godot/map_input.json"),"Scene save/load succeeds with map knowledge")
	check(scene.world_state.cartography.to_save()==before_map,"Load restores exactly the learned cells")
	scene.ui.mini_view.refresh(scene.world_state)
	var drawn_signature: String=scene.ui.mini_view.last_signature
	var identical: Dictionary=scene.world_state.to_save()
	check(scene.world_state.apply_save(identical),"An identical-position save can restore a new knowledge model")
	scene.ui.mini_view.refresh(scene.world_state)
	check(scene.ui.mini_view.last_signature!=drawn_signature,"Loading invalidates cached map drawing even with identical cell count and position")
	scene.close_windows()
	scene.world_state.life.clock.paused=true
	var paused_snapshot: Dictionary=scene.world_state.to_save()
	var key:=InputEventAction.new()
	key.action="world_map"
	key.pressed=true
	Input.parse_input_event(key)
	await settle()
	check(scene.ui.map_window.visible,"Real map shortcut works while paused")
	check(scene.world_state.to_save()==paused_snapshot,"Reading the map on pause does not advance or alter world state")
	scene.ui.map_window.get_child(0).get_child(0).get_child(1).grab_focus()
	var pause_key:=InputEventAction.new()
	pause_key.action="pause_game"
	pause_key.pressed=true
	Input.parse_input_event(pause_key)
	await settle()
	check(not scene.world_state.life.clock.paused and scene.ui.map_window.visible,"Space uses the common pause even when a map button is focused")
	scene.close_windows()
	scene.world_state.life.clock.paused=false
	scene.change_location("town",scene.LocationData.PLAYER_SPAWN)
	await install(scene,State.new(),"test_recluse")
	check(not scene.ui.visible and not scene.ui.minimap.is_visible_in_tree(),"Cinematic scene hides all ordinary HUD")
	check(scene.social_ui.dialogue.speech.get_theme_stylebox("panel").bg_color==UIStyle.BACKGROUND,"Cinematic speech shares the graphite theme")
	for resolution in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=resolution
		root.size=resolution
		scene.social_ui._layout()
		await settle()
		await picture("dark_dialogue_%dx%d"%[resolution.x,resolution.y])
	scene.close_windows()
	scene.economy.open_inventory(scene.world_state)
	await settle()
	await picture("dark_inventory")
	scene.queue_free()
	await settle()
	print("DARK MAP TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
