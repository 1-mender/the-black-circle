extends CharacterBody2D
## Общая визуализация персонажа. Позиция узла соответствует его ступням.

@export_range(0, 7) var character_index: int = 0
@export var marker_color := Color("dfbc70")
@onready var sprite: Sprite2D = $Sprite2D

var facing_row := 0
var animation_time := 0.0
var animation_distance := 0.0
const WALK_CYCLE_DISTANCE := 96.0

func _ready() -> void:
	update_sprite(Vector2.ZERO, 0.0)

func update_sprite(direction: Vector2, delta: float, look_direction: Vector2 = Vector2.ZERO, travelled: float = -1.0) -> void:
	# Направление взгляда независимо от движения: удар/блок могут смотреть вбок.
	var facing := direction if look_direction.is_zero_approx() else look_direction
	if facing.length_squared() > 0.001:
		if absf(facing.x) > absf(facing.y):
			facing_row = 2 if facing.x > 0 else 1
		else:
			facing_row = 0 if facing.y > 0 else 3
	var frame := 1
	if direction.length_squared() > 0.001:
		if travelled >= 0.0:
			# A full two-foot cycle follows distance, including blocking and slow combat.
			animation_distance = fposmod(animation_distance + travelled, WALK_CYCLE_DISTANCE)
			frame = [1, 2, 1, 0][int(animation_distance / (WALK_CYCLE_DISTANCE / 4.0)) % 4]
		else:
			animation_time += delta
			frame = [1, 2, 1, 0][int(animation_time * 9.0) % 4]
	else:
		animation_time = 0.0
		animation_distance = 0.0
	var origin := Vector2((character_index % 4) * 144, floori(float(character_index) / 4.0) * 192)
	sprite.region_rect = Rect2(origin + Vector2(frame * 48, facing_row * 48), Vector2(48, 48))

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2(0, -4), 17, Color(0, 0, 0, 0.28))
	draw_arc(Vector2(0, -4), 18, 0, TAU, 32, marker_color, 2.0, true)

