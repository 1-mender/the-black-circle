extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var state := State.new()
	var rpg = state.rpg
	check(state.inventory.items.is_empty(), "No implicit starter duplication")
	check(rpg.claim_kit(state.economy), "Explicit kit claim")
	check(not rpg.claim_kit(state.economy), "Kit can only be claimed once")
	check(state.inventory.count("test_heal") == 3, "Finite healing supply")
	check(rpg.stats(state.catalog).attack == 18 and rpg.stats(state.catalog).defense == 4, "Equipment modifies stats")
	check(state.economy.ledger.count("equipment", "test_sword") == 1 and state.inventory.count("test_sword") == 0, "Equipped sword has exactly one owner")
	var material: Dictionary = state.economy.ledger.material_totals()
	check(material == state.economy.material_budget, "Explicit kit updates conservation budget")
	for i in range(20):
		check(rpg.unequip(state.economy.ledger, "main_hand") and rpg.equip(state.economy.ledger, "test_sword"), "Repeated equipment transfer %d" % i)
	check(state.economy.ledger.material_totals() == material, "Equipment transfers conserve material")
	check(not rpg.equip(state.economy.ledger, "test_shield", "head"), "Wrong slot rejected")
	rpg.fighter.hp = 90.0
	check(rpg.heal(state.economy.ledger) and rpg.fighter.hp == 100, "Healing capped at maximum")
	check(state.inventory.count("test_heal") == 2 and state.economy.ledger.count("consumed", "test_heal") == 1, "Consumed item transferred once")
	check(not rpg.heal(state.economy.ledger), "Heal cooldown")
	check(rpg.bind_quick(0, "test_sword", state.economy.ledger), "Quick slot binding of equipped item")
	var restored := State.new()
	check(restored.apply_save(state.to_save()), "New save loads")
	check(restored.rpg.to_save() == rpg.to_save(), "Stats, equipment and quick slots restored")
	check(restored.economy.ledger.material_totals() == material, "Save preserves ownership")
	var legacy: Dictionary = State.new().to_save()
	legacy.version = 3
	legacy.erase("rpg")
	for owner in ["equipment", "consumed"]:
		legacy.economy.ledger.owners.erase(owner)
		legacy.economy.ledger.wallets.erase(owner)
	check(State.new().apply_save(legacy), "Legacy v3 owner migration")
	var crafter := State.new()
	crafter.player_position = crafter.economy.Settings.WORKBENCH
	crafter.mine("iron_01")
	crafter.mine("iron_01")
	for recipe in ["iron_ingot", "test_sword", "iron_ingot", "test_armor"]:
		check(crafter.economy.start_job("player", recipe), "Gear production reserves real inputs: " + recipe)
		var minutes: int = crafter.catalog.recipes[recipe].minutes
		for _i in range(minutes):
			crafter.life.advance(0.5)
	check(crafter.inventory.count("test_sword") == 1 and crafter.inventory.count("test_armor") == 1, "Mining and time produce weapon and armor")
	check(crafter.economy.ledger.material_totals() == crafter.economy.material_budget, "Gear recipes conserve original metal")
	check(not crafter.economy.start_job("player", "test_sword"), "No equipment production without materials")
	check(crafter.rpg.equip(crafter.economy.ledger, "test_armor") and crafter.rpg.stats(crafter.catalog).defense == 6 and crafter.rpg.stats(crafter.catalog).move_speed == 200, "Crafted body armor changes derived stats")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.economy.open_inventory(state)
	scene.economy.selected_item = "test_sword"
	scene.economy.refresh(state)
	scene.ui.refresh_rpg(state)
	check(scene.economy.equipment_box.get_child_count() >= 8, "All equipment slots visible")
	check(scene.ui.quick_buttons.size() == 4, "Four quick slots")
	scene.queue_free()
	await process_frame
	print("RPG TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
