extends RefCounted
## Геометрия технической карты. Размеры и позиции заданы в мировых пикселях.

const CELL_SIZE := 48
const MAP_SIZE := Vector2(1824, 1248)
const LOCATION_NAME := "Златогорье · тестовая территория"
const PLAYER_SPAWN := Vector2(864, 816)
const NPC_SPAWN := Vector2(1008, 672)
const NPC_ID := "test_npc"
const BUILDINGS: Array[Rect2] = [
	Rect2(240, 288, 336, 240),
	Rect2(1248, 336, 336, 240),
	Rect2(288, 864, 288, 192),
	Rect2(1296, 864, 288, 192),
]
const ROCKS: Array[Rect2] = [
	Rect2(624, 624, 96, 72), Rect2(1152, 960, 96, 72),
]
const TREES: Array[Vector2] = [
	Vector2(144, 624), Vector2(192, 768), Vector2(672, 1104),
	Vector2(1152, 288), Vector2(1680, 720), Vector2(1680, 1008),
	Vector2(720, 336), Vector2(1104, 1104),
]
const ROADS: Array[Rect2] = [Rect2(768,192,336,1008),Rect2(48,672,1728,144),Rect2(720,528,432,384)]
const MOUNTAIN := Rect2(48, 48, 1728, 144)

static func solid_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.append_array(BUILDINGS)
	result.append_array(ROCKS)
	result.append(MOUNTAIN)
	for tree in TREES:
		result.append(Rect2(tree - Vector2(12, 12), Vector2(24, 24)))
	# Граница мира видна как каменная ограда и совпадает с коллизиями.
	result.append(Rect2(0, 0, MAP_SIZE.x, 48))
	result.append(Rect2(0, MAP_SIZE.y - 48, MAP_SIZE.x, 48))
	result.append(Rect2(0, 0, 48, MAP_SIZE.y))
	result.append(Rect2(MAP_SIZE.x - 48, 0, 48, MAP_SIZE.y))
	return result
