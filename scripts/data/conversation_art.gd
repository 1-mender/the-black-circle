extends RefCounted
## Existing MZ busts must match the walking character; ambiguous casting gets a silhouette.
## Replace each entry with a transparent portrait/full-body PNG, preferably >=700px tall.
const Definitions=preload("res://scripts/data/resident_definitions.gd")
static func portrait_path(id: String) -> String:
	var definition: Dictionary=Definitions.PEOPLE.get(id,{})
	var replacement: String=str(definition.get("conversation_portrait",""))
	if not replacement.is_empty() and ResourceLoader.exists(replacement):
		return replacement
	var placeholder: String="res://assets/ui/portrait_placeholder.svg"
	if id in ["test_npc","test_rival","test_guard"]:
		return placeholder
	var fallback: String="res://asset/pictures/Actor1_%d.png" % (int(definition.get("sprite",-1))+1)
	return fallback if ResourceLoader.exists(fallback) else placeholder
static func portrait_note(id: String) -> String:
	return "Временный силуэт · портрет ещё не подготовлен" if portrait_path(id).ends_with("portrait_placeholder.svg") else ""
static func public_introduction(id: String) -> String:
	var role: String=str(Definitions.PEOPLE[id].get("profession",id))
	return {"test_npc":"Я живу в этом районе. Обычно меня можно встретить на улице.","smith":"Я работаю в кузнице. Покупаю руду и делаю из неё полезные вещи.","miner":"Работаю в шахте: добываю руду и отношу её на общий склад.","merchant":"Торгую готовыми изделиями. Могу показать, что есть в лавке.","metalworker":"Занимаюсь обработкой металла. Без хорошего материала в нашем деле никуда.","carrier":"Я носильщик. Часто помогаю другим с подготовкой работы.","mason":"Занимаюсь камнем и ремесленной работой.","guard":"Я дозорный. В основном бываю здесь, в районе.","scribe":"Я переписчик. Предпочитаю спокойную работу.","artisan":"Занимаюсь ремеслом. Ценю тех, с кем можно работать вместе."}.get(role,"Живу и работаю в этом районе.")
