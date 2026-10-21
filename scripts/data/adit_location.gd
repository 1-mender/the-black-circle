extends RefCounted
## Ручная тестовая штольня. Имена и награды не являются каноническим лором.
const SIZE := Vector2(1536,1056)
const TOWN_ENTRANCE := Vector2(816, 432)
const TOWN_RETURN := Vector2(816, 504)
const SPAWN := Vector2(240,864)
const AREAS := ["adit_entry", "adit_depths"]
const NAMES := {"adit_entry": "Заброшенная штольня · вход (тест)", "adit_depths": "Заброшенная штольня · глубины (тест)"}
const CONTAINERS := {
	"supplies": {"area":"adit_entry", "point":Vector2(240,816), "name":"Оставленные припасы", "items":{"test_sword":1,"test_shield":1,"test_heal":3,"test_food":2}},
	"key_cache": {"area":"adit_entry", "point":Vector2(240,240), "name":"Тайник у креплений", "items":{"test_adit_key":1,"test_copper_ore":2}},
	"materials": {"area":"adit_depths", "point":Vector2(240,240), "name":"Складской ящик", "items":{"test_iron_ingot":1,"test_heal":2}},
	"reward": {"area":"adit_depths", "point":Vector2(1296,240), "name":"Дальний тайник", "items":{"test_adit_ring":1,"test_armor":1,"test_iron_ore":2}},
}
const VEINS := {
	"entry_ore":{"area":"adit_entry","point":Vector2(864,672),"item":"test_iron_ore","count":4},
	"deep_ore":{"area":"adit_depths","point":Vector2(1296,816),"item":"test_copper_ore","count":3},
}
const GATES := {
	"iron_gate":{"area":"adit_entry","rect":Rect2(1056,480,48,144),"point":Vector2(1032,552),"name":"Решётка · нужен найденный ключ"},
	"rubble":{"area":"adit_depths","rect":Rect2(1008,672,48,144),"point":Vector2(984,744),"name":"Завал · найдите ворот в боковом зале"},
}
const LEVER := Vector2(288,240)
const TRAPS := {
	"spikes":{"area":"adit_entry","point":Vector2(528,792),"kind":"spikes"},
	"falling":{"area":"adit_depths","point":Vector2(768,720),"kind":"falling"},
}
const ENEMIES := {
	"adit_guard":{"kind":"melee","position":Vector2(384,384),"hp":45.0,"location":"adit_entry","items":{"test_iron_ore":1}},
	"adit_archer":{"kind":"ranged","position":Vector2(912,480),"hp":35.0,"location":"adit_entry","items":{"test_heal":1}},
	"deep_guard":{"kind":"melee","position":Vector2(768,816),"hp":50.0,"location":"adit_depths","items":{"test_iron_ore":2}},
	"deep_archer":{"kind":"ranged","position":Vector2(1296,384),"hp":40.0,"location":"adit_depths","items":{"test_copper_ore":1}},
}
static func is_area(area: String) -> bool:
	return area in AREAS
static func floors(area: String) -> Array[Rect2]:
	var cells: Array[Rect2]
	if area == "adit_entry":
		cells = [Rect2(2,14,8,6),Rect2(12,9,9,8),Rect2(2,3,8,7),Rect2(24,3,6,8),Rect2(8,15,6,3),Rect2(4,9,3,7),Rect2(8,5,6,3),Rect2(12,5,3,7),Rect2(19,10,8,3)]
	else:
		cells = [Rect2(2,13,7,7),Rect2(11,10,9,8),Rect2(24,13,6,7),Rect2(23,2,7,7),Rect2(2,2,8,7),Rect2(7,15,6,3),Rect2(5,7,3,10),Rect2(18,5,7,3),Rect2(17,5,3,9),Rect2(18,14,8,3),Rect2(26,7,3,8)]
	var result: Array[Rect2] = []
	for cell in cells:
		result.append(Rect2(cell.position*48,cell.size*48))
	return result
static func floor_at(area: String, point: Vector2) -> bool:
	for room in floors(area):
		if room.has_point(point):
			return true
	return false
static func solids(area: String, opened: Dictionary = {}) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for y in range(22):
		var start := -1
		for x in range(33):
			var wall: bool = x < 32 and not floor_at(area, Vector2(x*48+24,y*48+24))
			if wall and start < 0:
				start = x
			if not wall and start >= 0:
				result.append(Rect2(start*48,y*48,(x-start)*48,48))
				start = -1
	if area == "adit_entry":
		result.append_array([Rect2(720,528,96,96),Rect2(336,192,48,96),Rect2(1296,240,48,96)])
	else:
		result.append_array([Rect2(672,576,96,96),Rect2(1200,720,48,96),Rect2(288,288,96,48)])
	for id in GATES:
		if GATES[id].area == area and not opened.get(id,false):
			result.append(GATES[id].rect)
	return result
static func fixed_owners() -> Array[String]:
	var result: Array[String] = []
	for id in CONTAINERS:
		result.append("chest:"+id)
	for id in VEINS:
		result.append("vein:"+id)
	for id in ENEMIES:
		result.append("enemy:"+id)
	return result

