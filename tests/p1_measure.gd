extends SceneTree

const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const SLOT_PREFIX := "res://.godot/p1_measure_"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "verify":
		var restored := State.new()
		var start := Time.get_ticks_usec()
		var error := Service.load_game(restored, SLOT_PREFIX + args[1] + ".json")
		var elapsed := Time.get_ticks_usec() - start
		print("P1_LOAD count=%s ms=%.3f error=%s people=%d" % [args[1], elapsed / 1000.0, error, restored.life.people.size()])
		quit(0 if error.is_empty() and restored.life.people.size() == 11 + int(args[1]) else 1)
		return
	var failures := 0
	for amount in [0, 19, 39, 89]:
		var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
		var state := State.new()
		for index in range(amount):
			state.spawn_resident(Vector2(768, 864))
		state.life.minute_advanced.disconnect(state._production_tick)
		state.life.profile_enabled = true
		state.social.profile_enabled = true
		var life_usec := 0
		var production_usec := 0
		var social_usec := 0
		for minute in range(120):
			state.life.clock.minute += 1
			var phase_start := Time.get_ticks_usec()
			state.life.step()
			life_usec += Time.get_ticks_usec() - phase_start
			phase_start = Time.get_ticks_usec()
			state.economy.tick(state.life, state.location_id, state.player_position)
			production_usec += Time.get_ticks_usec() - phase_start
			phase_start = Time.get_ticks_usec()
			state.social.tick(state)
			social_usec += Time.get_ticks_usec() - phase_start
		var simulate_ms := float(life_usec + production_usec + social_usec) / 1000.0
		var profile := {"life_total_ms": life_usec / 1000.0, "decisions_ms": int(state.life.profile_usec.decisions) / 1000.0,
			"navigation_ms": int(state.life.profile_usec.navigation) / 1000.0, "production_ms": production_usec / 1000.0,
			"social_total_ms": social_usec / 1000.0, "encounters_ms": int(state.social.profile_usec.encounters) / 1000.0,
			"actions_ms": int(state.social.profile_usec.actions) / 1000.0, "social_projects_ms": int(state.social.profile_usec.projects) / 1000.0}
		var start := Time.get_ticks_usec()
		start = Time.get_ticks_usec()
		var data := state.to_save()
		var serialize_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var components: Dictionary = {}
		for key in data:
			components[key] = JSON.stringify(data[key], "\t", true, true).to_utf8_buffer().size()
		var social_parts: Dictionary = {}
		for key in data.social:
			social_parts[key] = JSON.stringify(data.social[key], "\t", true, true).to_utf8_buffer().size()
		var text := JSON.stringify(data, "\t", true, true)
		var compact_bytes := JSON.stringify(data, "", true, true).to_utf8_buffer().size()
		var count: int = 11 + int(amount)
		start = Time.get_ticks_usec()
		var error := Service.save_game(state, SLOT_PREFIX + str(amount) + ".json")
		var write_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var memory_after := Performance.get_monitor(Performance.MEMORY_STATIC)
		var disk_bytes := FileAccess.get_file_as_bytes(SLOT_PREFIX + str(amount) + ".json").size()
		if not error.is_empty() or disk_bytes != compact_bytes or disk_bytes > Service.MAX_BYTES:
			failures += 1
			push_error("SaveService failed size/integrity check for %d residents" % count)
		print("P1_RESULT count=%d simulate_ms=%.3f to_save_ms=%.3f write_ms=%.3f pretty_bytes=%d compact_bytes=%d disk_bytes=%d memory_delta_bytes=%d components=%s error=%s" % [count, simulate_ms, serialize_ms, write_ms, text.to_utf8_buffer().size(), compact_bytes, disk_bytes, memory_after - memory_before, JSON.stringify(components), error])
		print("P1_SOCIAL count=%d parts=%s" % [count, JSON.stringify(social_parts)])
		print("P1_PROFILE count=%d phases=%s" % [count, JSON.stringify(profile)])
	print("P1 MEASURE TEST: %d checks, %d failures" % [4, failures])
	quit(0 if failures == 0 else 1)
