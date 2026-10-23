extends SceneTree
## Детерминированные проверки модели без визуальных узлов и проверка интеграции.

const Simulation = preload("res://scripts/simulation/resident_simulation.gd")
const State = preload("res://scripts/simulation/world_state.gd")
const SaveService = preload("res://scripts/simulation/save_service.gd")
const Definitions = preload("res://scripts/data/resident_definitions.gd")
const SLOT := "res://.godot/resident_test_save.json"
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

func frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func action(scene: Node, name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	scene._unhandled_input(event)

func run() -> void:
	var state := State.new()
	if "--verify-save" in OS.get_cmdline_user_args():
		check(SaveService.load_game(state, SLOT).is_empty(), "New process loads resident save")
		check(state.life.clock.minute == 10560, "Seven days and clock restored from disk")
		for id in state.life.people:
			var person: Dictionary = state.life.people[id]
			check(person["work_minutes"] > (300 if id == "test_miner" else 600) and person["sleep_minutes"] > 300, "Persisted history: " + id)
			check(state.life.navigation_for(person["location"]).walkable(person["position"]), "Persisted location safe: " + id)
		await finish()
		return
	var life = state.life
	for id in Definitions.PEOPLE:
		var definition: Dictionary = Definitions.PEOPLE[id]
		for key in ["spawn", "work", "home", "food", "rest", "errand"]:
			check(life.navigation.walkable(definition[key]), "Valid place: " + id + "/" + key)
	var from := Vector2(180, 400)
	var goal := Vector2(624, 400)
	var path: Array[Vector2] = life.navigation.path(from, goal)
	check(not life.navigation.clear_segment(from, goal) and not path.is_empty(), "Path found around building")
	var safe := true
	for point in path:
		safe = safe and life.navigation.clear_segment(from, point)
		from = point
	check(safe and from == goal, "Every route segment clears obstacles and reaches destination")
	var visits: Dictionary = {}
	var no_blocked := true
	var all_safe := true
	var wait_streak: Dictionary={}
	for id in life.people:
		visits[id] = {}
	# Семь суток, 10080 фиксированных шагов, без кадров и сцен.
	for _minute in range(7 * 1440):
		life.advance(0.5)
		for id in life.people:
			var person: Dictionary = life.people[id]
			visits[id][person["activity"]] = true
			visits[id]["plan:"+str(person["task"])] = true
			var hour: int=floori(float(life.clock.minute%1440)/60)
			if hour>=17 and hour<20 and person.task=="rest" and person.reason in ["fatigue","break"]:
				visits[id]["evening:recovery"]=true
			wait_streak[id]=int(wait_streak.get(id,0))+1 if person.activity=="wait" and person.reason!="conversation" else 0
			no_blocked=no_blocked and wait_streak[id]<120
			all_safe = all_safe and life.navigation_for(person["location"]).clear_segment(person["previous"], person["position"])
	check(life.clock.minute == 10560 and is_zero_approx(life.clock.fraction), "Clock advances exactly seven days")
	check(no_blocked, "No permanent blocked routes during seven days")
	check(all_safe, "Seven days of movement never cross static obstacles")
	for id in life.people:
		var person: Dictionary = life.people[id]
		for task in ["work", "sleep", "rest", "errand", "walk"]:
			# Habits may yield to real fatigue from autonomous help, never force an errand.
			var observed: bool=(visits[id].has("plan:errand") or visits[id].has("evening:recovery")) if task=="errand" else visits[id].has(task)
			check(observed, "Observed " + id + ": " + task + (" or needed evening recovery" if task=="errand" else ""))
		check(person["work_minutes"] > (300 if id == "test_miner" else 600) and person["sleep_minutes"] > 300 and person["meal_minutes"] == 0, "Sustained work and sleep without mandatory food: " + id)
		check(person["hunger"] < 80 and person["fatigue"] < 80 and person["rest_need"] < 80, "Needs remain manageable: " + id)
	check(SaveService.save_game(state, SLOT).is_empty(), "Save seven-day simulation to disk")
	var restored := State.new()
	check(SaveService.load_game(restored, SLOT).is_empty(), "Restore clock and all residents")
	check(restored.life.to_save() == life.to_save(), "Current needs, positions, goals and activities restored exactly")
	var before: Dictionary = restored.to_save()
	var bad := before.duplicate(true)
	bad["life"]["people"]["test_smith"]["hunger"] = -1
	check(not restored.apply_save(bad) and restored.to_save() == before, "Invalid resident does not partially load")
	bad = before.duplicate(true)
	bad["life"]["clock"]["speed"] = 7
	check(not restored.apply_save(bad) and restored.to_save() == before, "Invalid clock speed rejected atomically")
	bad = before.duplicate(true)
	bad["life"]["people"]["test_smith"]["position"] = [300, 400]
	check(not restored.apply_save(bad), "Resident inside building rejected")
	for i in range(90):
		restored.life.advance(0.5)
	check(restored.life.clock.minute == 10650, "Loaded simulation continues ticking")
	var saved_point: Array = before["life"]["people"]["test_miner"]["position"]
	check(restored.life.people["test_miner"]["position"] != Vector2(saved_point[0], saved_point[1]), "Loaded miner continues own activity")
	var legacy := before.duplicate(true)
	legacy["version"] = 1
	legacy.erase("life")
	legacy["money"] = 123
	check(restored.apply_save(legacy) and restored.money == 123 and restored.life.clock.minute == 480, "Version 1 save migrates without losing money")
	var slow := Simulation.new()
	var fast := Simulation.new()
	for i in range(1200):
		slow.advance(0.05)
	for i in range(7200):
		fast.advance(1.0 / 120.0)
	var same := slow.clock.minute == fast.clock.minute
	for id in slow.people:
		same = same and slow.people[id]["position"].is_equal_approx(fast.people[id]["position"])
		check(is_equal_approx(slow.people[id]["hunger"], fast.people[id]["hunger"]), "Needs independent of frame rate: " + id)
	check(same, "20 FPS and 120 FPS produce same clock and positions")
	var priority := Simulation.new()
	priority.people["test_npc"]["hunger"] = 90.0
	priority.advance(0.5)
	check(priority.people["test_npc"]["task"] == "work" and priority.people["test_npc"]["reason"] == "schedule", "Legacy hunger does not require food or override habits")
	priority = Simulation.new()
	priority.people["test_npc"]["fatigue"] = 95.0
	priority.advance(0.5)
	check(priority.people["test_npc"]["task"] == "rest", "Fatigue overrides work schedule")
	priority = Simulation.new()
	priority.people["test_npc"]["rest_need"] = 95.0
	priority.advance(0.5)
	check(priority.people["test_npc"]["reason"] == "break", "Work strain triggers a break")
	priority = Simulation.new()
	priority.clock.minute = 1080
	priority.advance(30.0, [], Vector2(936, 792))
	check(priority.people["test_npc"]["position"].distance_to(Definitions.PEOPLE["test_npc"]["errand"]) < 48, "Resident reroutes around standing player")
	priority = Simulation.new()
	priority.advance(30.0, ["test_smith"])
	check(priority.people["test_smith"]["position"] == Definitions.PEOPLE["test_smith"]["spawn"] and priority.people["test_smith"]["work_minutes"] == 0, "Conversation holds resident without adding work")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await frames()
	action(scene, "pause_game")
	var paused_snapshot: Dictionary = scene.world_state.life.to_save()
	var player_position: Vector2 = scene.player.position
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(scene.world_state.life.to_save() == paused_snapshot and scene.player.position == player_position, "P pauses time, residents and player together")
	action(scene, "npc_debug")
	await frames(15)
	check(scene.time_ui.debug_panel.visible, "Debug UI remains responsive while paused")
	action(scene, "time_speed")
	check(scene.world_state.life.clock.speed == 4, "Speed changes while paused")
	check(scene.save_game("res://.godot/resident_paused.json"), "Paused game can be saved")
	action(scene, "pause_game")
	check(scene.load_game("res://.godot/resident_paused.json") and scene.world_state.life.clock.paused, "Pause and speed survive load")
	action(scene, "pause_game")
	scene.change_location("mine", Vector2(576, 696))
	await frames()
	var previous_minute: int = scene.world_state.life.clock.minute
	var previous_view: Vector2 = scene.npc.position
	scene.world_state.life.advance(180.0)
	await frames()
	check(scene.world_state.life.clock.minute >= previous_minute + 1440, "Full day advances while player in mine")
	check(not scene.npc.visible and not scene.smith.visible and scene.npc.position == previous_view, "Off-area NPC views stay inactive")
	check(scene.world_state.economy.mined["test_iron_ore"] + scene.world_state.economy.mined["test_copper_ore"] > 0, "Miner produces real ore while player is away")
	scene.change_location("town", Vector2(864, 816))
	check(scene.npc.visible and scene.npc.position == scene.world_state.life.people["test_npc"]["position"], "Returning to town restores current simulated position")
	if "--capture" in OS.get_cmdline_user_args():
		scene.time_ui.debug_enabled = true
		scene.time_ui.selected_id = "test_miner"
		scene.player.position = Vector2(936, 480)
		scene.player.get_node("Camera2D").reset_smoothing()
		await frames(15)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/resident_debug.png")
	scene.queue_free()
	await process_frame
	await finish()

func finish() -> void:
	print("RESIDENT TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
