extends RefCounted
## Иконки из уже включённого в проект RPG-атласа, ячейка 32×32.
const ATLAS = preload("res://asset/system/IconSet.png")
const ACTOR = preload("res://asset/characters/Actor1.png")
const QUICK_ACTIONS := {
	"attack": preload("res://asset/ui/abilities/attack.svg"),
	"block": preload("res://asset/ui/abilities/block.svg"),
	"dodge": preload("res://asset/ui/abilities/dodge.svg"),
	"test_heal": preload("res://asset/ui/vitals/healing.svg"),
}
const INDEX := {"test_adit_ring": 145, "test_adit_key": 194, "test_sword": 97, "test_shield": 128, "test_armor": 131, "test_heal": 176, "test_iron_ore": 168, "test_copper_ore": 169, "test_iron_ingot": 170, "test_copper_ingot": 171, "test_iron_tool": 242, "test_copper_trinket": 145, "attack": 97, "block": 128, "dodge": 82}
const EMPTY := {"head": 132, "body": 131, "main_hand": 97, "off_hand": 128, "feet": 140, "accessory_1": 145, "accessory_2": 145}
static func texture(id: String, fallback: int = 208) -> Texture2D:
	if id == "test_heal":
		return QUICK_ACTIONS[id]
	var result := AtlasTexture.new()
	result.atlas = ATLAS
	var index: int = INDEX.get(id, fallback)
	result.region = Rect2((index % 16) * 32, floori(float(index) / 16.0) * 32, 32, 32)
	return result
static func quick_texture(id: String) -> Texture2D:
	if QUICK_ACTIONS.has(id):
		return QUICK_ACTIONS[id]
	return texture(id)
static func portrait(index: int) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = ACTOR
	result.region = Rect2((index % 4) * 144 + 48, floori(float(index) / 4.0) * 192, 48, 48)
	return result
static func category(item: Dictionary) -> String:
	if item.get("slot") == "main_hand":
		return "weapon"
	if item.get("slot", "") in ["off_hand", "head", "body", "feet"]:
		return "armor"
	if item.has("heal") or item.get("category") == "consumable":
		return "consumable"
	if item.get("category") in ["ore", "material"]:
		return "material"
	return "other"
static func category_name(item: Dictionary) -> String:
	return {"weapon": "Оружие", "armor": "Броня", "consumable": "Расходники", "material": "Материалы", "other": "Прочее"}[category(item)]

