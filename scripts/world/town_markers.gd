extends Node2D

const Data = preload("res://scripts/data/mine_location.gd")
const Production = preload("res://scripts/data/production_definitions.gd")
const Arena = preload("res://scripts/data/arena_location.gd")
const Adit = preload("res://scripts/data/adit_location.gd")

func _ready() -> void:
	for entry in [
		[Data.TOWN_ENTRANCE + Vector2(-84, 28), "Тестовая шахта"],
		[Production.WORKBENCH + Vector2(-72, 24), "Склад и верстак · E"],
		[Arena.TOWN_ENTRANCE + Vector2(-110, 30), "Боевой полигон · E (тест)"],
		[Adit.TOWN_ENTRANCE + Vector2(-105, 28), "Заброшенная штольня · E"],
	]:
		var label := Label.new()
		label.hide()
		label.position = entry[0]
		label.text = entry[1]
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_shadow_color", Color("182b2a"))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(label)

func _draw() -> void:
	draw_circle(Adit.TOWN_ENTRANCE,26,Color("405a52"))
	draw_arc(Adit.TOWN_ENTRANCE,26,0,TAU,24,Color("e4cb98"),3)
	draw_circle(Arena.TOWN_ENTRANCE, 28, Color("7c5547"))
	draw_arc(Arena.TOWN_ENTRANCE, 28, 0, TAU, 32, Color("e5c58a"), 3)
	draw_rect(Rect2(Production.WORKBENCH - Vector2(26, 18), Vector2(52, 28)), Color("846c49"))
	draw_rect(Rect2(Production.WORKBENCH - Vector2(26, 18), Vector2(52, 28)), Color("d8b772"), false, 2)
	draw_circle(Data.TOWN_ENTRANCE, 28, Color("344c56"))
	draw_arc(Data.TOWN_ENTRANCE, 28, 0, TAU, 32, Color("e5c58a"), 3, true)
	draw_line(Data.TOWN_ENTRANCE + Vector2(-14, -14), Data.TOWN_ENTRANCE + Vector2(14, 14), Color("e5c58a"), 4)
	draw_line(Data.TOWN_ENTRANCE + Vector2(-14, 14), Data.TOWN_ENTRANCE + Vector2(14, -14), Color("e5c58a"), 4)
