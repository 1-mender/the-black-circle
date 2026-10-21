extends Node2D
## Отладочный путь выбранного жителя поверх земли, под персонажами.

var life: RefCounted
var selected_id := "test_npc"

func _draw() -> void:
	if life == null or not life.people.has(selected_id):
		return
	var record: Dictionary = life.people[selected_id]
	var point: Vector2 = record["position"]
	for next: Vector2 in record["path"]:
		draw_line(point, next, Color("eed58c"), 2, true)
		point = next
	draw_arc(record["goal"], 22, 0, TAU, 24, Color("eed58c"), 3, true)
