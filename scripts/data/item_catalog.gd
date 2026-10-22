extends RefCounted
## Определения предметов и ассортимент магазинов отделены от состояния игры.
const Occupations = preload("res://scripts/data/occupation_definitions.gd")

var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
var shops: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shops.json"))
var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))

func add_resident_shop(id: String, profession: String, display_name: String) -> void:
	if profession not in ["smith", "merchant"] or shops.has(id):
		return
	var template: String = Occupations.ROLES[profession].shop_template
	shops[id] = shops[template].duplicate(true)
	shops[id]["name"] = display_name

func item_name(item_id: String) -> String:
	return str(items.get(item_id, {}).get("name", item_id))

func buy_price(shop_id: String, item_id: String) -> int:
	return int(shops.get(shop_id, {}).get("buy_prices", {}).get(item_id, 0))

func sell_price(shop_id: String, item_id: String) -> int:
	return int(shops.get(shop_id, {}).get("sell_prices", {}).get(item_id, 0))
