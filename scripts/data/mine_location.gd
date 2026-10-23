extends RefCounted
## Все названия, запасы и выходы руды — тестовые данные, не канон.

const MAP_SIZE := Vector2(1152, 864)
const LOCATION_NAME := "Златогорье · тестовая шахта"
const SPAWN := Vector2(576, 696)
const EXIT := Vector2(576, 768)
const TOWN_ENTRANCE := Vector2(936, 240)
const TOWN_RETURN := Vector2(936, 300)
const SMITH_POSITION := Vector2(1152, 768)
## Тестовое естественное пополнение: один подход к жиле за игровые сутки.
const REGEN_MINUTES := 1440
const DEPOSITS: Dictionary = {
	"iron_01": {"position": Vector2(288, 288), "item_id": "test_iron_ore", "charges": 3, "yield": 2},
	"iron_02": {"position": Vector2(816, 288), "item_id": "test_iron_ore", "charges": 2, "yield": 2},
	"copper_01": {"position": Vector2(384, 528), "item_id": "test_copper_ore", "charges": 3, "yield": 1},
}

static func solid_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [
		Rect2(0, 0, 1152, 96), Rect2(0, 0, 96, 864),
		Rect2(1056, 0, 96, 864), Rect2(0, 816, 1152, 48),
		Rect2(528, 192, 96, 240), Rect2(768, 480, 144, 96),
	]
	for deposit in DEPOSITS.values():
		result.append(Rect2(deposit["position"] - Vector2(20, 16), Vector2(40, 32)))
	return result
