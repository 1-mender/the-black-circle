extends SceneTree
## UI uses the existing ledger; synthetic catalog entries exist only in this fixture.
const Service = preload("res://scripts/simulation/save_service.gd")
const SLOT := "res://.godot/inventory051_test_save.json"
var checks := 0
var failures := 0
var capture := false
var scene: Node
var view: Control
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func settle() -> void:
	for _i in range(4):
		await process_frame
		await physics_frame
	if capture:
		await RenderingServer.frame_post_draw
func key(code: Key, ctrl := false, alt := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		event.alt_pressed = alt
		Input.parse_input_event(event)
func pointer(button: Button, code: MouseButton, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = code
	event.pressed = true
	event.double_click = double_click
	button._gui_input(event)
func bounds(control: Control, rect: Rect2) -> bool:
	return rect.grow(1).encloses(control.get_global_rect())
func image_file(name: String) -> void:
	if capture:
		root.get_texture().get_image().save_png("res://.godot/inventory051_" + name + ".png")
func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.save_path = SLOT
	await settle()
	scene.economy.open_inventory(scene.world_state)
	view = scene.economy.inventory_view
	await settle()
	check(view.empty_label == null and view.grid.get_child_count() == 0, "Empty bag shows clean slots without instructional text")
	check(not view.kit_button.visible and not view.developer_mode, "Test grants hidden from normal inventory")
	image_file("empty_bag")
	key(KEY_D, true, true)
	await settle()
	check(view.developer_mode and view.kit_button.visible, "Explicit developer shortcut reveals grant")
	view.kit_button.pressed.emit()
	await settle()
	check(scene.world_state.rpg.kit_claimed and not view.kit_button.visible, "Developer kit still finite and one-time")
	check(view.gear_slots.main_hand.item_id == "test_sword" and view.gear_slots.off_hand.item_id == "test_shield", "Equipped gear visible with icons")
	check(view.portrait.texture != null and view.gear_slots.head.image.texture != null, "Actor and recognizable empty slot icons")
	view.developer_mode = false
	view.refresh(scene.world_state)
	var original: Dictionary = scene.world_state.economy.ledger.material_totals()
	pointer(view.gear_slots.main_hand, MOUSE_BUTTON_LEFT, true)
	await settle()
	check(scene.world_state.rpg.equipment.main_hand.is_empty() and scene.world_state.inventory.count("test_sword") == 1, "Double click removes gear through ledger")
	check(scene.world_state.rpg.stats(scene.world_state.catalog).attack == 8, "Unequipping changes attack")
	view.select_item("test_sword")
	check(view.comparison.text.contains("+10") and view.comparison.visible, "Comparison with empty main hand")
	var drag := {"item_id": "test_sword", "source_slot": ""}
	check(view.gear_slots.main_hand._can_drop_data(Vector2.ZERO, drag), "Matching gear drop accepted")
	check(not view.gear_slots.head._can_drop_data(Vector2.ZERO, drag), "Wrong gear drop rejected")
	await settle()
	check(view.gear_slots.main_hand.suitable and not view.gear_slots.head.suitable, "Selected item highlights compatible slots")
	view.gear_slots.main_hand._drop_data(Vector2.ZERO, drag)
	await settle()
	check(scene.world_state.rpg.equipment.main_hand == "test_sword" and scene.world_state.inventory.count("test_sword") == 0, "Drop equips exactly one existing sword")
	check(scene.world_state.rpg.stats(scene.world_state.catalog).attack == 18, "Equipping restores attack bonus")
	view.bag_scroll._drop_data(Vector2.ZERO, {"item_id": "test_sword", "source_slot": "main_hand"})
	await settle()
	check(scene.world_state.inventory.count("test_sword") == 1 and scene.world_state.rpg.equipment.main_hand.is_empty(), "Dropping equipped item back to bag")
	view.bag_slots.test_sword.grab_focus()
	key(KEY_ENTER)
	await settle()
	check(scene.world_state.rpg.equipment.main_hand == "test_sword", "Keyboard Enter equips focused item")
	view.select_item("test_heal")
	pointer(view.bag_slots.test_heal, MOUSE_BUTTON_RIGHT)
	await settle()
	check(view.context_menu.visible and view.context_menu.get_item_text(0) == "Использовать", "Right click opens item context menu")
	view.context_menu.id_pressed.emit(10)
	view.context_menu.hide()
	await settle()
	check(scene.world_state.rpg.quick[0] == "test_heal", "Context menu assigns quick slot")
	view.quick_slots[2]._drop_data(Vector2.ZERO, {"item_id": "test_heal", "quick_index": 0})
	await settle()
	check(scene.world_state.rpg.quick[2] == "test_heal" and scene.world_state.rpg.quick[0] == "dodge", "Dragging quick slots swaps references")
	scene.ui.quick_buttons[1]._drop_data(Vector2.ZERO, {"item_id": "test_heal", "quick_index": 2})
	await settle()
	check(scene.world_state.rpg.quick[1] == "test_heal" and scene.world_state.rpg.quick[2] == "block", "HUD and inventory share quick slots")
	view.select_item("test_heal")
	key(KEY_4)
	await settle()
	check(scene.world_state.rpg.quick[3] == "test_heal", "Keyboard quick binding")
	view.select_item("test_sword", "main_hand")
	key(KEY_2)
	await settle()
	check(scene.world_state.rpg.quick[1] == "test_sword", "Keyboard binding changes a different quick slot")
	view.select_item("test_heal")
	view._quick_context(0, Vector2(400,400))
	view._context_action(100)
	view.context_menu.hide()
	check(scene.world_state.rpg.quick[0] == "attack", "Standard quick action can be restored")
	var count: int = scene.world_state.inventory.count("test_heal")
	pointer(view.bag_slots.test_heal, MOUSE_BUTTON_LEFT, true)
	await settle()
	check(scene.world_state.inventory.count("test_heal") == count and view.message.text.contains("Здоровье"), "Cannot consume at full health and explains reason")
	scene.world_state.rpg.fighter.hp = 65
	pointer(view.bag_slots.test_heal, MOUSE_BUTTON_LEFT, true)
	await settle()
	check(scene.world_state.rpg.fighter.hp == 100 and scene.world_state.inventory.count("test_heal") == count - 1, "Double click heals once capped at max HP")
	scene.world_state.rpg.fighter.hp = 80
	pointer(view.bag_slots.test_heal, MOUSE_BUTTON_LEFT, true)
	await settle()
	check(scene.world_state.inventory.count("test_heal") == count - 1 and view.message.text.contains("восстанавливается"), "Healing cooldown shown without spending another item")
	scene.world_state.life.clock.paused = true
	pointer(view.gear_slots.main_hand, MOUSE_BUTTON_LEFT, true)
	check(scene.world_state.rpg.equipment.main_hand == "test_sword" and view.message.text.contains("паузе"), "Paused action gives clear reason and preserves ownership")
	check(view.drop_button.disabled, "Dropping is unavailable while paused")
	check(scene.world_state.economy.ledger.material_totals() == original, "UI actions never duplicate physical material")
	check(scene.save_game(SLOT), "Separate inventory test slot saves")
	var equipped: Dictionary = scene.world_state.rpg.equipment.duplicate()
	var quick: Array = scene.world_state.rpg.quick.duplicate()
	scene.world_state.rpg.equipment.main_hand = ""
	check(scene.load_game(SLOT), "Existing save loader restores inventory UI data")
	check(scene.world_state.rpg.equipment == equipped and scene.world_state.rpg.quick == quick and scene.world_state.rpg.fighter.hp == 80, "Equipment quick slots and HP restore")
	scene.economy.open_inventory(scene.world_state)
	await settle()
	check(view.gear_slots.main_hand.item_id == "test_sword", "Loaded equipment reflected in slots")
	# Explicit test-only fixtures; no game grants and no user slot writes.
	for id in ["test_iron_ore", "test_copper_ore", "test_iron_ingot", "test_copper_ingot", "test_iron_tool", "test_copper_trinket", "test_armor"]:
		scene.world_state.inventory.add(id, 12 if id.contains("ore") else 1)
	view.refresh(scene.world_state)
	view.category_picker.select(1)
	view.category_picker.item_selected.emit(1)
	check(view.filtered_ids().is_empty(), "Weapon category excludes equipped weapon from bag")
	view.category_picker.select(2)
	view.category_picker.item_selected.emit(2)
	check(view.filtered_ids() == ["test_armor"], "Armor category")
	view.category_picker.select(0)
	view.category_picker.item_selected.emit(0)
	view.search.text = "желез"
	view.search.text_changed.emit("желез")
	check(view.filtered_ids().size() == 4, "Search by item name and description")
	view.search.text = "нет такого предмета"
	view.search.text_changed.emit(view.search.text)
	check(view.empty_label.text.contains("Ничего не найдено"), "Empty search explained separately from empty bag")
	view.search.clear()
	view.search.text_changed.emit("")
	view.sorter.select(2)
	view.sorter.item_selected.emit(2)
	check(scene.world_state.inventory.count(view.filtered_ids()[0]) == 12, "Sort by stack quantity")
	view.sorter.select(0)
	view.sorter.item_selected.emit(0)
	view._activate("test_copper_trinket", "")
	view.gear_slots.accessory_2._drop_data(Vector2.ZERO, {"item_id": "test_copper_trinket", "source_slot": "accessory_1"})
	# Loaded pause deliberately prevents this attempt.
	check(scene.world_state.rpg.equipment.accessory_1.is_empty(), "Loaded pause still prevents equipping")
	scene.world_state.life.clock.paused = false
	view._activate("test_copper_trinket", "")
	view.gear_slots.accessory_2._drop_data(Vector2.ZERO, {"item_id": "test_copper_trinket", "source_slot": "accessory_1"})
	check(scene.world_state.rpg.equipment.accessory_2 == "test_copper_trinket" and scene.world_state.rpg.equipment.accessory_1.is_empty(), "Accessory transfers between equivalent slots")
	check(scene.world_state.economy.ledger.count("equipment", "test_copper_trinket") == 1 and scene.world_state.rpg.stats(scene.world_state.catalog).max_stamina == 105, "Accessory move conserves one item and stats")
	scene.world_state.life.clock.paused = true
	view.developer_mode = false
	# Freeze motion for reproducible screenshots while showing available actions.
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.world_state.life.clock.paused = false
	scene.world_state.rpg.fighter.heal_cooldown = 0.0
	for resolution in [Vector2i(1152,720), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.content_scale_size = Vector2i.ZERO
		root.size = resolution
		await settle()
		view.refresh(scene.world_state)
		view.select_item("test_armor")
		root.gui_release_focus()
		scene.economy.notice.hide()
		await settle()
		var viewport := root.get_visible_rect()
		var label := "%dx%d" % [resolution.x, resolution.y]
		check(bounds(view, viewport), "Window within viewport " + label)
		for column in [view.character_panel, view.bag_panel, view.detail_panel, view.footer]:
			check(bounds(column, view.get_global_rect()), "Inventory region within window " + label)
		check(not view.character_panel.get_global_rect().intersects(view.bag_panel.get_global_rect()) and not view.bag_panel.get_global_rect().intersects(view.detail_panel.get_global_rect()), "Three columns do not overlap " + label)
		for slot in view.gear_slots.values():
			check(bounds(slot, view.character_panel.get_global_rect()), "Equipment slot fits " + label)
		check(not scene.ui.vitals.visible or not view.get_global_rect().intersects(scene.ui.vitals.get_global_rect()), "Inventory does not cover HUD vitals " + label)
		check(bounds(view.comparison, view.property_group.get_parent().get_parent().get_global_rect()), "Comparison visible without scrolling " + label)
		image_file(label + "_equipment")
		if view.card_tabs.visible:
			view.description_tab_button.pressed.emit()
			await settle()
			check(view.details.visible and not view.property_group.visible, "Compact description tab " + label)
			check(bounds(view.details, view.details.get_parent().get_parent().get_global_rect()), "Description readable without clipping " + label)
			image_file(label + "_description")
			view.property_tab_button.pressed.emit()
			check(view.property_group.visible and not view.details.visible, "Compact properties tab " + label)
		else:
			check(view.property_group.visible and view.details.visible, "Tall layout shows description and properties together " + label)
		view.select_item("test_heal")
		await settle()
		image_file(label + "_consumable")
	# Stress a future large catalog without modifying on-disk definitions or saves.
	for index in range(120):
		var id := "fixture_%03d" % index
		scene.world_state.catalog.items[id] = {"name": "Образец %03d" % index, "description": "Только тест прокрутки", "category": "material", "material": {}}
		scene.world_state.inventory.add(id, index + 1)
	view.refresh(scene.world_state)
	await settle()
	check(view.bag_slots.size() >= 120 and view.bag_scroll.get_v_scroll_bar().max_value > view.bag_scroll.size.y, "Large bag has a functional scrollbar")
	view.bag_scroll.scroll_vertical = 100000
	await settle()
	check(view.bag_scroll.scroll_vertical > 0, "Can scroll to later items")
	var last: Button = view.bag_slots.values().back()
	last.grab_focus()
	await settle()
	check(last.has_focus(), "Keyboard reaches items in large bag")
	view.search.text = "Образец 119"
	view.search.text_changed.emit(view.search.text)
	check(view.filtered_ids() == ["fixture_119"], "Large bag search isolates one stack")
	scene.queue_free()
	await process_frame
	print("INVENTORY 0.5.1 TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
