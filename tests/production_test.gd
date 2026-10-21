extends SceneTree
## Полный производственный цикл, сохранение процессов и инварианты имущества.

const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const Settings = preload("res://scripts/data/production_definitions.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const SLOT := "res://.godot/production_test_save.json"
const MID_SLOT := "res://.godot/production_mid_save.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func advance(state: RefCounted, minutes: int, held: Array[String] = []) -> void:
	for _minute in range(minutes):
		state.life.advance(0.5 / float(state.life.clock.speed), held)

func cash_total(state: RefCounted) -> int:
	var total := 0
	for cash in state.economy.ledger.wallets.values():
		total += int(cash)
	return total

func frames(count: int = 3) -> void:
	for _frame in range(count):
		await physics_frame
		await process_frame

func verify_final(state: RefCounted) -> void:
	check(state.inventory.count("test_copper_trinket") == 1, "Purchased NPC-made product belongs to player")
	check(state.economy.ledger.material_totals() == {"iron": 10, "copper": 3}, "All material conserved through cycle and purchase")
	check(cash_total(state) == 700 and state.money == 2, "Trade money conserved with finite counterparty wallets")
	for id in state.resources:
		check(state.resources[id] == 0, "Source remains depleted: " + id)
	check(state.economy.ledger.count("shop:test_merchant", "test_copper_trinket") == 2, "Merchant stock reduced by purchased unit")

func run() -> void:
	var state := State.new()
	if "--verify-save" in OS.get_cmdline_user_args():
		check(Service.load_game(state, SLOT).is_empty(), "Fresh process loads economic owners")
		verify_final(state)
		await finish()
		return
	check(state.economy.ledger.count("source:iron_01", "test_iron_ore") == 6, "Source ownership derives from shared finite charges")
	check(not state.economy.start_job("smith", "iron_ingot"), "Smith cannot start without materials")
	var before: Dictionary = state.to_save()
	check(not state.economy.ledger.transfer("player", "workshop", "test_iron_ore", 1) and state.to_save() == before, "Empty inventory cannot create stock")
	check(state.mine("iron_01") == 2, "Player reserves own ore from shared mine")
	var seen := {"mine": false, "miner_inventory": false, "warehouse": false, "escrow": false, "finished": false, "merchant_inventory": false, "shop": false}
	var conserved := true
	var nonnegative := true
	var checkpoints: Dictionary = {}
	for _minute in range(5 * 1440):
		advance(state, 1)
		var ledger = state.economy.ledger
		seen["mine"] = seen["mine"] or state.life.people["test_miner"]["location"] == "mine"
		for pair in [["miner_inventory", "npc:test_miner"], ["warehouse", "workshop"], ["escrow", "process:smith"], ["finished", "finished"], ["merchant_inventory", "npc:test_merchant"], ["shop", "shop:test_merchant"]]:
			seen[pair[0]] = seen[pair[0]] or not ledger.owners[pair[1]].items.is_empty()
		conserved = conserved and ledger.material_totals() == {"iron": 10, "copper": 3} and cash_total(state) == 700
		for amount in state.resources.values():
			nonnegative = nonnegative and int(amount) >= 0
		for owner in ["npc:test_miner", "npc:test_merchant"]:
			if not checkpoints.has(owner) and not ledger.owners[owner].items.is_empty():
				var checkpoint := State.new()
				check(checkpoint.apply_save(state.to_save()) and checkpoint.economy.ledger.owners[owner].items == ledger.owners[owner].items, "Loaded nonempty NPC inventory: " + owner)
				checkpoints[owner] = true
		if not checkpoints.has("mining") and state.economy.mining_progress > 0:
			var checkpoint := State.new()
			check(checkpoint.apply_save(state.to_save()) and checkpoint.economy.mining_progress == state.economy.mining_progress, "Partial mining effort and site survive load")
			checkpoints["mining"] = true
	check(conserved, "Every minute for five days preserves material and money")
	check(nonnegative, "Shared deposits never become negative")
	for stage in seen:
		check(seen[stage], "Full cycle reaches stage: " + stage)
	check(state.economy.ledger.count("shop:test_merchant", "test_iron_tool") == 4 and state.economy.ledger.count("shop:test_merchant", "test_copper_trinket") == 3, "NPC ore produces exactly four tools and three trinkets")
	check(state.economy.mined == {"test_iron_ore": 10, "test_copper_ore": 3}, "Mining statistics match finite extraction including player")
	var completed: Dictionary = state.economy.produced.duplicate()
	advance(state, 1440)
	check(state.economy.produced == completed and state.economy.jobs["smith"].is_empty(), "Exhaustion stops new production instead of creating free goods")
	check(state.sell("test_smith", "test_iron_ore", 2) == 10, "Existing ore sale transfers stock and money")
	check(state.economy.ledger.count("workshop", "test_iron_ore") == 2, "Sold ore belongs to workshop instead of disappearing")
	check(state.buy("test_merchant", "test_copper_trinket", 1) == 8, "Player buys actual NPC-made product")
	verify_final(state)
	before = state.to_save()
	check(state.buy("test_merchant", "test_iron_tool", 1) == 0 and state.to_save() == before, "Insufficient money is atomic")
	check(state.buy("test_merchant", "test_copper_trinket", 100) == 0 and state.to_save() == before, "Cannot buy more than finite shop stock")
	check(state.mine("copper_01") == 0, "Player cannot mine an exhausted NPC-used source")
	check(Service.save_game(state, SLOT).is_empty(), "Full economy saved to disk")
	var restored := State.new()
	check(Service.load_game(restored, SLOT).is_empty(), "Economic owners restored from disk")
	check(restored.economy.to_save() == state.economy.to_save(), "Owners, cash, production counters and jobs restore exactly")
	for _attempt in range(3):
		check(Service.load_game(restored, SLOT).is_empty() and restored.economy.ledger.material_totals() == {"iron": 10, "copper": 3}, "Repeated load never duplicates goods")
	var mid := State.new()
	mid.mine("iron_01")
	mid.economy.ledger.transfer("player", "workshop", "test_iron_ore", 2)
	check(mid.economy.start_job("smith", "iron_ingot"), "Smith reserves ore into process owner")
	check(mid.economy.ledger.count("workshop", "test_iron_ore") == 0 and mid.economy.ledger.count("process:smith", "test_iron_ore") == 2, "Reservation removes available material exactly once")
	check(not mid.economy.start_job("smith", "iron_ingot"), "Cannot double-reserve same job")
	advance(mid, 12, ["test_miner"])
	check(mid.economy.jobs["smith"]["progress"] == 12, "Production takes actual work minutes")
	check(Service.save_game(mid, MID_SLOT).is_empty(), "Mid-production escrow saved")
	var resumed := State.new()
	check(Service.load_game(resumed, MID_SLOT).is_empty() and resumed.economy.jobs["smith"]["progress"] == 12, "Mid-production progress restored")
	var hungry := State.new()
	hungry.apply_save(mid.to_save())
	hungry.life.people["test_smith"]["fatigue"] = 90.0
	hungry.life.people["test_smith"]["next_decision"] = hungry.life.clock.minute
	advance(hungry, 5, ["test_miner"])
	check(hungry.economy.jobs["smith"]["progress"] == 12 and hungry.economy.ledger.count("process:smith", "test_iron_ore") == 2, "Fatigue suspends smith work without losing or refunding reserved inputs")
	advance(mid, 60, ["test_miner"])
	advance(resumed, 60, ["test_miner"])
	check(resumed.economy.to_save() == mid.economy.to_save(), "Loaded job completes identically to uninterrupted job")
	check(resumed.economy.ledger.count("shop:test_merchant", "test_iron_tool") == 1 and resumed.economy.ledger.owners["process:smith"].items.is_empty(), "Job yields once and empties escrow")
	var crafting := State.new()
	crafting.mine("iron_01")
	crafting.player_position = Settings.WORKBENCH
	check(crafting.economy.start_job("player", "iron_ingot"), "Player can start recipe with own material")
	advance(crafting, 5, ["test_miner", "test_smith", "test_merchant"])
	crafting.location_id = "mine"
	advance(crafting, 10, ["test_miner", "test_smith", "test_merchant"])
	check(crafting.economy.jobs["player"]["progress"] == 5, "Player crafting pauses away from workbench")
	crafting.location_id = "town"
	advance(crafting, 15, ["test_miner", "test_smith", "test_merchant"])
	check(crafting.inventory.count("test_iron_ingot") == 1 and crafting.inventory.count("test_iron_ore") == 0, "Player smelts reserved material into inventory")
	check(crafting.economy.start_job("player", "iron_tool"), "Player can craft second-stage product")
	advance(crafting, 30, ["test_miner", "test_smith", "test_merchant"])
	check(crafting.inventory.count("test_iron_tool") == 1 and crafting.economy.ledger.material_totals() == {"iron": 10, "copper": 3}, "Player crafting conserves material through two stages")
	for player_first in [true, false]:
		var race := State.new()
		race.mine("iron_01")
		race.mine("iron_01")
		var miner: Dictionary = race.life.people["test_miner"]
		miner["location"] = "mine"
		miner["position"] = Mine.DEPOSITS["iron_01"]["position"] + Vector2(0, 64)
		miner["previous"] = miner["position"]
		miner["goal"] = miner["position"]
		miner["next_decision"] = 999
		miner["activity"] = "work"
		race.economy.mining_progress = 19
		if player_first:
			race.mine("iron_01")
		advance(race, 1)
		if not player_first:
			check(race.mine("iron_01") == 0, "Player cannot steal already extracted last charge")
		check(race.resources["iron_01"] == 0 and race.economy.ledger.count("player", "test_iron_ore") + race.economy.ledger.count("npc:test_miner", "test_iron_ore") == 6, "Last charge has one owner regardless of action order")
	var baseline: Dictionary = {}
	for speed in [1, 4, 12, 60]:
		var timed := State.new()
		timed.life.clock.speed = speed
		# Одинаковый реальный размер шага; ускорение объединяет больше минут
		# в одном вызове, но состояние через трое игровых суток совпадает.
		for _frame in range(floori(8640.0 / float(speed))):
			timed.life.advance(0.25)
		if baseline.is_empty():
			baseline = timed.economy.to_save()
		check(timed.economy.to_save() == baseline, "Same economy for three days at %d×" % speed)
	var corrupt := state.to_save()
	corrupt["economy"]["ledger"]["owners"]["finished"]["test_iron_tool"] = 100
	before = state.to_save()
	check(not state.apply_save(corrupt) and state.to_save() == before, "Inconsistent duplicated stock rejected without partial load")
	corrupt = mid.to_save()
	corrupt["economy"]["jobs"]["smith"] = {"recipe": "iron_ingot", "progress": 10}
	check(not state.apply_save(corrupt), "Job without escrow rejected")
	for version in [1, 2]:
		var legacy := crafting.to_save()
		legacy["version"] = version
		legacy.erase("economy")
		if version == 1:
			legacy.erase("life")
		var migrated := State.new()
		check(migrated.apply_save(legacy), "Legacy version %d loads" % version)
		check(migrated.resources == crafting.resources and migrated.inventory.items == crafting.inventory.items and migrated.money == crafting.money, "Migration preserves old items, cash and source depletion")
	await integration()
	await finish()

func integration() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await frames()
	scene.player.position = Settings.WORKBENCH + Vector2(0, 50)
	await frames()
	scene.interact()
	check(scene.workshop.window.visible and not scene.player.input_enabled, "E opens workshop and locks movement")
	scene.world_state.mine("iron_01")
	scene.workshop.transfer_requested.emit("test_iron_ore", true)
	check(scene.world_state.inventory.count("test_iron_ore") == 0 and scene.world_state.economy.ledger.count("workshop", "test_iron_ore") == 2, "Warehouse UI transfers actual items")
	scene.workshop.transfer_requested.emit("test_iron_ore", false)
	scene.workshop.transfer_requested.emit("test_iron_ore", false)
	scene.workshop.craft_requested.emit("iron_ingot")
	check(not scene.world_state.economy.jobs["player"].is_empty(), "Workshop UI starts real player order")
	scene.close_windows()
	check(scene.player.input_enabled, "Closing workshop restores movement")
	scene.change_location("mine", Mine.SPAWN)
	var previous: int = scene.world_state.life.clock.minute
	scene.world_state.life.advance(720.0)
	await frames()
	check(scene.world_state.life.clock.minute >= previous + 1440 and int(scene.world_state.economy.produced.get("test_copper_trinket", 0)) > 0, "NPC production continues while player is in mine")
	check(not scene.npc.visible and not scene.smith.visible, "No background city rendering needed")
	check(scene.save_game("res://.godot/production_scene_save.json") and scene.load_game("res://.godot/production_scene_save.json"), "Scene transition and load preserve production")
	scene.change_location("town", Settings.WORKBENCH + Vector2(0, 50))
	scene.workshop.open(scene.world_state)
	if "--capture" in OS.get_cmdline_user_args():
		scene.workshop.tabs.current_tab = 2
		scene.world_state.life.clock.paused = true
		scene.player.get_node("Camera2D").reset_smoothing()
		await frames(15)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/production_workshop.png")
		for tab in [0, 1]:
			scene.workshop.tabs.current_tab = tab
			await frames()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/production_workshop_%d.png" % tab)
	scene.world_state.life.clock.paused = false
	scene.time_ui.refresh(scene.world_state.life, "town", true)
	scene.close_windows()
	scene.world_state.money = 20 # Явное финансирование теста интерфейса, не игровая выдача.
	var merchant = scene.resident_views["test_merchant"]
	scene.player.position = merchant.position + Vector2(0, 64)
	await frames()
	scene.interact()
	scene.social_ui.trade_button.pressed.emit()
	check(scene.economy.mode == "market", "Merchant E opens finite market")
	var index: int = scene.world_state.catalog.shops["test_merchant"]["sell_prices"].keys().find("test_copper_trinket")
	scene.economy.rows.get_child(index).get_child(2).pressed.emit()
	check(scene.world_state.inventory.count("test_copper_trinket") == 1 and scene.world_state.money == 12, "Market UI buys existing product and pays price")
	if "--capture" in OS.get_cmdline_user_args():
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/production_market.png")
	scene.queue_free()
	await process_frame

func finish() -> void:
	print("PRODUCTION TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
