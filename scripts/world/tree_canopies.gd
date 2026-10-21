extends Node2D
## Кроны находятся над персонажами; тени и основания остаются на карте.

const Data = preload("res://scripts/data/test_location.gd")

func _draw() -> void:
	for tree in Data.TREES:
		draw_circle(tree + Vector2(0, -37), 35, Color("29483f"))
		draw_circle(tree + Vector2(-12, -48), 25, Color("36594a"))
		draw_circle(tree + Vector2(8, -55), 20, Color("466953"))
