extends Node2D
const Adit = preload("res://scripts/data/adit_location.gd")
const ENEMY_TEXTURE = preload("res://asset/characters/Evil.png")
const Icons = preload("res://scripts/ui/item_icons.gd")
## Только визуальное представление боевой модели. Мирные жители сюда не входят.
var state: RefCounted
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	if state == null:
		return
	var combat = state.combat
	var fighter: Dictionary = state.rpg.fighter
	if not Adit.is_area(state.location_id):
		for owner_id in state.adventure.drops:
			var pile: Dictionary=state.adventure.drops[owner_id]
			var items: Dictionary=state.economy.ledger.owners[owner_id].items
			if pile.area==state.location_id and not items.is_empty():
				draw_circle(pile.position,18,Color("675838"))
				draw_texture_rect(Icons.texture(items.keys()[0]),Rect2(pile.position-Vector2(16,24),Vector2(32,32)),false)
	if state.location_id == "arena" or Adit.is_area(state.location_id):
		for id in combat.enemies:
			var enemy: Dictionary = combat.enemies[id]
			if enemy.location!=state.location_id:
				continue
			var point: Vector2 = enemy.position
			if enemy.hp <= 0:
				draw_line(point - Vector2(12, 12), point + Vector2(12, 12), Color("6f756d"), 4)
				draw_line(point + Vector2(-12, 12), point + Vector2(12, -12), Color("6f756d"), 4)
				continue
			var color := Color("ba7463") if enemy.kind == "melee" else Color("9b81b2")
			if enemy.hurt > 0:
				color = Color("ffccab")
			draw_circle(point, 20, Color("1e2925"))
			if Adit.is_area(state.location_id):
				var row:=0
				if absf(enemy.facing.x)>absf(enemy.facing.y):
					row=2 if enemy.facing.x>0 else 1
				elif enemy.facing.y<0:
					row=3
				draw_texture_rect_region(ENEMY_TEXTURE,Rect2(point-Vector2(24,48),Vector2(48,48)),Rect2(48 if enemy.kind=="melee" else 192,row*48,48,48),Color("ffb19b") if enemy.hurt>0 else Color.WHITE)
				if enemy.ai=="alert":
					draw_arc(point,32,0,TAU,24,Color("f0bd71"),3)
			elif enemy.kind == "melee":
				draw_rect(Rect2(point - Vector2(14, 25), Vector2(28, 32)), color)
			else:
				draw_colored_polygon(PackedVector2Array([point + Vector2(0, -30), point + Vector2(19, 5), point + Vector2(-19, 5)]), color)
			draw_line(point, point + enemy.facing * 26, Color("f4ddab"), 3)
			if id == combat.selected_id:
				draw_arc(point, 27, 0, TAU, 32, Color("ffdc8a"), 2)
			draw_rect(Rect2(point + Vector2(-22, -42), Vector2(44, 5)), Color("332d2b"))
			draw_rect(Rect2(point + Vector2(-22, -42), Vector2(44 * enemy.hp / combat.enemy_stats(enemy).max_hp, 5)), Color("c87866"))
			_telegraph(enemy, 60, combat)
		for shot in combat.projectiles:
			if shot.get("location",state.location_id)!=state.location_id:
				continue
			draw_circle(shot.position, 5, Color("f5cc85"))
			draw_line(shot.position, shot.position - shot.direction * 16, Color("db8662"), 3)
	_player_attack(fighter, combat)
	if fighter.blocking:
		_player_guard(fighter)
	if combat.invulnerable(fighter):
		draw_arc(fighter.position, 25, 0, TAU, 24, Color("b8eddf"), 2)
	if not combat.queued.is_empty() and (state.location_id == "arena" or Adit.is_area(state.location_id)):
		var aim: Vector2 = combat.queued.aim
		if combat.enemies.has(combat.queued.target):
			aim = combat.enemies[combat.queued.target].position
		draw_dashed_line(fighter.position, aim, Color("f2d27f"), 2, 10)

func _player_attack(fighter: Dictionary, combat: RefCounted) -> void:
	if fighter.attack_elapsed < 0:
		if fighter.attack_count > 0 and fighter.cooldown > 0:
			var recovery: float = state.rpg.stats(state.catalog).attack_recovery / maxf(0.01, fighter.attack_scale)
			var since: float = recovery - fighter.cooldown
			if since >= 0 and since < 0.14:
				var alpha: float = 1.0 - since / 0.14
				var last_angle: float = fighter.facing.angle() + 1.1
				draw_arc(fighter.position, 56, fighter.facing.angle() - 0.2, last_angle, 14, Color(0.9, 0.7, 0.4, alpha * 0.25), 5)
				_draw_player_blade(fighter.position, Vector2.from_angle(last_angle), alpha * 0.65)
		return
	var wind: float = combat.windup(fighter)
	var active: float = combat.active_duration(fighter)
	var facing: Vector2 = fighter.facing.normalized()
	if facing.is_zero_approx():
		facing = Vector2.RIGHT
	var base_angle := facing.angle()
	var elapsed: float = fighter.attack_elapsed
	var sweep: float = clampf((elapsed - wind) / maxf(0.01, active), 0.0, 1.0)
	var blade_angle: float = base_angle - 1.1 + 2.2 * sweep
	if elapsed < wind:
		_draw_player_blade(fighter.position, Vector2.from_angle(base_angle - 1.1), 0.75)
		var cue: float = clampf(elapsed / maxf(0.01, wind), 0.0, 1.0)
		draw_arc(fighter.position, 52, base_angle - 1.25, base_angle - 1.25 + cue * 0.45, 8, Color(0.82, 0.66, 0.39, 0.45), 2)
	else:
		var start: float = base_angle - 1.1
		var end: float = blade_angle
		draw_arc(fighter.position, 56, start, end, 18, Color(0.91, 0.68, 0.35, 0.38), 10)
		draw_arc(fighter.position, 59, start, end, 18, Color(1.0, 0.9, 0.69, 0.82), 3)
		_draw_player_blade(fighter.position, Vector2.from_angle(blade_angle), 1.0)

func _draw_player_blade(point: Vector2, direction: Vector2, alpha: float) -> void:
	var hand: Vector2 = point + Vector2(0, -22) + direction * 14
	var side: Vector2 = direction.orthogonal()
	if state.rpg.equipment.main_hand.is_empty():
		var fist: Vector2 = hand + direction * 21
		draw_line(hand, fist, Color(0.55, 0.39, 0.28, alpha), 8)
		draw_circle(fist, 5, Color(0.85, 0.65, 0.46, alpha))
		return
	var tip: Vector2 = hand + direction * 43
	draw_line(hand, tip, Color(0.23, 0.25, 0.26, alpha), 8)
	draw_line(hand + direction * 5, tip, Color(0.76, 0.81, 0.78, alpha), 5)
	draw_line(hand + direction * 9, tip, Color(0.96, 0.94, 0.81, alpha), 2)
	draw_line(hand - side * 9, hand + side * 9, Color(0.68, 0.5, 0.28, alpha), 5)
	draw_circle(hand - direction * 5, 4, Color(0.77, 0.6, 0.34, alpha))

func _player_guard(fighter: Dictionary) -> void:
	var facing: Vector2 = fighter.facing.normalized()
	if facing.is_zero_approx():
		facing = Vector2.DOWN
	var side: Vector2 = facing.orthogonal()
	var center: Vector2 = fighter.position + Vector2(0, -22) + facing * 26
	if state.rpg.equipment.off_hand.is_empty():
		draw_arc(fighter.position, 30, facing.angle() - 0.75, facing.angle() + 0.75, 16, Color("b99a61"), 4)
		draw_line(center - side * 9, center + side * 9, Color("d5ae78"), 7)
		return
	var rim := PackedVector2Array([center - side * 14 - facing * 5, center + side * 14 - facing * 5, center + side * 12 + facing * 8, center + facing * 16, center - side * 12 + facing * 8])
	var face := PackedVector2Array([center - side * 10 - facing * 2, center + side * 10 - facing * 2, center + side * 8 + facing * 6, center + facing * 12, center - side * 8 + facing * 6])
	draw_arc(fighter.position, 34, facing.angle() - 0.85, facing.angle() + 0.85, 16, Color(0.73, 0.64, 0.45, 0.38), 2)
	draw_colored_polygon(rim, Color("b99a61"))
	draw_colored_polygon(face, Color("4d5c60"))
	draw_line(center - side * 6, center + side * 6, Color("9ba9a2"), 3)
	draw_circle(center + facing * 4, 3, Color("e1bc74"))
func _telegraph(fighter: Dictionary, reach: float, combat: RefCounted) -> void:
	if fighter.attack_elapsed < 0:
		return
	var wind: float = combat.windup(fighter)
	var preparing: bool = fighter.attack_elapsed < wind
	var color := Color("e2af60", 0.55) if preparing else Color("fff0be", 0.95)
	if preparing and fighter.attack_kind == "strong":
		color = Color("f18a6a", 0.85)
	var angle: float = fighter.facing.angle()
	var point: Vector2 = fighter.position
	if preparing:
		draw_arc(point, 24, -PI / 2, -PI / 2 + TAU * fighter.attack_elapsed / wind, 24, color, 3)
	if fighter.attack_kind == "ranged":
		draw_dashed_line(point, point + fighter.facing * 360, color, 2, 12)
	else:
		draw_arc(point, reach, angle - 1.25, angle + 1.25, 32, color, 3 if preparing else 6)
		draw_line(point, point + Vector2.from_angle(angle - 1.25) * reach, color, 1)
		draw_line(point, point + Vector2.from_angle(angle + 1.25) * reach, color, 1)
