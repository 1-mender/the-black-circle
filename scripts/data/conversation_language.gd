extends RefCounted
## Presentation only: supported Russian name forms, never save IDs or biographies.
const Definitions=preload("res://scripts/data/resident_definitions.gd")
static var extra_names: Dictionary = {}
const FORMS={
	"test_npc":["горожанин","горожанину","горожанином","горожанина"],
	"test_smith":["кузнец","кузнецу","кузнецом","кузнеца"],
	"test_miner":["шахтёр","шахтёру","шахтёром","шахтёра"],
	"test_merchant":["торговец","торговцу","торговцем","торговца"],
	"test_apprentice":["Ива","Иве","Ивой","Ивы"],
	"test_rival":["Руд","Руду","Рудом","Руда"],
	"test_carrier":["Тар","Тару","Таром","Тара"],
	"test_mason":["Вел","Велу","Велом","Вела"],
	"test_guard":["Эр","Эру","Эром","Эра"],
	"test_recluse":["Ол","Олу","Олом","Ола"],
	"test_mediator":["Лин","Лин","Лин","Лин"]}
static func name_form(id: String, form: int=0) -> String:
	if id=="player":
		return ["вы","вам","вами","вас"][form]
	var definition: Dictionary=Definitions.PEOPLE.get(id,extra_names.get(id,{}))
	var forms: Array=definition.get("speech_names",FORMS.get(id,[]))
	if forms.size()==4:
		return str(forms[form])
	# Unknown morphology: quoted names are indeclinable, rather than guessed endings.
	return "«"+str(definition.get("name","собеседник")).get_slice(" · ",0).replace(" (тест)","")+"»"
static func display_name(id: String) -> String:
	var value:=name_form(id)
	return value.left(1).to_upper()+value.substr(1)
static func female(id: String) -> bool:
	return bool(Definitions.PEOPLE.get(id,{}).get("speech_female",id in ["test_apprentice","test_mediator"]))
static func past(id: String, male: String, woman: String) -> String:
	return woman if female(id) else male
