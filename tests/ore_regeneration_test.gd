extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const SLOT := "res://.godot/ore_regeneration_test.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func advance(world: RefCounted, minutes: int) -> void:
	var held: Array[String] = ["test_miner"]
	for _minute in range(minutes):
		world.life.advance(0.5 / world.life.clock.speed, held)

func empty_sources(world: RefCounted) -> void:
	for site in Mine.DEPOSITS:
		var deposit: Dictionary = Mine.DEPOSITS[site]
		while int(world.resources[site]) > 0:
			world.economy.ledger.transfer("source:" + site, "player", deposit.item_id, int(deposit["yield"]))

func run() -> void:
	var baseline: Dictionary = {}
	for speed in [1.0, 4.0, 12.0, 60.0]:
		var world := State.new()
		world.life.clock.speed = speed
		empty_sources(world)
		check(world.resources == {"iron_01": 0, "iron_02": 0, "copper_01": 0}, "All shared sources are exhausted at %sx" % speed)
		var initial_budget: Dictionary = world.economy.material_budget.duplicate()
		world.life.clock.paused = true
		advance(world, Mine.REGEN_MINUTES)
		check(world.life.clock.minute == 480 and world.resources.iron_01 == 0, "Pause prevents regeneration at %sx" % speed)
		world.life.clock.paused = false
		advance(world, 959)
		check(world.life.clock.minute == 1439 and world.resources.iron_01 == 0, "Sources stay depleted until the next game-day boundary at %sx" % speed)
		if speed == 1.0:
			check(Service.save_game(world, SLOT).is_empty(), "Pre-renewal world saves to a separate test slot")
		advance(world, 1)
		check(world.life.clock.minute == 1440 and world.resources == {"iron_01": 1, "iron_02": 1, "copper_01": 1}, "Each source regains one charge at %sx" % speed)
		check(world.economy.material_budget == {"iron": int(initial_budget.iron) + 4, "copper": int(initial_budget.copper) + 1} and world.economy.ledger.material_totals() == world.economy.material_budget, "New ore is explicit in the material budget at %sx" % speed)
		if baseline.is_empty():
			baseline = {"resources": world.resources.duplicate(), "budget": world.economy.material_budget.duplicate()}
		else:
			check(world.resources == baseline.resources and world.economy.material_budget == baseline.budget, "Equal game time gives equal renewal at %sx" % speed)
		if speed == 1.0:
			var restored := State.new()
			check(Service.load_game(restored, SLOT).is_empty() and restored.resources.iron_01 == 0, "Pre-renewal save loads without early ore")
			advance(restored, 1)
			check(restored.resources == world.resources and restored.economy.material_budget == world.economy.material_budget, "Loading before renewal applies the same single scheduled event")
			check(Service.save_game(world, SLOT).is_empty(), "Post-renewal state saves")
			var again := State.new()
			check(Service.load_game(again, SLOT).is_empty() and again.resources == world.resources and again.economy.material_budget == world.economy.material_budget, "Loading after renewal does not duplicate ore")
			advance(again, Mine.REGEN_MINUTES - 1)
			check(again.resources == world.resources, "No second renewal before another complete game day")
			advance(again, 1)
			check(again.resources.iron_01 == 2 and again.resources.copper_01 == 2, "Renewal continues on later days")
			advance(again, Mine.REGEN_MINUTES * 3)
			check(again.resources.iron_01 == 3 and again.resources.iron_02 == 2 and again.resources.copper_01 == 3, "Regeneration never exceeds each deposit's original capacity")
	print("ORE REGENERATION TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
