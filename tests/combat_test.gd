extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const RPG = preload("res://scripts/simulation/rpg_state.gd")
const Arena = preload("res://scripts/data/arena_location.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const SLOT := "res://.godot/combat_test_save.json"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) < 0.000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]):
				print("Mismatch: ", key, " ", a.get(key), " / ", b.get(key))
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not same(a[i], b[i]):
				return false
		return true
	return a == b
func state_at(point: Vector2) -> RefCounted:
	var state := State.new()
	state.rpg.claim_kit(state.economy)
	state.location_id = "arena"
	state.player_position = point
	state.rpg.fighter.position = point
	state.combat.enemies.ranged_01.hp = 0.0
	return state
func step(state: RefCounted, seconds: float) -> void:
	for _i in range(roundi(seconds * 60)):
		state.combat.update_safety(state)
		state.life.advance(1.0 / 60)
		state.combat.advance(state, 1.0 / 60)
func run() -> void:
	var state := state_at(Vector2(744, 480))
	var combat = state.combat
	var player: Dictionary = state.rpg.fighter
	var enemy: Dictionary = combat.enemies.melee_01
	enemy.position = Vector2(900, 480)
	check(not combat.can_hit(player, enemy, 78), "Cannot hit outside actual range")
	enemy.position = Vector2(800, 480)
	check(combat.can_hit(player, enemy, 78), "Actual range permits a hit")
	player.position = Vector2(550, 480)
	enemy.position = Vector2(698, 480)
	check(not combat.can_hit(player, enemy, 200), "Melee blocked by actual wall")
	check(not combat.line_clear(Vector2(550, 480), Vector2(698, 480)), "Projectile line blocked by wall")
	player.position = Vector2(744, 480)
	enemy.position = Vector2(800, 480)
	enemy.cooldown = 20.0
	check(combat.request_attack(state, enemy.position), "Player starts attack")
	check(not combat.request_attack(state, enemy.position), "Cannot start another attack during preparation")
	combat.advance(state, 0.1)
	check(enemy.hp == 65, "No damage during windup")
	combat.advance(state, 0.13)
	check(enemy.hp == 48, "Active phase hits once")
	combat.advance(state, 0.1)
	check(enemy.hp == 48 and player.cooldown > 0, "One hit per swing and recovery")
	check(not combat.request_attack(state, enemy.position), "Recovery prevents attack spam")
	player.attack_elapsed = -1.0
	player.cooldown = 0.0
	player.hp = 100.0
	player.stamina = 100.0
	player.blocking = true
	player.facing = Vector2.RIGHT
	var received: float = combat.damage(player, state.rpg.stats(state.catalog), 20, player.position + Vector2(50, 0))
	check(received == 4 and player.stamina == 76, "Shield reduces hit and spends correct stamina")
	player.stamina = 1.0
	check(combat.damage(player, state.rpg.stats(state.catalog), 20, player.position + Vector2(50, 0)) == 16 and player.stamina == 0 and not player.blocking, "Insufficient stamina breaks guard")
	player.stamina = 100.0
	player.hurt = 0.0
	check(combat.dodge(state, Vector2.RIGHT), "Dodge spends resource")
	check(player.stamina == 75 and not combat.invulnerable(player), "Dodge has a short vulnerable startup")
	player.dodge_left = 0.2
	var hp: float = player.hp
	check(combat.damage(player, state.rpg.stats(state.catalog), 50, enemy.position) == 0 and player.hp == hp, "Dodge interval prevents damage")
	player.dodge_left = 0.02
	check(not combat.invulnerable(player), "Dodge invulnerability ends before recovery")
	check(not combat.dodge(state, Vector2.RIGHT), "Dodge cooldown prevents spam")
	player.dodge_left = 0.0
	player.hurt = 0.0
	player.hp = 95.0
	check(state.rpg.heal(state.economy.ledger) and player.hp == 100, "Healing cannot exceed maximum")
	player.hp = 95.0
	check(not state.rpg.heal(state.economy.ledger), "Healing cooldown prevents spam")
	var stamina: float = player.stamina
	combat.advance(state, 1.0)
	check(player.stamina > stamina, "Stamina recovers over simulation time")
	state.life.clock.paused = true
	var paused: Dictionary = state.to_save()
	step(state, 10)
	check(state.to_save() == paused, "Full pause freezes NPC, economy and combat state")
	combat.select_at(enemy.position)
	check(combat.request_attack(state, enemy.position) and not combat.queued.is_empty(), "Paused targeting queues an attack")
	player.cooldown = 0.0
	player.hurt = 0.0
	state.life.clock.paused = false
	combat.advance(state, 1.0 / 60)
	check(combat.queued.is_empty() and player.attack_elapsed >= 0, "Queued action executes on resume")
	state = state_at(Vector2(744, 480))
	state.combat.enemies.melee_01.position = Vector2(790, 480)
	state.life.clock.set_speed(60)
	check(state.combat.update_safety(state) and state.life.clock.speed == 1, "Threat cancels acceleration before simulation")
	check(not state.life.clock.set_speed(60), "High acceleration locked during threat")
	check(state.life.clock.set_speed(0.25), "Combat slow motion allowed")
	state.life.clock.set_speed(1)
	step(state, 0.1)
	check(state.rpg.fighter.hp == 100, "No lethal burst before player can react")
	state.combat.enemies.melee_01.hp = 0
	state.combat.update_safety(state)
	check(state.life.clock.speed == 1 and state.life.clock.set_speed(4), "No automatic 60x restore, ordinary speeds unlocked after threat")
	state = state_at(Vector2(744, 480))
	state.combat.enemies.melee_01.position = Vector2(790, 480)
	state.combat.enemies.melee_01.cooldown = 10.0
	state.combat.request_attack(state, Vector2(790, 480))
	state.combat.advance(state, 0.1)
	state.player_position = state.rpg.fighter.position
	state.life.clock.paused = true
	check(Service.save_game(state, SLOT).is_empty(), "Save mid-attack uses separate test slot")
	var loaded := State.new()
	check(Service.load_game(loaded, SLOT).is_empty(), "Load mid-attack")
	check(same(loaded.to_save(), state.to_save()), "Exact inventory, gear, vitals, world and paused combat restore")
	state.life.clock.paused = false
	loaded.life.clock.paused = false
	step(state, 0.2)
	step(loaded, 0.2)
	check(same(loaded.to_save(), state.to_save()), "Resumed attack identical after loading")
	var invalid: Dictionary = state.to_save()
	invalid.rpg.fighter.hp = -1
	var before: Dictionary = loaded.to_save()
	check(not loaded.apply_save(invalid) and loaded.to_save() == before, "Invalid combat save rejected atomically")
	# Ranged projectiles stop at walls and can hit in clear space.
	state = state_at(Vector2(698, 480))
	state.combat.enemies.melee_01.hp = 0
	state.combat.projectiles.append({"position": Vector2(550, 480), "direction": Vector2.RIGHT, "left": 2.0, "power": 20.0})
	step(state, 0.6)
	check(state.rpg.fighter.hp == 100 and state.combat.projectiles.is_empty(), "Projectile cannot cross a wall")
	state.combat.projectiles.append({"position": Vector2(750, 480), "direction": Vector2.LEFT, "left": 2.0, "power": 20.0})
	var flying := State.new()
	check(flying.apply_save(state.to_save()) and same(flying.combat.to_save(), state.combat.to_save()), "In-flight projectile and defeated enemy survive loading")
	step(state, 0.3)
	step(flying, 0.3)
	check(state.rpg.fighter.hp == 84, "Projectile hits actual player position")
	check(same(flying.rpg.to_save(), state.rpg.to_save()) and same(flying.combat.to_save(), state.combat.to_save()), "Loaded projectile hits exactly once at the same moment")
	# Navigation around obstacle, not straight through it.
	state = state_at(Vector2(440, 480))
	var initial: Vector2 = state.combat.enemies.melee_01.position
	var walked := true
	for _i in range(600):
		state.combat.advance(state, 1.0 / 60)
		walked = walked and state.combat.navigation.walkable(state.combat.enemies.melee_01.position)
	check(walked and state.combat.enemies.melee_01.position.distance_to(initial) > 200, "Melee navigation progresses around obstacles")
	state = state_at(Vector2(1000, 288))
	state.combat.enemies.melee_01.hp = 0
	state.combat.enemies.ranged_01.hp = 45.0
	var ranged_start: Vector2 = state.combat.enemies.ranged_01.position
	step(state, 0.5)
	check(state.combat.enemies.ranged_01.position.distance_to(state.rpg.fighter.position) > ranged_start.distance_to(state.rpg.fighter.position), "Ranged AI retreats when player approaches")
	state.rpg.fighter.position = Vector2(1000, 288)
	step(state, 4)
	check(state.rpg.fighter.hp < 100, "Ranged AI prepares and fires actual projectiles")
	var normal := state_at(Vector2(744, 480))
	var slow := state_at(Vector2(744, 480))
	slow.life.clock.set_speed(0.25)
	step(normal, 1)
	step(slow, 4)
	check(same(normal.combat.to_save(), slow.combat.to_save()) and same(normal.rpg.to_save(), slow.rpg.to_save()), "1x and 0.25x agree for equal simulation time")
	var low_fps := state_at(Vector2(744, 480))
	var high_fps := state_at(Vector2(744, 480))
	for _i in range(20):
		low_fps.combat.advance(low_fps, 0.05)
	for _i in range(120):
		high_fps.combat.advance(high_fps, 1.0 / 120)
	check(same(low_fps.combat.to_save(), high_fps.combat.to_save()), "Fixed combat steps agree at 20 and 120 FPS")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	# Спрайт должен следовать боевому направлению, а не последней клавише WASD.
	var fighter_view: Dictionary = scene.world_state.rpg.fighter
	fighter_view.attack_elapsed = 0.1
	for sample in [[Vector2.UP, 3], [Vector2.RIGHT, 2], [Vector2.DOWN, 0], [Vector2.LEFT, 1]]:
		fighter_view.facing = sample[0]
		scene.player._physics_process(0.0)
		check(scene.player.facing_row == sample[1], "Attack sprite faces sector: " + str(sample[0]))
	check(scene.player.animation_time == 0, "Stationary attack does not play walking animation")
	fighter_view.facing = Vector2.UP
	Input.action_press("move_right")
	scene.player._physics_process(0.0)
	Input.action_release("move_right")
	check(scene.player.facing_row == 3 and fighter_view.facing == Vector2.UP, "Strafing does not turn sprite away from attack sector")
	fighter_view.attack_elapsed = -1.0
	fighter_view.blocking = true
	fighter_view.facing = Vector2.LEFT
	scene.player._physics_process(0.0)
	check(scene.player.facing_row == 1, "Block sprite faces defensive sector")
	fighter_view.blocking = false
	Input.action_press("move_down")
	scene.player._physics_process(0.0)
	Input.action_release("move_down")
	check(scene.player.facing_row == 0, "Normal movement still controls facing outside attack and block")
	scene.player.position = Arena.TOWN_ENTRANCE + Vector2(0, -35)
	await physics_frame
	check(scene.interaction_target().get("kind") == "arena", "Town portal reachable")
	scene.interact()
	await physics_frame
	check(scene.world_state.location_id == "arena", "Existing E interaction enters arena")
	scene.player.position = Arena.EXIT
	await physics_frame
	scene.interact()
	await physics_frame
	check(scene.world_state.location_id == "town", "Arena exit returns to working town")
	scene.change_location("arena", Vector2(744, 480))
	await physics_frame
	scene.world_state.life.clock.set_speed(60)
	var minute_before: int = scene.world_state.life.clock.minute
	await physics_frame
	await physics_frame
	check(scene.world_state.life.clock.speed == 1 and scene.world_state.life.clock.minute <= minute_before + 1 and scene.world_state.rpg.fighter.hp == 100, "Scene clamps 60x before world clock or enemy strike")
	scene._toggle_pause()
	var before_pause: Dictionary = scene.world_state.to_save()
	await physics_frame
	await physics_frame
	check(scene.world_state.to_save() == before_pause, "Scene tactical pause freezes all saved simulation fields")
	scene._toggle_pause()
	scene.world_state.rpg.fighter.hp = 0
	await physics_frame
	await process_frame
	check(scene.ui.defeat_panel.visible and not scene.player.input_enabled, "Defeat screen disables player movement")
	scene._recover()
	await physics_frame
	check(scene.world_state.location_id == "town" and scene.world_state.rpg.fighter.hp == 100, "Safe recovery without permanent death")
	var disjoint: bool = scene.world_state.combat.enemies.size()==2
	for id in scene.world_state.life.people:
		disjoint=disjoint and not scene.world_state.combat.enemies.has(id)
	check(disjoint, "Peaceful residents never enter hostile roster")
	scene.queue_free()
	await process_frame
	print("COMBAT TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
