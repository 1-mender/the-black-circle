extends RefCounted
## Adapter over authoritative area geometry; no NPCs, loot, traps or secret markers.
const Town=preload("res://scripts/data/test_location.gd")
const Mine=preload("res://scripts/data/mine_location.gd")
const Arena=preload("res://scripts/data/arena_location.gd")
const Adit=preload("res://scripts/data/adit_location.gd")
const AREAS=["town","mine","arena","adit_entry","adit_depths"]
const CELL=48
static func bounds(area: String) -> Vector2:
	return Adit.SIZE if Adit.is_area(area) else Mine.MAP_SIZE if area=="mine" else Arena.MAP_SIZE if area=="arena" else Town.MAP_SIZE
static func columns(area: String) -> int:
	return ceili(bounds(area).x/CELL)
static func count(area: String) -> int:
	return columns(area)*ceili(bounds(area).y/CELL)
static func walls(area: String, gates: Dictionary) -> Array[Rect2]:
	return Adit.solids(area,gates) if Adit.is_area(area) else Mine.solid_rects() if area=="mine" else Arena.solid_rects() if area=="arena" else Town.solid_rects()
static func title(area: String) -> String:
	return {"town":"Златогорье","mine":"Шахта","arena":"Боевой полигон","adit_entry":"Заброшенная штольня · вход","adit_depths":"Заброшенная штольня · глубины"}.get(area,"Местность")
static func exits(area: String) -> Array[Vector2]:
	var points: Array[Vector2]=[]
	match area:
		"town": points=[Mine.TOWN_ENTRANCE,Arena.TOWN_ENTRANCE,Adit.TOWN_ENTRANCE]
		"mine": points=[Mine.EXIT]
		"arena": points=[Arena.EXIT]
		"adit_entry": points=[Vector2(144,912),Vector2(1320,384)]
		"adit_depths": points=[Vector2(144,864)]
	return points

static func exit_name(area: String, index: int) -> String:
	return ["В шахту","На полигон","В штольню"][index] if area=="town" else "В глубины" if area=="adit_entry" and index==1 else "К входу" if area=="adit_depths" else "В город"
