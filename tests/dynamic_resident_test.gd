extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const MainScene = preload("res://scenes/main.tscn")
const SLOT := "res://.godot/dynamic_resident_test.json"
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

func run() -> void:
	var state := State.new()
	var id: String = state.spawn_resident(Vector2(768, 864))
	check(not id.is_empty(), "New NPC can appear during a running game")
	if id.is_empty():
		quit(1)
		return
	check(state.life.people.has(id) and state.social.characters.has(id) and state.economy.ledger.owners.has("npc:" + id) and state.economy.ledger.owners.has("process:social:" + id), "One action registers life, social identity and property")
	check(state.life.definitions[id].profession == "metalworker" and state.social.characters[id].traits.size() == 5, "New worker has a profession and complete personality")
	var replay := State.new()
	var replay_id: String = replay.spawn_resident(Vector2(768, 864))
	check(replay_id == id and replay.social.characters[replay_id].traits == state.social.characters[id].traits, "Same seed and creation order reproduce personality")
	var other: String = state.spawn_resident(Vector2(768, 864))
	check(other != id and state.social.characters[other].traits != state.social.characters[id].traits, "Stable IDs and seed produce varied identities")
	state.life.advance(60.0)
	check(state.life.clock.minute > 0 and state.life.people[id].work_minutes + state.life.people[id].sleep_minutes > 0, "Generated resident uses common daily simulation")
	var action: Dictionary = state.social.execute(state, id, "test_apprentice", "talk")
	check(bool(action.get("ok", false)) and state.social.characters[id].memory.size() > 0, "Generated resident uses common social actions and memory")
	var first_contact_count: int = state.social.history.size()
	state.life.advance(1440.0)
	check(state.social.history.size() > first_contact_count and state.life.people[id].work_minutes > 0, "Generated resident continues common work and social life across days")
	var before: Dictionary = state.to_save()
	check(Service.save_game(state, SLOT).is_empty(), "Dynamic population saves outside the user slot")
	var loaded := State.new()
	var load_message: String = Service.load_game(loaded, SLOT)
	check(load_message.is_empty(), "Dynamic population loads")
	check(loaded.life.people.has(id) and loaded.social.characters.has(id) and loaded.economy.ledger.owners.has("npc:" + id), "Life, personality and property restore together")
	if loaded.social.characters.has(id):
		check(loaded.social.characters[id].traits == state.social.characters[id].traits and JSON.parse_string(JSON.stringify(loaded.social.characters[id].memory)) == JSON.parse_string(JSON.stringify(state.social.characters[id].memory)), "Personality and history persist")
		check(JSON.parse_string(JSON.stringify(loaded.to_save())) == JSON.parse_string(JSON.stringify(before)), "Round-trip preserves all dynamic state")
	var old_slot: Dictionary = State.new().to_save()
	old_slot.version = 6
	old_slot.erase("resident_seed")
	old_slot.erase("next_resident_id")
	old_slot.life.erase("definitions")
	check(loaded.apply_save(old_slot) and loaded.life.people.size() == 11 and loaded.next_resident_id == 1, "Loading an older slot removes transient residents and resets the runtime ID sequence")
	var previous_p1: Dictionary = state.to_save()
	previous_p1.economy.erase("workers")
	check(State.new().apply_save(previous_p1), "Earlier P1 slots without production workers remain loadable")
	for amount in [30, 100]:
		var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
		var bench := State.new()
		var start := Time.get_ticks_usec()
		for index in range(amount):
			var created: String = bench.spawn_resident(Vector2(768, 864))
			if created.is_empty():
				break
		var create_ms := float(Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		bench.life.advance(60.0)
		var simulate_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var save_bytes := JSON.stringify(bench.to_save(), "\t", true, true).to_utf8_buffer().size()
		var memory_after := Performance.get_monitor(Performance.MEMORY_STATIC)
		print("BENCH %d: create_ms=%.2f simulate_120_minutes_ms=%.2f memory_before_bytes=%d memory_after_bytes=%d memory_delta_bytes=%d save_bytes=%d" % [amount, create_ms, simulate_ms, memory_before, memory_after, memory_after - memory_before, save_bytes])
		check(bench.life.people.size() == 11 + amount, "%d generated residents join the shared model" % amount)
		check(save_bytes <= Service.MAX_BYTES, "%d residents fit current save limit" % amount)
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	var visible_id: String = scene.world_state.spawn_resident(Vector2(768,864))
	scene._sync_residents(0.0, true)
	check(scene.resident_views.has(visible_id) and scene.resident_views[visible_id].visible, "New NPC receives a live scene representation")
	scene.selected_resident = visible_id
	scene.player.position = Vector2(768,864)
	check(scene.interaction_target().get("id","") == visible_id, "Interaction selection can target a generated resident")
	scene.queue_free()
	print("DYNAMIC RESIDENT TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
