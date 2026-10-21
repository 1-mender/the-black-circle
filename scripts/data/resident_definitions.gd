extends RefCounted
## Только тестовые роли и точки на существующей карте, без нового лора.

const PEOPLE: Dictionary = {
	"test_npc": {"name": "Горожанин · тест", "sprite": 5, "spawn": Vector2(1008, 672),
		"work": Vector2(1008, 672), "home": Vector2(408, 576), "rest": Vector2(864, 624),
		"food": Vector2(1104, 624), "errand": Vector2(864, 912)},
	"test_smith": {"name": "Кузнец · тест", "sprite": 2, "spawn": Vector2(1152, 768),
		"work": Vector2(1152, 768), "home": Vector2(1416, 624), "rest": Vector2(1200, 720),
		"food": Vector2(1104, 864), "errand": Vector2(1056, 912)},
	"test_miner": {"name": "Шахтёр · тест", "sprite": 4, "spawn": Vector2(888, 384),
		"work": Vector2(936, 300), "home": Vector2(432, 1104), "rest": Vector2(1008, 480),
		"food": Vector2(816, 864), "errand": Vector2(624, 768)},
	"test_merchant": {"name": "Торговец · тест", "sprite": 6, "spawn": Vector2(816, 720),
		"work": Vector2(816, 720), "home": Vector2(1440, 1104), "rest": Vector2(912, 912),
		"food": Vector2(1008, 864), "errand": Vector2(1200, 624)},
	"test_apprentice": {"name":"Ива · подмастерье (тест)","sprite":1,"spawn":Vector2(768,864),"work":Vector2(768,864),"home":Vector2(600,1104),"rest":Vector2(864,912),"food":Vector2(864,912),"errand":Vector2(864,864),"profession":"metalworker"},
	"test_rival": {"name":"Руд · ремесленник (тест)","sprite":3,"spawn":Vector2(768,912),"work":Vector2(816,864),"home":Vector2(1248,1104),"rest":Vector2(960,864),"food":Vector2(960,864),"errand":Vector2(864,864),"profession":"metalworker"},
	"test_carrier": {"name":"Тар · носильщик (тест)","sprite":4,"spawn":Vector2(768,768),"work":Vector2(768,768),"home":Vector2(600,816),"rest":Vector2(864,912),"food":Vector2(864,912),"errand":Vector2(912,864),"profession":"carrier"},
	"test_mason": {"name":"Вел · каменщик (тест)","sprite":2,"spawn":Vector2(1008,912),"work":Vector2(912,912),"home":Vector2(1248,816),"rest":Vector2(864,912),"food":Vector2(864,912),"errand":Vector2(912,864),"profession":"mason"},
	"test_guard": {"name":"Эр · дозорный (тест)","sprite":7,"spawn":Vector2(1008,816),"work":Vector2(1008,816),"home":Vector2(1200,1104),"rest":Vector2(1008,864),"food":Vector2(1008,864),"errand":Vector2(912,864),"profession":"guard"},
	"test_recluse": {"name":"Ол · переписчик (тест)","sprite":0,"spawn":Vector2(1104,720),"work":Vector2(1104,720),"home":Vector2(1200,624),"rest":Vector2(1104,816),"food":Vector2(1104,816),"errand":Vector2(1008,864),"profession":"scribe"},
	"test_mediator": {"name":"Лин · ремесленница (тест)","sprite":5,"spawn":Vector2(960,912),"work":Vector2(960,912),"home":Vector2(600,1104),"rest":Vector2(912,864),"food":Vector2(912,864),"errand":Vector2(864,864),"profession":"artisan"},
}

## Профили — тестовые определения, не биографии канонических жителей.
const PROFILES := {
	"test_npc":[35,85,25,60,15,"companionship"],
	"test_smith":[45,45,65,80,25,"craft"],
	"test_miner":[55,55,40,70,20,"security"],
	"test_merchant":[40,80,75,35,30,"reputation"],
	"test_apprentice":[55,85,55,85,10,"craft"],
	"test_rival":[15,35,95,25,90,"recognition"],
	"test_carrier":[40,90,20,80,10,"help"],
	"test_mason":[30,40,75,70,60,"recognition"],
	"test_guard":[65,40,45,90,35,"peace"],
	"test_recluse":[95,10,30,85,5,"security"],
	"test_mediator":[45,90,30,95,5,"peace"],
}
const INNER_LIFE := {
	"test_npc":{"beliefs":["не оставлять знакомых в одиночестве"],"wishes":["общение","найти приятную компанию"],"fears":["одиночество"],"biography":"Тестовый горожанин: ищет близкий круг и ценит внимание."},
	"test_smith":{"beliefs":["держать слово","ценить хорошую работу"],"wishes":["закончить заказ","поделиться опытом"],"fears":["подвести партнёра"],"biography":"Тестовый кузнец: хочет делать полезные вещи и отвечать за обещания."},
	"test_miner":{"beliefs":["держать слово"],"wishes":["помощь в тяжёлой работе","спокойный отдых"],"fears":["остаться без поддержки"],"biography":"Тестовый шахтёр: предпочитает надёжное сотрудничество риску."},
	"test_merchant":{"beliefs":["добиваться своего"],"wishes":["хорошая репутация","новые знакомства"],"fears":["потерять доверие"],"biography":"Тестовый торговец: дорожит связями и впечатлением о себе."},
	"test_apprentice":{"beliefs":["держать слово","учиться вместе"],"wishes":["закончить собственную работу","сотрудничество"],"fears":["ссоры"],"biography":"Тестовое подмастерье: стремится учиться, но болезненно воспринимает отказ."},
	"test_rival":{"beliefs":["добиваться своего"],"wishes":["признание","первым получить материал"],"fears":["оказаться ненужным"],"biography":"Тестовый ремесленник: хочет признания и легко видит соперничество в нехватке ресурсов."},
	"test_carrier":{"beliefs":["держать слово","помогать уставшим"],"wishes":["полезный труд","общение"],"fears":["подвести товарища"],"biography":"Тестовый носильщик: охотно тратит силы ради других."},
	"test_mason":{"beliefs":["держать слово"],"wishes":["уважение к труду","надёжный партнёр"],"fears":["несправедливый отказ"],"biography":"Тестовый каменщик: ценит уважение и может вспылить из-за отказа."},
	"test_guard":{"beliefs":["держать слово","сдерживать ссоры"],"wishes":["мирный район","взаимовыручка"],"fears":["потерять самообладание"],"biography":"Тестовый дозорный: старается поддерживать порядок без эскалации."},
	"test_recluse":{"beliefs":["держать слово","избегать ссор"],"wishes":["покой","осторожное общение"],"fears":["ссоры"],"biography":"Тестовый переписчик: осторожен и уходит от конфликтных встреч."},
	"test_mediator":{"beliefs":["держать слово","восстанавливать доверие"],"wishes":["примирение","взаимопомощь"],"fears":["затяжная вражда"],"biography":"Тестовая ремесленница: предпочитает примирение борьбе за первое место."},
}
static func profile(id: String) -> Dictionary:
	var values: Array = PROFILES.get(id,[50,50,50,50,25,"companionship"])
	var result := {"caution":values[0],"sociability":values[1],"ambition":values[2],"principle":values[3],"aggression":values[4],"goal":values[5]}
	result.merge(INNER_LIFE.get(id,{}).duplicate(true))
	return result
const TASK_POINT: Dictionary = {"work": "work", "sleep": "home", "rest": "rest", "eat": "food", "errand": "errand"}
const TASK_NAMES: Dictionary = {"work": "Работает", "sleep": "Спит", "rest": "Отдыхает", "eat": "Ест", "errand": "Бытовые дела", "walk": "В пути", "wait": "Ждёт прохода"}
const REASONS: Dictionary = {
	"schedule": "Дневное рабочее время", "night": "Ночь: пора спать",
	"hunger": "Голод важнее расписания", "fatigue": "Нужен сон или отдых",
	"break": "Накопилась потребность в перерыве", "meal": "Обеденный перерыв",
	"evening": "Свободное время: бытовые дела", "rest": "Свободное время: отдых",
	"blocked": "Путь закрыт; повторная попытка через 5 минут",
	"player": "Уступает дорогу игроку", "conversation": "Общается с игроком",
}
