extends RefCounted
## Read-only realisation: remembered claim -> speaker's role -> intention -> speech.
## Never reads objective history, private reasons or another character's memories.
const Language=preload("res://scripts/data/conversation_language.gd")

static func person(world: RefCounted, id: String, speaker: String, form: int=0) -> String:
	if id==speaker:
		return ["я","мне","мной","меня"][form]
	return Language.name_form(id,form,world)

static func verb(world: RefCounted, id: String, speaker: String, male: String, female: String, plural: String) -> String:
	return plural if id=="player" else Language.past(speaker if id==speaker else id,male,female,world)

static func role(event: Dictionary, speaker: String) -> String:
	# Participation belongs to this remembered claim, not to an omniscient event lookup.
	if not event.get("witnessed",false):
		return "rumour"
	if speaker==event.actor:
		return "actor"
	if speaker==event.target:
		return "target"
	return "witness"

static func account(world: RefCounted, speaker: String, event: Dictionary, intent: String="account") -> String:
	var npc: Dictionary=world.social.characters[speaker]
	var stance:=role(event,speaker)
	var cause: Dictionary={}
	for memory in npc.memory+npc.summaries:
		if int(memory.id)==int(event.get("topic",0)):
			cause=memory
			break
	if intent=="source":
		if stance in ["actor","target"]:
			return "Это было со мной. О том, что было дальше без меня, не скажу."
		if stance=="witness":
			return "Я %s это своими глазами. За то, чего не было при мне, не ручаюсь."%Language.past(speaker,"видел","видела",world)
		var origin:=str(event.get("source",""))
		return "Мне об этом %s %s. Не знаю, всё ли так и было."%[Language.past(origin,"рассказал","рассказала",world),Language.name_form(origin,0,world)] if origin!=speaker and world.social.characters.has(origin) else "До меня дошёл такой рассказ. Само событие я не наблюдаю — ручаться не стану."
	if intent=="participant":
		var other: String=event.target if event.actor==speaker else event.actor
		if other==speaker:
			return "В этой истории речь обо мне. Что именно вас интересует?"
		# Only public acquaintance and a directed attitude, never private motives.
		if not npc.contacts.has(other) and speaker not in [event.actor,event.target]:
			return "Лично мы почти не общались. Судить по одному рассказу не хочу."
		var attitude: Dictionary=world.social.relation_view(speaker,other)
		if attitude.dislike>30:
			return "С %s мне сейчас нелегко ладить. Но за чужие намерения я говорить не буду."%Language.name_form(other,2,world)
		if attitude.trust>=30:
			return "Обычно я могу положиться на %s. Это моё впечатление, а не обещание за другого человека."%Language.name_form(other,3,world)
		if event.kind in ["argue","discontent"] and speaker in [event.actor,event.target]:
			return "После такого разговора мне непросто с %s. Давайте вернёмся к этому позже."%Language.name_form(other,2,world)
		return "Мы знакомы, но я не стану говорить за другого человека. Лучше спросите лично."
	if intent=="detail":
		if not cause.is_empty():
			return "Началось вот с чего: "+_fact(world,cause,speaker)+" "+_boundary(npc,stance)
		return "Больше подробностей у меня нет. "+_boundary(npc,stance)
	var text:=_fact(world,event,speaker)
	if stance=="rumour":
		text="Говорят, "+_continued(world,text,event)+" "+Language.past(speaker,"Сам я этого не видел.","Сама я этого не видела.",world)
	elif stance=="witness":
		text="Я %s, как %s"%[Language.past(speaker,"видел","видела",world),_continued(world,text,event)]
	if npc.emotion.anger>45 and stance in ["actor","target"]:
		text+=" Не хочется снова к этому возвращаться."
	elif npc.traits.sociability>=65 and world.life.people[speaker].fatigue<70:
		if event.kind in ["argue","discontent"]:
			text+=" Мне бы хотелось обойтись без ссоры." if "ссоры" in npc.fears else " Непростой вышел разговор."
		elif event.kind in ["help","accept"]:
			text+=" Такую помощь я ценю." if stance=="target" else " Хорошо, когда есть кому помочь."
	if npc.traits.caution>70 and stance=="rumour":
		text+=" Не принимайте это за доказательство."
	return text

static func _continued(world: RefCounted, text: String, event: Dictionary) -> String:
	var actor_name:=Language.name_form(str(event.actor),0,world)
	if actor_name.left(1)==actor_name.left(1).to_upper() and text.begins_with(actor_name):
		return text
	return text.left(1).to_lower()+text.substr(1)

static func _boundary(npc: Dictionary, stance: String) -> String:
	if stance=="rumour":
		return "Это всё пересказ; лучше спросить самих участников."
	return "За других говорить не буду." if "держать слово" in npc.beliefs else "Я могу говорить только за себя."

static func _fact(world: RefCounted, event: Dictionary, speaker: String) -> String:
	var actor: String=event.actor
	var target: String=event.target
	var a:=person(world,actor,speaker)
	var t:=person(world,target,speaker,1)
	var other: String=target if actor==speaker else actor
	match str(event.kind):
		"argue","discontent":
			if speaker==actor:
				return "Я %s с %s. Не %s промолчать."%[Language.past(speaker,"поспорил","поспорила",world),Language.name_form(other,2,world),Language.past(speaker,"смог","смогла",world)]
			if speaker==target:
				return "%s %s мне претензии. Мы поспорили — мне было неприятно."%[a.capitalize(),verb(world,actor,speaker,"высказал","высказала","высказали")]
			return "%s и %s поспорили."%[a.capitalize(),Language.name_form(target,0,world)]
		"help","accept":
			return "%s %s %s с работой."%[a.left(1).to_upper()+a.substr(1),verb(world,actor,speaker,"помог","помогла","помогли"),t]
		"refuse":
			return "%s %s %s в помощи."%[a.left(1).to_upper()+a.substr(1),verb(world,actor,speaker,"отказал","отказала","отказали"),t]
		"request_help","offer_cooperation":
			return "%s %s %s помочь с работой."%[a.left(1).to_upper()+a.substr(1),verb(world,actor,speaker,"предложил","предложила","предложили") if event.kind=="offer_cooperation" else verb(world,actor,speaker,"попросил","попросила","попросили"),(Language.name_form(target,1,world) if event.kind=="offer_cooperation" else Language.name_form(target,3,world)) if target!=speaker else ("мне" if event.kind=="offer_cooperation" else "меня")]
		"shortage":
			return "У %s не хватило материалов для работы."%("меня" if actor==speaker else Language.name_form(actor,3,world))
		"completed":
			return "%s %s свою работу."%[a.left(1).to_upper()+a.substr(1),verb(world,actor,speaker,"закончил","закончила","закончили")]
		"project":
			return "%s %s за работу."%[a.left(1).to_upper()+a.substr(1),verb(world,actor,speaker,"взялся","взялась","взялись")]
		"reconcile":
			return "Мы с %s помирились."%Language.name_form(other,2,world) if speaker in [actor,target] else "%s и %s помирились."%[a.capitalize(),Language.name_form(target,0,world)]
	return "Об этом у меня нет достаточно ясного рассказа."
