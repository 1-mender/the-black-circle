extends "res://scripts/actors/actor.gd"

@export var speed := 210.0
var input_enabled := true
var rpg: RefCounted
var time_scale := 1.0
var combat_enabled := false

func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if input_enabled:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	if rpg != null:
		var fighter: Dictionary = rpg.fighter
		if fighter.hp <= 0:
			velocity = Vector2.ZERO
		elif fighter.dodge_left > 0:
			velocity = fighter.dodge_direction * 520.0 if input_enabled else Vector2.ZERO
		elif fighter.blocking:
			velocity *= 0.45
		elif fighter.attack_elapsed >= 0:
			velocity *= 0.35
		if fighter.hurt > 0:
			velocity *= 0.3
		velocity *= time_scale
		if not direction.is_zero_approx() and fighter.attack_elapsed < 0 and not fighter.blocking:
			fighter.facing = direction
		modulate = Color("ff8880") if fighter.hurt > 0 else (Color("a1d9f3") if fighter.dodge_left > 0 else Color.WHITE)
	var previous_position := position
	move_and_slide()
	var displacement := position - previous_position
	var look_direction := Vector2.ZERO
	if rpg != null and (rpg.fighter.attack_elapsed >= 0 or rpg.fighter.blocking):
		look_direction = rpg.fighter.facing
	if look_direction.is_zero_approx():
		look_direction = direction
	update_sprite(displacement, delta * time_scale, look_direction, displacement.length())
	if rpg != null:
		_update_combat_pose(rpg.fighter)
		rpg.fighter.position = position

func _update_combat_pose(fighter: Dictionary) -> void:
	sprite.position = Vector2(0, -24)
	var pose_frame := -1
	if fighter.blocking:
		pose_frame = 1
		sprite.position -= fighter.facing.normalized() * 2.0
	elif fighter.attack_elapsed >= 0:
		var windup: float = (0.85 if fighter.attack_kind == "strong" else 0.18) / maxf(0.01, fighter.attack_scale)
		pose_frame = 0 if fighter.attack_elapsed < windup else 2
		sprite.position += fighter.facing.normalized() * (-2.0 if pose_frame == 0 else 4.0)
	if pose_frame >= 0:
		var region: Rect2 = sprite.region_rect
		region.position.x = (character_index % 4) * 144 + pose_frame * 48
		sprite.region_rect = region
