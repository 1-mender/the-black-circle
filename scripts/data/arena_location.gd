extends RefCounted
## Полигон и противники — только технические прототипы, не новый канон.
const LOCATION_NAME := "Боевой полигон · тестовая область"
const MAP_SIZE := Vector2(1440, 960)
const SPAWN := Vector2(192, 768)
const EXIT := Vector2(144, 816)
const TOWN_ENTRANCE := Vector2(1008, 1104)
const TOWN_RETURN := Vector2(1008, 1032)
const ENEMIES := {"melee_01": {"kind": "melee", "position": Vector2(816, 480), "hp": 65.0}, "ranged_01": {"kind": "ranged", "position": Vector2(1152, 288), "hp": 45.0}}
static func solid_rects() -> Array[Rect2]:
	return [Rect2(0, 0, 1440, 48), Rect2(0, 912, 1440, 48), Rect2(0, 0, 48, 960), Rect2(1392, 0, 48, 960), Rect2(576, 336, 96, 288), Rect2(864, 624, 288, 48)]
