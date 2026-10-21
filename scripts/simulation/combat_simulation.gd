extends RefCounted
## Фиксированные боевые шаги. Не зависит от спрайтов, UI или SceneTree.pause.
const RPG = preload("res://scripts/simulation/rpg_state.gd")
const Arena = preload("res://scripts/data/arena_location.gd")
const Navigation = preload("res://scripts/navigation/town_navigation.gd")
const Adit = preload("res://scripts/data/adit_location.gd")
const Psychology = preload("res://scripts/simulation/combat_psychology.gd")
const STEP := 1.0 / 60.0
var navigation := Navigation.new(Arena.solid_rects(), Arena.MAP_SIZE)
var definitions: Dictionary = Arena.ENEMIES
var dungeon_mode := false
var active_location := "arena"
var opened_gates: Dictionary = {}
var solids: Array[Rect2] = Arena.solid_rects()
var context_key := ""
var navigation_cache: Dictionary = {}
var enemies: Dictionary = {}
var projectiles: Array[Dictionary] = []
var selected_id := ""
var queued: Dictionary = {}
var fraction := 0.0
var elapsed := 0.0

func _init(enemies_data: Dictionary = Arena.ENEMIES, in_dungeon: bool = false) -> void:
	definitions = enemies_data
	dungeon_mode = in_dungeon
	for id in definitions:
		var definition: Dictionary = definitions[id]
		var enemy := RPG.new_fighter(definition.position)
		enemy.hp = definition.hp
		enemy.kind = definition.kind
		enemy.id = id
		enemy.max_hp = definition.hp
		enemy.location = definition.get("location","arena")
		enemy.ai = "guard"
		enemy.alert = 0.0
		enemy.notice = 0.0
		enemy.last_x = definition.position.x
		enemy.last_y = definition.position.y
		enemy.melee_practice = 0
		enemy.defense_practice = 0
		enemy.fear=0.0
		enemy.courage=float(definition.get("courage",65 if enemy.kind=="melee" else 35))
		enemy.motivation=float(definition.get("motivation",70 if enemy.kind=="melee" else 45))
		enemy.seen_defeats=[]
		enemy.pursuit_refused=false
		enemies[id] = enemy

func threatening(state: RefCounted) -> bool:
	if (not Adit.is_area(state.location_id) if dungeon_mode else state.location_id != "arena") or state.rpg.fighter.hp <= 0:
		return false
	for enemy in enemies.values():
		if enemy.hp > 0 and enemy.location == state.location_id and (not dungeon_mode and enemy.position.distance_to(state.rpg.fighter.position) < 540 or dungeon_mode and (enemy.ai in ["alert","chase"] or enemy.position.distance_to(state.rpg.fighter.position) < 400 and line_clear(enemy.position,state.rpg.fighter.position))):
			return true
	for shot in projectiles:
		if shot.get("location",active_location)==active_location:
			return true
	return dungeon_mode and state.adventure.threatening(state)

func update_safety(state: RefCounted) -> bool:
	sync_context(state)
	return state.life.clock.set_threat(threatening(state))

func enemy_stats(enemy: Dictionary) -> Dictionary:
	return {"max_hp": enemy.get("max_hp",65.0 if enemy.kind == "melee" else 45.0), "max_stamina": 100.0, "attack": 16.0 if enemy.kind == "melee" else 13.0, "defense": 1.0, "attack_speed": 1.0, "attack_recovery": 0.38, "move_speed": 125.0 if enemy.kind == "melee" else 110.0, "stamina_regen": 16.0, "block_reduction": 0.5}

func select_at(point: Vector2) -> String:
	var best := 40.0
	selected_id = ""
	for id in enemies:
		if enemies[id].location != active_location:
			continue
		var distance: float = enemies[id].position.distance_to(point)
		if enemies[id].hp > 0 and distance < best:
			best = distance
			selected_id = id
	return selected_id

func target_text() -> String:
	if not enemies.has(selected_id):
		return ""
	var enemy: Dictionary = enemies[selected_id]
	var activity := "Подготовка атаки!" if enemy.attack_elapsed >= 0 else "Сближение / поиск позиции"
	if dungeon_mode and enemy.attack_elapsed<0:
		activity={"guard":"Наблюдает за участком","alert":"Обнаружил игрока","chase":"Преследует цель","return":"Возвращается к месту","flee":"Отступает из-за опасности"}[enemy.ai]
	if enemy.attack_elapsed >= 0 and enemy.attack_kind == "strong":
		activity = "Сильная атака — уклоняйтесь!"
	if enemy.hp <= 0:
		activity = "Побеждён"
	return "%s · прототип\nHP %.0f / %.0f\n%s%s" % ["Ближний боец" if enemy.kind == "melee" else "Стрелок", enemy.hp, enemy_stats(enemy).max_hp, activity, "\nАтака подготовлена · Space: пуск" if not queued.is_empty() else ""]

func request_attack(state: RefCounted, aim: Vector2) -> bool:
	if state.rpg.fighter.hp <= 0:
		return false
	if state.life.clock.paused:
		queued = {"action": "attack", "aim": aim, "target": selected_id}
		return true
	return begin_attack(state.rpg.fighter, state.rpg.stats(state.catalog), aim)

func begin_attack(fighter: Dictionary, stats: Dictionary, aim: Vector2, kind: String = "normal") -> bool:
	if fighter.hp <= 0 or fighter.attack_elapsed >= 0 or fighter.cooldown > 0 or fighter.dodge_left > 0 or fighter.blocking or fighter.hurt > 0 or fighter.stamina < 12:
		return false
	fighter.stamina -= 12.0
	fighter.attack_elapsed = 0.0
	fighter.attack_kind = kind
	fighter.attack_scale = stats.attack_speed
	fighter.facing = fighter.position.direction_to(aim)
	if fighter.facing.is_zero_approx():
		fighter.facing = Vector2.RIGHT
	fighter.hit_ids.clear()
	fighter.shot = false
	fighter.attack_count += 1
	return true

func dodge(state: RefCounted, direction: Vector2) -> bool:
	var fighter: Dictionary = state.rpg.fighter
	if state.life.clock.paused or fighter.hp <= 0 or fighter.stamina < 25 or fighter.dodge_left > 0 or fighter.dodge_cooldown > 0 or fighter.hurt > 0:
		return false
	fighter.stamina -= 25.0
	fighter.dodge_left = 0.32
	fighter.dodge_cooldown = 0.9
	fighter.dodge_direction = fighter.facing if direction.is_zero_approx() else direction.normalized()
	fighter.attack_elapsed = -1.0
	fighter.blocking = false
	return true

static func invulnerable(fighter: Dictionary) -> bool:
	return fighter.dodge_left > 0.04 and fighter.dodge_left <= 0.28

static func windup(fighter: Dictionary) -> float:
	return (0.85 if fighter.attack_kind == "strong" else (0.8 if fighter.attack_kind == "ranged" else 0.18)) / fighter.attack_scale

static func active_duration(fighter: Dictionary) -> float:
	return 0.10 / fighter.attack_scale

func line_clear(from: Vector2, to: Vector2) -> bool:
	for rect in solids:
		if rect.has_point(from) or rect.has_point(to):
			return false
		var a := rect.position
		var b := Vector2(rect.end.x, rect.position.y)
		var c := rect.end
		var d := Vector2(rect.position.x, rect.end.y)
		for edge in [[a, b], [b, c], [c, d], [d, a]]:
			if Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1]) != null:
				return false
	return true

func can_hit(attacker: Dictionary, target: Dictionary, reach: float) -> bool:
	var offset: Vector2 = target.position - attacker.position
	return target.hp > 0 and offset.length() <= reach and (offset.length() < 0.1 or attacker.facing.dot(offset.normalized()) >= 0.25) and line_clear(attacker.position, target.position)

func damage(target: Dictionary, stats: Dictionary, power: float, source: Vector2) -> float:
	if target.hp <= 0 or invulnerable(target):
		return 0.0
	var incoming := maxf(1.0, power - stats.defense)
	var guard_direction: Vector2 = target.position.direction_to(source)
	if target.blocking and target.facing.dot(guard_direction) >= 0.2:
		var cost := incoming * 1.5
		if target.stamina >= cost:
			target.stamina -= cost
			incoming *= 1.0 - stats.block_reduction
		else:
			target.stamina = 0.0
			target.blocking = false
	target.hp = maxf(0.0, target.hp - incoming)
	target.hurt = 0.16
	if target.hp <= 0:
		target.attack_elapsed = -1.0
		target.blocking = false
	return incoming

func advance(state: RefCounted, real_seconds: float) -> float:
	# Safety is repeated here so callers cannot accidentally advance 60× combat.
	update_safety(state)
	if state.life.clock.paused:
		return 0.0
	var accepted: float = maxf(0, real_seconds) * state.life.clock.scale()
	fraction += accepted
	if not queued.is_empty():
		var aim: Vector2 = queued.aim
		if enemies.has(queued.target) and enemies[queued.target].hp > 0:
			aim = enemies[queued.target].position
		begin_attack(state.rpg.fighter, state.rpg.stats(state.catalog), aim)
		queued.clear()
	while fraction + 0.00000001 >= STEP:
		# Возвращающийся враг может выйти из-за угла внутри ускоренного кадра.
		# Отбрасываем оставшийся ускоренный бюджет до подготовки/попадания.
		if state.life.clock.speed>1 and threatening(state):
			state.life.clock.set_threat(true)
			accepted=maxf(0,accepted-maxf(0,fraction-STEP))
			fraction=minf(fraction,STEP)
		fraction = maxf(0, fraction - STEP)
		_tick(state, STEP)
	return accepted

func _tick(state: RefCounted, delta: float) -> void:
	elapsed += delta
	var fighter: Dictionary = state.rpg.fighter
	var stats: Dictionary = state.rpg.stats(state.catalog)
	_timers(fighter, stats, delta)
	if not Adit.is_area(state.location_id) if dungeon_mode else state.location_id != "arena":
		_resolve_attack(fighter, stats, {}, {}, 78.0, delta)
		return
	if fighter.hp <= 0:
		return
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		if enemy.hp <= 0 or enemy.location != state.location_id:
			continue
		var derived := enemy_stats(enemy)
		_timers(enemy, derived, delta)
		var distance: float = enemy.position.distance_to(fighter.position)
		if dungeon_mode:
			if _psychology(id,enemy,fighter,delta):
				continue
			_perceive(id,enemy,fighter,delta)
		if (enemy.ai == "chase" and distance < 380 and line_clear(enemy.position,fighter.position) if dungeon_mode else distance < 510):
			if enemy.attack_elapsed < 0:
				enemy.facing = enemy.position.direction_to(fighter.position)
				if enemy.kind == "melee":
					if distance <= 54 and line_clear(enemy.position, fighter.position):
						begin_attack(enemy, derived, fighter.position, "strong" if enemy.attack_count % 3 == 2 else "normal")
						# Enemy normal attacks also have a readable preparation.
						if enemy.attack_elapsed >= 0 and enemy.attack_kind == "normal":
							enemy.attack_scale = 0.4
					else:
						_move_enemy(enemy, fighter.position, derived.move_speed, delta)
				else:
					var goal: Vector2 = fighter.position
					if distance < 190:
						goal = _retreat_point(enemy.position, fighter.position)
						if goal==enemy.position:
							begin_attack(enemy,derived,fighter.position,"ranged")
					elif distance <= 350 and line_clear(enemy.position, fighter.position):
						begin_attack(enemy, derived, fighter.position, "ranged")
						goal = enemy.position
					if goal != enemy.position:
						_move_enemy(enemy, goal, derived.move_speed, delta)
			_resolve_attack(enemy, derived, {"player": fighter}, {"player": stats}, 60.0, delta, state)
	var targets: Dictionary = {}
	for id in enemies:
		if enemies[id].location == state.location_id:
			targets[id] = enemies[id]
	_resolve_attack(fighter, stats, targets, {}, 78.0, delta, state)
	if dungeon_mode:
		state.adventure.tick(state,delta)
		for id in enemies:
			if enemies[id].hp <= 0:
				state.adventure.enemy_died(state,id,enemies[id])
	_tick_projectiles(fighter, stats, delta, state)

func _timers(fighter: Dictionary, stats: Dictionary, delta: float) -> void:
	for key in ["cooldown", "dodge_left", "dodge_cooldown", "heal_cooldown", "hurt", "nav_wait", "block_left"]:
		fighter[key] = maxf(0, float(fighter[key]) - delta)
	if fighter.hp <= 0:
		return
	if fighter.blocking:
		fighter.stamina = maxf(0, fighter.stamina - delta * 6.0)
		if fighter.stamina <= 0:
			fighter.blocking = false
	elif fighter.attack_elapsed < 0 and fighter.dodge_left <= 0:
		fighter.stamina = minf(stats.max_stamina, fighter.stamina + stats.stamina_regen * delta)

func _resolve_attack(attacker: Dictionary, stats: Dictionary, targets: Dictionary, target_stats: Dictionary, reach: float, delta: float, state: RefCounted = null) -> void:
	if attacker.attack_elapsed < 0 or attacker.hp <= 0:
		return
	attacker.attack_elapsed += delta
	var preparation := windup(attacker)
	if attacker.attack_elapsed >= preparation and attacker.attack_elapsed < preparation + active_duration(attacker):
		if attacker.attack_kind == "ranged":
			if not attacker.shot:
				projectiles.append({"position": attacker.position, "direction": attacker.facing, "left": 2.4, "power": stats.attack, "shooter": attacker.get("id", ""), "location": active_location})
				attacker.shot = true
		else:
			for id in targets:
				if id not in attacker.hit_ids and can_hit(attacker, targets[id], reach):
					attacker.hit_ids.append(id)
					var derived: Dictionary = target_stats[id] if target_stats.has(id) else enemy_stats(targets[id])
					var before_stamina: float=targets[id].stamina
					var dealt: float=damage(targets[id], derived, stats.attack * (1.7 if attacker.attack_kind == "strong" else 1.0), attacker.position)
					if state!=null and dealt>0:
						if id!="player" and not state.rpg.equipment.main_hand.is_empty():
							_practice(state,targets[id],"melee")
						elif id=="player" and targets[id].blocking and targets[id].stamina<before_stamina:
							_practice(state,attacker,"defense")
	if attacker.attack_elapsed >= preparation + active_duration(attacker):
		attacker.attack_elapsed = -1.0
		attacker.cooldown = stats.attack_recovery / attacker.attack_scale

func _move_enemy(enemy: Dictionary, goal: Vector2, speed: float, delta: float) -> void:
	if enemy.hurt > 0:
		return
	if enemy.nav_wait <= 0:
		enemy.path = navigation.path(enemy.position, goal)
		enemy.nav_wait = 0.35
	if enemy.path.is_empty():
		return
	var next: Vector2 = enemy.path[0]
	var candidate: Vector2 = enemy.position.move_toward(next, speed * delta)
	if navigation.clear_segment(enemy.position, candidate):
		enemy.position = candidate
	if enemy.position.distance_to(next) < 2:
		enemy.path.pop_front()

func _retreat_point(origin: Vector2, danger: Vector2) -> Vector2:
	var best := origin
	var score := origin.distance_to(danger)
	var away := danger.direction_to(origin)
	for angle in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var candidate := origin + away.rotated(angle) * 100.0
		if navigation.walkable(candidate) and navigation.clear_segment(origin, candidate) and candidate.distance_to(danger) > score:
			best = candidate
			score = candidate.distance_to(danger)
	return best

func _tick_projectiles(fighter: Dictionary, stats: Dictionary, delta: float, state: RefCounted = null) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var shot: Dictionary = projectiles[index]
		if shot.get("location",active_location)!=active_location:
			continue
		var from: Vector2 = shot.position
		var to: Vector2 = from + shot.direction * 280.0 * delta
		shot.left -= delta
		if shot.left <= 0 or not line_clear(from, to):
			projectiles.remove_at(index)
			continue
		shot.position = to
		if Geometry2D.get_closest_point_to_segment(fighter.position, from, to).distance_to(fighter.position) <= 18:
			var before_stamina:float=fighter.stamina
			var dealt:float=damage(fighter, stats, shot.power, from - shot.direction * 30)
			if dealt>0 and state!=null and fighter.blocking and fighter.stamina<before_stamina and enemies.has(shot.get("shooter","")):
				_practice(state,enemies[shot.shooter],"defense")
			projectiles.remove_at(index)

func to_save() -> Dictionary:
	var saved: Dictionary = {}
	for id in enemies:
		saved[id] = RPG.encode_fighter(enemies[id])
	var shots: Array = []
	for shot in projectiles:
		shots.append({"position": [shot.position.x, shot.position.y], "direction": [shot.direction.x, shot.direction.y], "left": shot.left, "power": shot.power,"shooter":shot.get("shooter",""), "location":shot.get("location",active_location)})
	var order := queued.duplicate()
	if not order.is_empty():
		order.aim = [order.aim.x, order.aim.y]
	return {"enemies": saved, "projectiles": shots, "selected": selected_id, "queued": order, "fraction": fraction, "elapsed": elapsed}

func load_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("enemies") is Dictionary or data.enemies.size() != definitions.size() or not data.get("projectiles") is Array or data.projectiles.size() > 32:
		return false
	if not RPG.number(data.get("fraction"), 0, STEP) or not RPG.number(data.get("elapsed"), 0, 1000000000):
		return false
	var restored: Dictionary = {}
	for id in definitions:
		var enemy := RPG.decode_fighter(data.enemies.get(id))
		if enemy.is_empty() or enemy.get("kind") != definitions[id].kind or not navigation_for(definitions[id].get("location","arena")).walkable(enemy.position) or enemy.hp > definitions[id].hp or enemy.stamina > 100:
			return false
		for key in ["id","max_hp","location","ai","alert","notice","last_x","last_y","melee_practice","defense_practice","fear","courage","motivation","seen_defeats","pursuit_refused"]:
			if not enemy.has(key):
				enemy[key] = enemies[id][key]
		if enemy.id!=id or enemy.max_hp!=definitions[id].hp or enemy.location != definitions[id].get("location","arena") or enemy.ai not in ["guard","alert","chase","return","flee"]:
			return false
		for key in ["fear","motivation","courage"]:
			if not RPG.number(enemy.get(key,50 if key!="fear" else 0),0,100):
				return false
		if not enemy.get("seen_defeats",[]) is Array or enemy.get("seen_defeats",[]).size()>definitions.size() or not enemy.get("pursuit_refused",false) is bool:
			return false
		for ally in enemy.seen_defeats:
			if not ally is String or not definitions.has(ally):
				return false
		for key in ["alert","notice","last_x","last_y","melee_practice","defense_practice"]:
			if not RPG.number(enemy[key],0,2000):
				return false
		restored[id] = enemy
	var shots: Array[Dictionary] = []
	for shot in data.projectiles:
		if not shot is Dictionary or not RPG.number(shot.get("left"), 0, 3) or not RPG.number(shot.get("power"), 1, 1000):
			return false
		for key in ["position", "direction"]:
			if not shot.get(key) is Array or shot[key].size() != 2 or not RPG.number(shot[key][0], -10000, 10000) or not RPG.number(shot[key][1], -10000, 10000):
				return false
		var point := Vector2(shot.position[0], shot.position[1])
		var direction := Vector2(shot.direction[0], shot.direction[1])
		if not is_equal_approx(direction.length(), 1.0):
			return false
		var shooter: Variant=shot.get("shooter","")
		if not shooter is String or (not shooter.is_empty() and not restored.has(shooter)):
			return false
		var shot_area: Variant=shot.get("location","arena")
		if not shot_area is String or (shot_area not in Adit.AREAS if dungeon_mode else shot_area!="arena") or (not shooter.is_empty() and restored[shooter].location!=shot_area):
			return false
		shots.append({"position": point, "direction": direction, "left": float(shot.left), "power": float(shot.power),"shooter":shooter,"location":shot_area})
	if not data.get("selected") is String or (not data.selected.is_empty() and not restored.has(data.selected)) or not data.get("queued") is Dictionary:
		return false
	var order: Dictionary = data.queued.duplicate()
	if not order.is_empty():
		if order.get("action") != "attack" or not order.get("aim") is Array or order.aim.size() != 2 or not order.get("target") is String or (not order.target.is_empty() and not restored.has(order.target)):
			return false
		if not RPG.number(order.aim[0], -10000, 10000) or not RPG.number(order.aim[1], -10000, 10000):
			return false
		order.aim = Vector2(order.aim[0], order.aim[1])
	enemies = restored
	projectiles = shots
	selected_id = data.selected
	queued = order
	fraction = float(data.fraction)
	elapsed = float(data.elapsed)
	return true



func sync_context(state: RefCounted) -> void:
	if not dungeon_mode:
		active_location = "arena"
		return
	opened_gates = state.adventure.gates.duplicate()
	if Adit.is_area(state.location_id):
		active_location = state.location_id
	var key := active_location + str(opened_gates)
	if key != context_key:
		context_key = key
		navigation_cache.clear()
		solids = Adit.solids(active_location,opened_gates)
		navigation = navigation_for(active_location)
		for enemy in enemies.values():
			enemy.path.clear()
			enemy.nav_wait=0.0
func navigation_for(area: String) -> RefCounted:
	if not dungeon_mode:
		return navigation
	if not navigation_cache.has(area):
		navigation_cache[area] = Navigation.new(Adit.solids(area,opened_gates),Adit.SIZE)
	return navigation_cache[area]
func _perceive(id: String, enemy: Dictionary, fighter: Dictionary, delta: float) -> void:
	var sees: bool = not enemy.get("pursuit_refused",false) and enemy.position.distance_to(fighter.position) < 380 and line_clear(enemy.position,fighter.position)
	if sees:
		enemy.last_x=fighter.position.x
		enemy.last_y=fighter.position.y
		enemy.alert=6.0
		if enemy.ai in ["guard","return"]:
			enemy.ai="alert"
			enemy.notice=0.5
		if enemy.ai=="alert":
			enemy.notice=maxf(0,enemy.notice-delta)
			if enemy.notice<=0:
				enemy.ai="chase"
	else:
		enemy.alert=maxf(0,enemy.alert-delta)
		if enemy.ai in ["alert","chase"] and enemy.alert<=0:
			enemy.ai="return"
			enemy.attack_elapsed=-1.0
			enemy.path.clear()
	if enemy.ai=="return":
		var home: Vector2=definitions[id].position
		if enemy.position.distance_to(home)<4:
			enemy.ai="guard"
		else:
			_move_enemy(enemy,home,enemy_stats(enemy).move_speed,delta)
	elif enemy.ai=="chase" and not sees:
		_move_enemy(enemy,Vector2(enemy.last_x,enemy.last_y),enemy_stats(enemy).move_speed,delta)

func _psychology(id: String, enemy: Dictionary, fighter: Dictionary, delta: float) -> bool:
	if not enemy.has("fear"):
		enemy.fear=0.0
		enemy.courage=65.0 if enemy.kind=="melee" else 35.0
		enemy.motivation=70.0 if enemy.kind=="melee" else 45.0
		enemy.seen_defeats=[]
		enemy.pursuit_refused=false
	var observed_defeats: Array=[]
	for ally_id in enemies:
		var ally: Dictionary=enemies[ally_id]
		if ally_id!=id and ally.hp<=0 and ally.location==enemy.location and ally_id not in enemy.seen_defeats and enemy.position.distance_to(ally.position)<300 and line_clear(enemy.position,ally.position):
			observed_defeats.append(ally_id)
	var assessment := Psychology.evaluate(enemy,enemy,{"defeated_allies":observed_defeats,"health_fraction":enemy.hp/enemy.max_hp,"threat_distance":enemy.position.distance_to(fighter.position)},delta)
	enemy.fear=assessment.fear
	enemy.seen_defeats=assessment.seen_defeats
	enemy.pursuit_refused=assessment.pursuit_refused
	if assessment.retreat:
		enemy.ai="flee"
		enemy.attack_elapsed=-1.0
	if enemy.ai=="flee":
		var home: Vector2=definitions[id].position
		var goal: Vector2=_retreat_point(enemy.position,fighter.position) if enemy.position.distance_to(fighter.position)<220 else home
		_move_enemy(enemy,goal,enemy_stats(enemy).move_speed,delta)
		if enemy.position.distance_to(home)<5 and enemy.position.distance_to(fighter.position)>300:
			enemy.ai="guard"
		return true
	return false

func _practice(state: RefCounted, enemy: Dictionary, skill: String) -> void:
	var key:=skill+"_practice"
	if int(enemy.get(key,0))>=8:
		return
	enemy[key]=int(enemy.get(key,0))+1
	state.rpg.skills.practice(skill,true)
