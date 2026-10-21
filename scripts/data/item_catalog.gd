extends RefCounted
## Определения предметов и ассортимент магазинов отделены от состояния игры.

var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
var shops: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shops.json"))
var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))

func item_name(item_id: String) -> String:
	return str(items.get(item_id, {}).get("name", item_id))

func buy_price(shop_id: String, item_id: String) -> int:
	return int(shops.get(shop_id, {}).get("buy_prices", {}).get(item_id, 0))

func sell_price(shop_id: String, item_id: String) -> int:
	return int(shops.get(shop_id, {}).get("sell_prices", {}).get(item_id, 0))
