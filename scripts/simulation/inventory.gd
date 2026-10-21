extends RefCounted
## Стеки по постоянному ID предмета. Лимит защищает от переполнения чисел.

const MAX_COUNT := 1000000
var items: Dictionary = {}

func count(item_id: String) -> int:
	return int(items.get(item_id, 0))

func add(item_id: String, amount: int) -> bool:
	if amount <= 0 or amount > MAX_COUNT - count(item_id):
		return false
	items[item_id] = count(item_id) + amount
	return true

func remove(item_id: String, amount: int) -> bool:
	if amount <= 0 or amount > count(item_id):
		return false
	var remaining := count(item_id) - amount
	if remaining == 0:
		items.erase(item_id)
	else:
		items[item_id] = remaining
	return true
