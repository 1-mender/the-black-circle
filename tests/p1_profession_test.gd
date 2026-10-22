extends SceneTree

const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const Conversation = preload("res://scripts/simulation/conversation_session.gd")
const MainScene = preload("res://scenes/main.tscn")
const SLOT := "res://.godot/p1_profession_test.json"
const EXPECTED := "res://.godot/p1_profession_expected.json"
const HELD: Array[String] = ["test_miner", "test_smith", "test_merchant"]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)

func advance_minutes(state: RefCounted, count: int) -> void:
	for index in range(count):
		state.life.clock.minute += 1
		state.life.step(HELD)

func first_difference(left: Variant, right: Variant, path: String = "root") -> String:
	if (left is float or left is int) and (right is float or right is int):
		return "" if is_equal_approx(float(left), float(right)) else "%s %.9f != %.9f" % [path, float(left), float(right)]
	if left is Dictionary and right is Dictionary:
		for key in left:
			if not right.has(key):
				return path + "." + str(key) + " missing"
			var nested := first_difference(left[key], right[key], path + "." + str(key))
			if not nested.is_empty():
				return nested
		return "" if left.size() == right.size() else path + " extra keys"
	if left is Array and right is Array:
		if left.size() != right.size():
			return "%s length %d != %d" % [path, left.size(), right.size()]
		for index in range(left.size()):
			var nested := first_difference(left[index], right[index], path + "[%d]" % index)
			if not nested.is_empty():
				return nested
		return ""
	return "" if left == right else "%s %s != %s" % [path, str(left).left(160), str(right).left(160)]

func run() -> void:
	if "--verify-save" in OS.get_cmdline_user_args():
		var loaded := State.new()
		var error := Service.load_game(loaded, SLOT)
		check(error.is_empty(), "Fresh process loads unfinished production")
		if error.is_empty():
			advance_minutes(loaded, 180)
			var expected = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
			var actual = JSON.parse_string(JSON.stringify(loaded.to_save()))
			var difference := first_difference(actual, expected)
			if not difference.is_empty():
				print("P1_DIFFERENCE ", difference)
			check(difference.is_empty(), "Fresh process continues the same production and social history")
		print("P1 PROFESSION FRESH: %d checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	var state := State.new()
	var miner_a: String = state.spawn_resident(Vector2(936, 300), "miner")
	var miner_b: String = state.spawn_resident(Vector2(888, 384), "miner")
	var smith_a: String = state.spawn_resident(Vector2(720, 864), "smith")
	var smith_b: String = state.spawn_resident(Vector2(768, 864), "smith")
	var merchant_a: String = state.spawn_resident(Vector2(816, 720), "merchant")
	var merchant_b: String = state.spawn_resident(Vector2(864, 720), "merchant")
	var ids := [miner_a, miner_b, smith_a, smith_b, merchant_a, merchant_b]
	var unique_ids: Dictionary = {}
	for id in ids:
		unique_ids[id] = true
	check(ids.all(func(id: String): return not id.is_empty()) and unique_ids.size() == 6, "Two workers of each existing production occupation can be created")
	if ids.any(func(id: String): return id.is_empty()):
		quit(1)
		return
	check(state.economy.ledger.owners.has("process:worker:" + smith_a) and state.economy.ledger.owners.has("shop:" + merchant_b), "Per-worker escrow and shop ownership are registered")
	check(state.catalog.shops.has(merchant_a) and state.catalog.shops.has(smith_a), "Dynamic merchants and smiths inherit existing price definitions")
	var dialogue := Conversation.new()
	dialogue.state = state
	dialogue.npc_id = merchant_a
	dialogue.menu()
	check(dialogue.choices.any(func(choice: Dictionary): return choice.id == "trade"), "Generated merchant offers trade through the existing conversation menu")
	check(state.life.people[miner_a].position.distance_to(state.life.people[miner_b].position) >= 32, "New residents receive distinct walkable spawn positions")
	var contact: Dictionary = state.social.execute(state, smith_a, "test_apprentice", "talk")
	check(bool(contact.get("ok", false)) and state.social.characters[smith_a].memory.size() > 0, "New production worker uses ordinary social actions with an existing resident")
	var initial_materials: Dictionary = state.economy.ledger.material_totals()
	var initial_money: int = state.economy.money_budget
	state.life.clock.minute = 600
	state.social.last_minute = 599
	advance_minutes(state, 180)
	check(state.economy.mined.test_iron_ore + state.economy.mined.test_copper_ore > 0, "New miners extract finite ore")
	check(state.economy.ledger.material_totals() == initial_materials, "Concurrent mining and production conserve material")
	check(state.economy.money_budget == initial_money, "Creation and work do not mint money")
	var job_in_progress := false
	for minute in range(180):
		advance_minutes(state, 1)
		if not state.economy.jobs[smith_a].is_empty() and int(state.economy.jobs[smith_a].progress) > 0 or not state.economy.jobs[smith_b].is_empty() and int(state.economy.jobs[smith_b].progress) > 0:
			job_in_progress = true
			break
	check(job_in_progress, "A generated smith reserves actual material in an unfinished order")
	var snapshot := JSON.stringify(state.to_save(), "", true, true)
	var broken: Dictionary = state.to_save()
	broken.economy.workers[smith_a].mining_progress = -1
	check(not state.apply_save(broken) and JSON.stringify(state.to_save(), "", true, true) == snapshot, "Malformed worker progress is rejected without changing the live game")
	check(Service.save_game(state, SLOT).is_empty(), "Work-in-progress saves through SaveService in an isolated slot")
	var restored := State.new()
	check(Service.load_game(restored, SLOT).is_empty(), "All six workers reload through SaveService")
	check(JSON.parse_string(JSON.stringify(restored.to_save())) == JSON.parse_string(JSON.stringify(state.to_save())), "Jobs, deposits, worker inventories and social state round-trip")
	advance_minutes(state, 180)
	advance_minutes(restored, 180)
	check(JSON.parse_string(JSON.stringify(restored.to_save())) == JSON.parse_string(JSON.stringify(state.to_save())), "Loaded workers continue deterministically")
	var expected_file := FileAccess.open(EXPECTED, FileAccess.WRITE)
	if expected_file != null:
		expected_file.store_string(JSON.stringify(state.to_save(), "", true, true))
		expected_file.close()
	check(expected_file != null, "Expected continuation stored outside the user slot")
	print("P1_CHAIN mined=", state.economy.mined, " produced=", state.economy.produced, " shops=", state.economy.ledger.owners["shop:" + merchant_a].items, " | ", state.economy.ledger.owners["shop:" + merchant_b].items)
	check(not state.economy.produced.is_empty(), "Generated smiths complete existing recipes")
	var stocked_shop := ""
	var stocked_item := ""
	for merchant in [merchant_a, merchant_b]:
		var stock: Dictionary = state.economy.ledger.owners["shop:" + merchant].items
		if not stock.is_empty():
			stocked_shop = merchant
			stocked_item = str(stock.keys()[0])
			break
	check(not stocked_shop.is_empty(), "Generated merchant delivers finished goods to a finite shop")
	if not stocked_shop.is_empty():
		var stock_before: int = state.economy.ledger.count("shop:" + stocked_shop, stocked_item)
		check(state.economy.ledger.transfer_money("shop:test_merchant", "player", 100), "Test buyer receives existing cash by explicit transfer")
		var paid: int = state.buy(stocked_shop, stocked_item, 1)
		check(paid > 0 and state.inventory.count(stocked_item) == 1 and state.economy.ledger.count("shop:" + stocked_shop, stocked_item) == stock_before - 1, "Player buys a real item from a generated merchant")
	check(state.economy.ledger.material_totals() == initial_materials, "No materials duplicate after continuation")
	check(state.economy.money_budget == initial_money, "No money duplicates after continuation")
	check(state.social.characters.has(smith_a) and state.social.characters[smith_a].memory.size() > 0, "Production workers retain common social memory")
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	var new_trader: String = scene.world_state.spawn_resident(Vector2(816, 720), "merchant")
	scene._sync_residents(0.0, true)
	scene.player.position = scene.resident_views[new_trader].position
	scene._social_trade(new_trader)
	check(scene.economy.mode == "market" and scene.economy.shop_id == new_trader, "Live conversation opens generated merchant's own shop")
	scene.close_windows()
	var new_smith: String = scene.world_state.spawn_resident(Vector2(720, 864), "smith")
	scene._sync_residents(0.0, true)
	scene.player.position = scene.resident_views[new_smith].position
	scene._social_trade(new_smith)
	check(scene.economy.mode == "trade" and scene.economy.shop_id == new_smith, "Live conversation opens generated smith's ore trade")
	scene.queue_free()
	print("P1 PROFESSION TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
