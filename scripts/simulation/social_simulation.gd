extends RefCounted
## Objective events, subjective bounded memories, and validated local commands.
## State is independent of nodes. No event replay during loading.
const Definitions = preload("res://scripts/data/resident_definitions.gd")
const MAX_HISTORY := 128
const MAX_MEMORY := 24
const MAX_SUMMARIES := 8
const MAX_ACCOUNTS := 3
const ACTIONS := ["talk","ask_news","request_help","offer_cooperation","accept","refuse","help","discontent","argue","reconcile","inform","support","oppose"]
const LABELS := {"talk":"Разговор","ask_news":"Вопрос о происходящем","request_help":"Просьба о помощи","offer_cooperation":"Предложение сотрудничества","accept":"Согласие","refuse":"Отказ","help":"Помощь трудом","discontent":"Недовольство","argue":"Спор","reconcile":"Примирение","inform":"Передача сведений","support":"Поддержка","oppose":"Осуждение","deception":"Обнаруженный обман","misinformation":"Опровергнутый слух","shortage":"Не хватает материалов","project":"Начало ремесленной работы","completed":"Работа завершена"}
var characters: Dictionary = {}
var relations: Dictionary = {}
var history: Array = []
var projects: Dictionary = {}
var next_event := 1
var last_minute := -1
## Stable public seed is used by deterministic simulations and older tests.
@warning_ignore("shadowed_global_identifier")
var seed := 7307
var receipts: Array = []
var revision := 0

func _init() -> void:
	for id in ["player"] + Definitions.PEOPLE.keys():
		add_character(id, Definitions.profile(id))
	# Unequal initial perceptions, not an inevitable future conflict.
	relationship("test_rival","test_apprentice").dislike = 28.0
	relationship("test_apprentice","test_rival").respect = 35.0
	relationship("test_mediator","test_rival").attachment = 20.0

func add_character(id: String, profile: Dictionary) -> bool:
	if id.is_empty() or characters.has(id):
		return false
	var traits: Dictionary={}
	for key in ["caution","sociability","ambition","principle","aggression"]:
		traits[key]=float(profile[key])
	characters[id] = {"id":id,"traits":traits,"beliefs":profile.get("beliefs",["держать слово"]).duplicate(),
		"wishes":profile.get("wishes",["общение","полезный труд"]).duplicate(),"long_goal":profile.goal,"biography":str(profile.get("biography","Тестовый житель района.")),
		"emotion":{"anger":0.0,"fear":0.0,"joy":0.0},"fears":profile.get("fears",["неудача"]).duplicate(),
		"memory":[],"summaries":[],"knowledge":{},"pending":{},"cooldown":0,"plan":"Привычный распорядок","reason":"Нет незавершённой просьбы",
		"blocked_until":0,"completed":0,"last_partner":"","last_action":"","last_topic":0,"grievances":{},"contacts":{},"requested_until":0,"work_available":false}
	characters[id]["shared"]={}
	relations[id] = {}
	return true

func relationship(actor: String, target: String) -> Dictionary:
	if not relations[actor].has(target):
		relations[actor][target] = {"attachment":0.0,"trust":10.0,"respect":10.0,"dislike":0.0,"history":[],"last_summary":""}
	return relations[actor][target]

func relation_view(actor: String, target: String) -> Dictionary:
	# Inspecting a card must not create simulation state, especially while paused.
	return relations.get(actor,{}).get(target,{"attachment":0.0,"trust":10.0,"respect":10.0,"dislike":0.0,"history":[],"last_summary":""})

func name_of(id: String) -> String:
	return "Авантюрист" if id == "player" else str(Definitions.PEOPLE.get(id,{}).get("name",id))

func spatial(state: RefCounted, id: String) -> Dictionary:
	if id == "player":
		return {"location":state.location_id,"position":state.player_position,"awake":state.rpg.fighter.hp>0}
	if not state.life.people.has(id):
		return {}
	var person: Dictionary = state.life.people[id]
	return {"location":person.location,"position":person.position,"awake":person.activity!="sleep" and person.fatigue<95}

func check_action(state: RefCounted, actor: String, target: String, action: String, payload: Dictionary = {}) -> String:
	if not payload.get("command","") is String or str(payload.get("command","")).length()>80:
		return "Некорректный идентификатор команды"
	if not payload.get("distort",false) is bool:
		return "Некорректное содержание рассказа"
	if action not in ACTIONS or not characters.has(actor) or not characters.has(target) or actor==target:
		return "Нет такого действия или участника"
	if state.life.clock.paused:
		return "Мир на паузе"
	var a := spatial(state,actor)
	var b := spatial(state,target)
	if a.is_empty() or b.is_empty() or not a.awake or not b.awake:
		return "Собеседник сейчас недоступен"
	if a.location!=b.location or a.position.distance_to(b.position)>140 or not state.adventure.clear_line(a.location,a.position,b.position):
		return "Нужно подойти к собеседнику без преграды"
	if int(characters[actor].cooldown)>state.life.clock.minute:
		return "Дайте собеседнику немного времени"
	if not str(payload.get("command","")).is_empty() and payload.command in receipts:
		return "Эта команда уже выполнена"
	if action in ["request_help","offer_cooperation"] and not characters[target].pending.is_empty():
		return "Собеседник ещё обдумывает другую просьбу"
	if action in ["argue","discontent"] and not characters[actor].grievances.has(target):
		return "Нет известной личной причины для спора"
	if actor=="player" and action in ["help","accept"] and state.rpg.fighter.stamina<6:
		return "Недостаточно выносливости для помощи"
	if action in ["accept","refuse"] and (characters[actor].pending.is_empty() or characters[actor].pending.from!=target):
		return "Нет просьбы от этого персонажа"
	if action=="help" and target!="player" and state.life.people[target].fatigue<8 and state.economy.jobs.smith.is_empty() and not projects.has(target):
		return "Сейчас помощь трудом не требуется"
	if action in ["support","oppose"] and _conflict_known(actor,target,payload).is_empty():
		return "Вам неизвестен конфликт с этим участником"
	if not payload.get("subject","") is String or str(payload.get("subject","")).length()>40 or not payload.get("statement","") is String or str(payload.get("statement","")).length()>512:
		return "Некорректная тема разговора"
	if action=="ask_news" and payload.has("event") and _source_topic(target,actor,payload).is_empty():
		return "Собеседник не знает этого события"
	if action=="inform" and _source_topic(actor,target,payload).is_empty():
		return "Нет новых сведений для передачи"
	if action=="inform" and payload.get("distort",false):
		var fact := _source_topic(actor,target,payload)
		if fact.actor==fact.target or fact.kind not in ["help","accept","refuse"]:
			return "Этот факт не является рассказом о помощи или отказе"
	if action=="inform" and payload.get("distort",false) and float(characters[actor].traits.principle)>=70 and float(characters[actor].emotion.anger)<60:
		return "Принципы не позволяют сознательно искажать рассказ"
	return ""

func execute(state: RefCounted, actor: String, target: String, action: String, payload: Dictionary = {}) -> Dictionary:
	var refusal := check_action(state,actor,target,action,payload)
	if not refusal.is_empty():
		return {"ok":false,"reason":refusal}
	var minute: int = state.life.clock.minute
	if actor=="player":
		characters[actor].reason="Личный выбор героя: "+str(LABELS[action])
	var topic: Dictionary = {}
	if action in ["accept","refuse"]:
		topic={"id":characters[actor].pending.event}
	elif action in ["argue","discontent"]:
		topic={"id":characters[actor].grievances[target].event}
	if action in ["inform","ask_news"]:
		topic = _source_topic(actor,target,payload) if action=="inform" else (_source_topic(target,actor,payload) if payload.has("event") else _shareable(target,actor))
	if action in ["support","oppose"]:
		topic = _conflict_known(actor,target,payload)
	var outcome := ""
	match action:
		"request_help", "offer_cooperation":
			characters[target].pending = {"from":actor,"kind":action,"minute":minute,"event":next_event}
			characters[actor].requested_until=minute+180
			outcome = "Просит помочь трудом с подготовкой работы; ждёт ответа" if action=="request_help" else "Предлагает совместную подготовку работы; ждёт ответа"
		"accept":
			var kind: String = characters[actor].pending.kind
			characters[actor].pending = {}
			_help(state,actor,target)
			if kind=="offer_cooperation":
				characters[actor].plan="Сотрудничать с "+name_of(target)
				characters[target].plan="Работать с "+name_of(actor)
			outcome = "Выделено время помощи; партнёр меньше устаёт"
		"refuse":
			characters[actor].pending = {}
			characters[target].emotion.anger = minf(100,characters[target].emotion.anger+12)
			outcome = "Просьба отклонена; проситель будет выбирать другого помощника"
		"help":
			_help(state,actor,target)
			outcome = "Помощник потратил силы и время, получатель получил поддержку"
		"argue", "discontent":
			characters[target].emotion.anger = minf(100,characters[target].emotion.anger+18)
			characters[actor].emotion.anger = maxf(0,characters[actor].emotion.anger-6)
			outcome = "Работа прервана; участники запомнили спор"
		"reconcile":
			characters[actor].emotion.anger *= 0.5
			characters[target].emotion.anger *= 0.5
			outcome = "Напряжение снижено; можно снова просить о сотрудничестве"
		"support":
			characters[target].emotion.joy = minf(100,characters[target].emotion.joy+15)
			characters[target].emotion.anger *= 0.6
			var other: String=str(topic.target) if str(topic.actor)==target else str(topic.actor)
			if characters.has(other) and other!=target:
				relationship(target,other).dislike=maxf(0,float(relationship(target,other).dislike)-12)
			outcome = "Участник почувствовал поддержку; спор стал менее вероятен"
		"oppose":
			characters[target].emotion.anger = minf(100,characters[target].emotion.anger+15)
			outcome = "Участник запомнил осуждение"
		"talk":
			characters[actor].emotion.joy = minf(100,characters[actor].emotion.joy+4)
			characters[target].emotion.joy = minf(100,characters[target].emotion.joy+4)
			outcome = "Знакомство укрепилось"
		_:
			outcome = "Нет новых известий" if topic.is_empty() else "Обсуждают событие: "+str(LABELS[topic.kind])+" · "+name_of(topic.actor)+" → "+name_of(topic.target)
	var reported: Dictionary=topic.duplicate(true)
	var distorted: bool=action=="inform" and bool(payload.get("distort",false)) and not topic.is_empty()
	if distorted:
		reported.kind="refuse" if str(topic.kind) in ["help","accept","completed"] else "help"
		reported.consequence="Непроверенный рассказ: "+str(LABELS[reported.kind])+" · "+name_of(reported.actor)+" → "+name_of(reported.target)
	if action in ["inform","ask_news"] and not reported.is_empty():
		outcome="Со слов собеседника: "+str(LABELS[reported.kind])+" · "+name_of(reported.actor)+" → "+name_of(reported.target)
	# Follow-ups enrich the same attributed evidence. No replay of social consequences.
	if action=="ask_news" and not reported.is_empty():
		for known in characters[actor].memory+characters[actor].summaries:
			if int(known.id)!=int(reported.id):
				continue
			var prior: Dictionary=known.get("accounts",{}).get(target,{})
			if not prior.is_empty() and prior.kind==reported.kind and prior.get("actor",reported.actor)==reported.actor and prior.get("target",reported.target)==reported.target:
				var before:=JSON.stringify(known)
				_record_account(actor,target,reported,minute,str(payload.get("statement","")))
				if before!=JSON.stringify(known):
					revision+=1
				characters[actor].cooldown=minute+1
				if not str(payload.get("command","")).is_empty():
					receipts.append(str(payload.command))
					if receipts.size()>64:
						receipts.pop_front()
				return {"ok":true,"reason":"Уточнение известного рассказа","event":int(reported.id),"repeated":true}
	var event := _event(state,action,actor,target,outcome,topic,str(payload.get("subject","")),str(payload.get("statement","")))
	if distorted:
		# Objective intent is retained only in the developer history, never leaked to memories.
		event["misleading"]=true
		event["original_kind"]=topic.kind
		history.append(event)
		if history.size()>MAX_HISTORY:
			history.pop_front()
	if action in ["argue","discontent","reconcile"]:
		characters[actor].grievances.erase(target)
	if action=="reconcile":
		characters[target].grievances.erase(actor)
	if not topic.is_empty() and action in ["inform","ask_news"]:
		var speaker := actor if action=="inform" else target
		var listener := target if action=="inform" else actor
		var claim: Dictionary=reported
		var exposed:=false
		for known in characters[listener].memory+characters[listener].summaries:
			if int(known.id)==int(claim.id) and known.witnessed and known.kind!=claim.kind:
				_event(state,"deception" if distorted else "misinformation",speaker,listener,"Рассказ противоречит лично увиденному событию; доверие к источнику снизилось",topic)
				exposed=true
				break
		if not exposed:
			_remember(listener,claim,speaker,false,{})
		_record_account(listener,speaker,claim,minute,str(payload.get("statement","")))
		if not characters[speaker].shared.has(listener):
			characters[speaker].shared[listener]=[]
		var told: Array=characters[speaker].shared[listener]
		if int(topic.id) not in told:
			told.append(int(topic.id))
		if told.size()>8:
			told.pop_front()
	for id in [actor,target]:
		characters[id].last_partner = target if id==actor else actor
		characters[id].last_action = action
		characters[id].contacts[target if id==actor else actor]=minute
		characters[id].cooldown = minute+(1 if id=="player" else 8)
		characters[id].reason = str(LABELS[action])+": "+outcome
		if id!="player":
			state.life.people[id].social_hold_until=maxi(minute+2,int(state.life.people[id].get("social_hold_until",0)))
	if not str(payload.get("command","")).is_empty():
		receipts.append(str(payload.command))
		if receipts.size()>64:
			receipts.pop_front()
	return {"ok":true,"reason":outcome,"event":event.id}

func _help(state: RefCounted, actor: String, target: String) -> void:
	var minute: int = state.life.clock.minute
	if actor!="player":
		state.life.people[actor].fatigue = minf(100,state.life.people[actor].fatigue+6)
		state.life.people[actor].social_hold_until=minute+4
	else:
		state.rpg.fighter.stamina=maxf(0,state.rpg.fighter.stamina-6)
	if target!="player":
		state.life.people[target].fatigue=maxf(0,state.life.people[target].fatigue-12)
		state.life.people[target].support_until=minute+60
		# Real labour credit, consumed once by a job with already reserved inputs.
		state.life.people[target].assist_credit=mini(8,int(state.life.people[target].get("assist_credit",0))+2)
	else:
		state.rpg.fighter.stamina=minf(state.rpg.stats(state.catalog).max_stamina,state.rpg.fighter.stamina+12)
	characters[target].emotion.joy=minf(100,characters[target].emotion.joy+10)

func _event(state: RefCounted, kind: String, actor: String, target: String, consequence: String, topic: Dictionary = {}, subject: String = "", statement: String = "") -> Dictionary:
	var event := {"id":next_event,"minute":state.life.clock.minute,"kind":kind,"actor":actor,"target":target,"consequence":consequence,"reason":str(characters[actor].reason),"topic":int(topic.get("id",0)),"witnesses":[],"effects":{}}
	if not subject.is_empty():
		event["subject"]=subject
		event["statement"]=statement
		event["statement_source"]=target if actor=="player" else actor
	next_event += 1
	var origin := spatial(state,actor)
	var observers: Array=characters.keys()
	observers.sort()
	for id in observers:
		var observer := spatial(state,id)
		if id in [actor,target] or (not observer.is_empty() and observer.awake and not origin.is_empty() and observer.location==origin.location and observer.position.distance_to(origin.position)<=180 and state.adventure.clear_line(observer.location,observer.position,origin.position)):
			event.witnesses.append(id)
			var effects := _interpret(id,event)
			event.effects[id]=effects
			_remember(id,event,id,true,effects)
	if kind not in ["talk","inform"]:
		history.append(event)
		if history.size()>MAX_HISTORY:
			history.pop_front()
	revision += 1
	return event

func _interpret(observer: String, event: Dictionary) -> Dictionary:
	var other: String = event.actor if observer!=event.actor else event.target
	if not characters.has(other) or observer==other:
		return {}
	var delta := {"attachment":0.0,"trust":0.0,"respect":0.0,"dislike":0.0}
	var personal: bool = observer in [event.actor,event.target]
	match event.kind:
		"help", "accept", "support":
			delta.attachment=6.0 if personal else 1.0
			delta.trust=8.0 if observer==event.target else 2.0
			delta.respect=3.0
			delta.dislike=-4.0
		"refuse":
			if observer==event.target:
				delta.trust=-7.0
				delta.dislike=8.0
		"deception", "misinformation":
			delta.trust=-18.0 if observer==event.target else -4.0
			delta.dislike=10.0 if observer==event.target else 2.0
			delta.respect=-5.0
		"argue", "discontent", "oppose":
			delta.dislike=12.0 if personal else 2.0
			delta.trust=-6.0 if personal else -1.0
			delta.respect=-4.0 if float(characters[observer].traits.principle)>60 else 1.0
			characters[observer].emotion.fear=minf(100,characters[observer].emotion.fear+float(characters[observer].traits.caution)*0.08)
		"reconcile":
			delta.dislike=-15.0
			delta.trust=5.0
		"talk", "offer_cooperation":
			delta.attachment=2.0 if personal else 0.0
		_:
			pass
	var relation := relationship(observer,other)
	if personal and (event.kind in ["argue","discontent"] or event.kind in ["refuse","deception","misinformation"] and observer==event.target):
		characters[observer].grievances[other]={"event":event.id,"until":int(event.minute)+180}
	for key in delta:
		relation[key]=clampf(float(relation[key])+float(delta[key]),-100,100) if key!="dislike" else clampf(float(relation[key])+float(delta[key]),0,100)
	relation.history.append(event.id)
	relation.last_summary="%s · день %d: %s" % [LABELS[event.kind],floori(float(event.minute)/1440)+1,str(event.consequence)]
	if relation.history.size()>8:
		relation.history.pop_front()
	return {"toward":other,"delta":delta}

func _remember(observer: String, event: Dictionary, source: String, witnessed: bool, effects: Dictionary) -> void:
	var person: Dictionary = characters[observer]
	for memory in person.memory:
		if int(memory.id)==int(event.id):
			return
	for memory in person.summaries:
		if int(memory.id)==int(event.id):
			return
	var interpretation := "наблюдал лично" if witnessed else "со слов "+name_of(source)+"; не проверено"
	if event.kind in ["argue","discontent"]:
		interpretation += "; лучше избегать ссор" if float(person.traits.caution)>60 else "; соперник перешёл границу"
	var known_reason: String=str(event.get("reason","")) if witnessed and observer==event.actor else ("Мотивы собеседника оценивает по поступку; чужие мысли неизвестны" if witnessed else "Объяснение со слов источника, а не достоверное знание мотивов")
	var memory := {"id":event.id,"minute":event.minute,"kind":event.kind,"actor":event.actor,"target":event.target,"consequence":event.consequence,"reason":known_reason,"topic":int(event.get("topic",0)),"source":source,"witnessed":witnessed,"interpretation":interpretation,"effects":effects.duplicate(true)}
	if event.has("subject"):
		memory["subject"]=event.subject
		memory["statement"]=event.get("statement","")
		memory["statement_source"]=event.get("statement_source",event.target)
	person.memory.append(memory)
	if not witnessed and event.kind in ["argue","discontent"] and event.actor!=observer:
		# A rumour may be misread; it remains a claim, never objective knowledge.
		var opinion:=relationship(observer,event.actor)
		opinion.trust=maxf(-100,float(opinion.trust)-2)
		memory.effects={"toward":event.actor,"delta":{"trust":-2.0},"basis":"непроверенный рассказ"}
	if person.memory.size()>MAX_MEMORY:
		var old: Dictionary = person.memory.pop_front()
		if old.kind in ["help","refuse","argue","accept","reconcile","completed","deception","misinformation"]:
			var summary: Dictionary=old.duplicate(true)
			summary.effects={}
			person.summaries.append(summary)
			if person.summaries.size()>MAX_SUMMARIES:
				person.summaries.pop_front()
	var topic := str(event.actor)+":"+str(event.kind)
	person.knowledge[topic]={"event":event.id,"source":source,"confidence":1.0 if witnessed else clampf((float(relationship(observer,source).trust)+100)/200,0.1,0.9)}
	if person.knowledge.size()>12:
		var oldest := ""
		var oldest_event := 2147483647
		var topics: Array=person.knowledge.keys()
		topics.sort()
		for key in topics:
			if int(person.knowledge[key].event)<oldest_event:
				oldest=str(key)
				oldest_event=int(person.knowledge[key].event)
		person.knowledge.erase(oldest)

func _shareable(actor: String, target: String) -> Dictionary:
	# The speaker knows what they told, not the recipient's private memory.
	var ids: Array = characters[actor].shared.get(target,[])
	var memories: Array = characters[actor].summaries+characters[actor].memory
	for i in range(memories.size()-1,-1,-1):
		if memories[i].kind not in ["inform","ask_news","talk"] and int(memories[i].id) not in ids:
			return memories[i]
	return {}

func _source_topic(actor: String, target: String, payload: Dictionary) -> Dictionary:
	if not payload.has("event"):
		if payload.get("distort",false):
			var memories: Array=characters[actor].summaries+characters[actor].memory
			var told: Array=characters[actor].shared.get(target,[])
			for index in range(memories.size()-1,-1,-1):
				var memory: Dictionary=memories[index]
				if memory.actor!=memory.target and memory.kind in ["help","accept","refuse"] and int(memory.id) not in told:
					return memory
			return {}
		return _shareable(actor,target)
	if not _whole(payload.event,1,next_event-1):
		return {}
	for memory in characters[actor].memory+characters[actor].summaries:
		if int(memory.id)==int(payload.event):
			return memory
	return {}

func _conflict_known(actor: String, target: String, payload: Dictionary={}) -> Dictionary:
	if payload.has("event"):
		var claim:=_source_topic(actor,target,payload)
		return claim if not claim.is_empty() and claim.kind in ["argue","discontent"] and target in [claim.actor,claim.target] else {}
	var memories: Array = characters[actor].summaries+characters[actor].memory
	for i in range(memories.size()-1,-1,-1):
		var memory: Dictionary = memories[i]
		if memory.kind in ["argue","discontent"] and target in [memory.actor,memory.target]:
			return memory
	return {}

func _random() -> float:
	seed=(seed*1103515245+12345)&0x7fffffff
	return float(seed)/2147483648.0

func choose(actor: String, target: String, fatigue: float) -> Dictionary:
	var person: Dictionary = characters[actor]
	var traits: Dictionary = person.traits
	var relation := relationship(actor,target)
	if not person.pending.is_empty() and person.pending.from==target:
		var acceptance: float = float(traits.sociability)+float(traits.principle)*0.5+float(relation.trust)-float(relation.dislike)-float(person.emotion.anger)-fatigue-float(traits.ambition)*0.2
		if person.beliefs.has("держать слово"):
			acceptance+=10
		acceptance+=float(person.emotion.joy)*0.2
		return {"action":"accept" if acceptance>35 else "refuse","reason":"Оценка просьбы %.0f: доверие, принципы, настроение, усталость" % acceptance}
	if person.grievances.has(target) and float(relation.dislike)>28 and float(traits.aggression)+float(person.emotion.anger)>80:
		return {"action":"argue","reason":"Неприязнь и раздражение сильнее осторожности"}
	if float(relation.dislike)>18 and float(traits.principle)>65 and float(traits.sociability)>50:
		return {"action":"reconcile","reason":"Желание мира важнее прошлой обиды"}
	if fatigue>50 and int(person.requested_until)<=last_minute:
		return {"action":"request_help","reason":"Усталость: ищет того, кому ещё доверяет"}
	if person.grievances.has(target) and float(person.emotion.anger)>12:
		return {"action":"discontent","reason":"Работа не удалась: хочет высказать недовольство"}
	if int(person.blocked_until)>last_minute and float(traits.sociability)>30 and int(person.requested_until)<=last_minute:
		return {"action":"request_help","reason":"Для ремесленной цели не хватает материалов: ищет содействия"}
	if person.long_goal in ["help","peace"]:
		return {"action":"help","reason":"Личный принцип: поддерживать других"}
	if float(traits.ambition)>65 and float(person.emotion.anger)>60 and not _source_topic(actor,target,{"distort":true}).is_empty():
		return {"action":"inform","distort":true,"reason":"Сильная обида толкает приукрасить рассказ против собственных принципов"}
	if float(traits.sociability)>65 and not _shareable(actor,target).is_empty():
		return {"action":"inform","reason":"Знает новое событие и хочет поделиться"}
	if person.long_goal in ["craft","recognition"] and float(relation.trust)>-10 and (person.work_available or characters[target].work_available) and int(person.requested_until)<=last_minute:
		return {"action":"offer_cooperation","reason":"Для личной цели нужен партнёр"}
	return {"action":"talk","reason":"Ищет общения"}

func tick(state: RefCounted) -> void:
	var minute: int = state.life.clock.minute
	if state.life.clock.paused or minute<=last_minute:
		return
	last_minute=minute
	for id in characters:
		var person: Dictionary = characters[id]
		for mood in person.emotion:
			person.emotion[mood]=snappedf(maxf(0,float(person.emotion[mood])-0.025),0.001)
		if not person.pending.is_empty() and minute-int(person.pending.minute)>180:
			person.pending={}
		for other in person.grievances.keys():
			if minute>int(person.grievances[other].until):
				person.grievances.erase(other)
		if id!="player":
			var resident: Dictionary = state.life.people[id]
			person.work_available=projects.has(id) or id=="test_smith" and not state.economy.jobs.smith.is_empty()
			if resident.has("social_goal") and minute>=int(resident.get("social_goal_until",0)):
				resident.erase("social_goal")
				state.life.refresh_assignment(id)
	_projects(state)
	if minute%15!=0:
		return
	var ids: Array = state.life.people.keys()
	ids.sort()
	for actor in ids:
		var person: Dictionary = characters[actor]
		var resident: Dictionary = state.life.people[actor]
		if resident.activity=="sleep" or minute<int(person.cooldown) or minute<int(resident.get("social_hold_until",0)) or resident.fatigue>80:
			continue
		if resident.activity=="wait" and resident.reason=="conversation" and (person.pending.is_empty() or person.pending.from!="player"):
			continue
		if float(person.traits.sociability)<20 and person.pending.is_empty() and minute%240!=0:
			continue
		if float(person.emotion.fear)>20 and (float(person.traits.caution)>70 or person.fears.has("ссоры")):
			person.plan="Избегать ссор и побыть в покое"
			person.reason="Страх после наблюдаемого конфликта"
			if resident.task=="errand":
				var refuge: Vector2=Definitions.PEOPLE[actor].rest
				resident.social_goal=[refuge.x,refuge.y]
				resident.social_goal_until=minute+45
				state.life.refresh_assignment(actor)
			continue
		var candidates: Array = []
		for target in ids+["player"]:
			if target==actor:
				continue
			if minute-int(person.contacts.get(target,-1000))<90 and (person.pending.is_empty() or person.pending.from!=target):
				continue
			var other := spatial(state,target)
			if other.location==resident.location and other.awake and other.position.distance_to(resident.position)<140 and state.adventure.clear_line(resident.location,resident.position,other.position):
				candidates.append(target)
		if candidates.is_empty():
			continue
		var target: String = str(candidates[0])
		var best := -INF
		for candidate in candidates:
			var attitude := relationship(actor,candidate)
			# Preference, uncertainty and emotion; not an omniscient profit maximum.
			var score: float=float(attitude.attachment)*0.4+float(attitude.trust)*0.4-float(attitude.dislike)+_random()*15
			if person.grievances.has(candidate) and float(person.traits.aggression)>50:
				score+=80
			if score>best:
				best=score
				target=str(candidate)
		if not person.pending.is_empty() and person.pending.from in candidates:
			target=person.pending.from
		var decision := choose(actor,target,resident.fatigue)
		person.plan=LABELS[decision.action]+": "+name_of(target)
		person.reason=decision.reason
		var response := execute(state,actor,target,decision.action,{"distort":bool(decision.get("distort",false))})
		person.reason=decision.reason+" · "+str(response.reason)
		# Habits yield to a chosen relationship during free time, not teleportation.
		if resident.task=="errand" and resident.location=="town":
			var point: Vector2 = spatial(state,target).position
			var offset: Vector2 = point.direction_to(resident.position)*48
			if offset.is_zero_approx():
				offset=Vector2(48,0)
			if state.life.navigation.clear_segment(point,point+offset):
				point+=offset
			var relation := relationship(actor,target)
			if float(relation.dislike)>50:
				point=Definitions.PEOPLE[actor].rest
			resident.social_goal=[point.x,point.y]
			resident.social_goal_until=minute+30
			state.life.refresh_assignment(actor)

func _projects(state: RefCounted) -> void:
	var minute: int = state.life.clock.minute
	var ledger = state.economy.ledger
	for id in state.life.people:
		var definition: Dictionary = Definitions.PEOPLE[id]
		if definition.get("profession","")!="metalworker":
			continue
		var resident: Dictionary = state.life.people[id]
		if resident.activity!="work" or resident.location!="town":
			continue
		var owner: String = "process:social:"+str(id)
		if not projects.has(id):
			if minute%30!=0:
				continue
			if ledger.reserve("workshop",owner,{"test_iron_ore":2}):
				var started := _event(state,"project",id,id,"Зарезервированы 2 железные руды со склада; слиток вернётся на склад")
				projects[id]={"recipe":"iron_ingot","progress":0,"started_event":started.id}
			elif minute>=int(characters[id].blocked_until):
				characters[id].blocked_until=minute+360
				characters[id].emotion.anger=minf(100,float(characters[id].emotion.anger)+20)
				characters[id].reason="Не хватает общей руды для личной ремесленной цели"
				var shortage := _event(state,"shortage",id,id,"Не удалось начать работу: на складе меньше двух руд")
				for rival in projects:
					if rival!=id and state.life.people[rival].position.distance_to(resident.position)<180:
						characters[id].grievances[rival]={"event":shortage.id,"until":minute+180}
			continue
		var project: Dictionary = projects[id]
		var credit: int = mini(1,int(resident.get("assist_credit",0)))
		project.progress=mini(20,int(project.progress)+1+credit)
		resident.assist_credit=int(resident.get("assist_credit",0))-credit
		if project.progress>=20 and ledger.transform(owner,"workshop",{"test_iron_ore":2},{"test_iron_ingot":1}):
			projects.erase(id)
			characters[id].completed+=1
			characters[id].emotion.joy=minf(100,float(characters[id].emotion.joy)+20)
			state.economy.produced["test_iron_ingot"]=int(state.economy.produced.get("test_iron_ingot",0))+1
			_event(state,"completed",id,id,"Слиток поступил на общий склад и доступен кузнецу",{"id":project.started_event})

func to_save() -> Dictionary:
	return _canonical({"characters":characters,"relations":relations,"history":history,"projects":projects,"next_event":next_event,"last_minute":last_minute,"seed":seed,"receipts":receipts})

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:
			result[key]=_canonical(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for entry in value:
			result.append(_canonical(entry))
		return result
	if value is float and is_finite(value):
		var rounded: float=snappedf(value,0.000001)
		if rounded==floorf(rounded):
			return int(rounded)
		return rounded
	return value

func load_data(data: Variant, state_life: RefCounted, ledger: RefCounted) -> bool:
	if not data is Dictionary or not data.get("characters") is Dictionary or not data.get("relations") is Dictionary or not data.get("history") is Array or not data.get("projects") is Dictionary or not data.get("receipts") is Array:
		return false
	if data.characters.size()!=characters.size() or data.relations.size()!=characters.size() or data.history.size()>MAX_HISTORY or data.receipts.size()>64:
		return false
	for key in ["next_event","seed"]:
		if not _whole(data.get(key),1 if key=="next_event" else 0,2147483647):
			return false
	if not _whole(data.get("last_minute"),-1,state_life.clock.minute):
		return false
	for receipt in data.receipts:
		if not receipt is String or receipt.length()>80:
			return false
	for id in characters:
		var person = data.characters.get(id)
		if not person is Dictionary or person.get("id")!=id or not person.get("traits") is Dictionary or not person.get("emotion") is Dictionary or not person.get("memory") is Array or not person.get("summaries") is Array or not person.get("knowledge") is Dictionary or not person.get("pending") is Dictionary:
			return false
		if person.memory.size()>MAX_MEMORY or person.summaries.size()>MAX_SUMMARIES or person.knowledge.size()>12:
			return false
		for key in ["grievances","contacts","shared"]:
			if not person.get(key) is Dictionary or person[key].size()>characters.size():
				return false
		for other in person.shared:
			if not characters.has(other) or not person.shared[other] is Array or person.shared[other].size()>8:
				return false
			for event_id in person.shared[other]:
				if not _whole(event_id,1,int(data.next_event)-1):
					return false
		for other in person.contacts:
			if not characters.has(other) or not _whole(person.contacts[other],0,state_life.clock.minute):
				return false
		for other in person.grievances:
			var grievance=person.grievances[other]
			if not characters.has(other) or not grievance is Dictionary or not _whole(grievance.get("event"),1,int(data.next_event)-1) or not _whole(grievance.get("until"),0,1000000010):
				return false
		for key in ["caution","sociability","ambition","principle","aggression"]:
			if not _number(person.traits.get(key),0,100):
				return false
		for key in ["anger","fear","joy"]:
			if not _number(person.emotion.get(key),0,100):
				return false
		for key in ["cooldown","blocked_until","completed","last_topic","requested_until"]:
			if not _whole(person.get(key),0,1000000010):
				return false
		if not person.get("work_available") is bool:
			return false
		for key in ["long_goal","plan","reason","last_partner","last_action","biography"]:
			if not person.get(key) is String or person[key].length()>512:
				return false
		for key in ["beliefs","wishes","fears"]:
			if not person.get(key) is Array or person[key].size()>8:
				return false
			for entry in person[key]:
				if not entry is String or entry.length()>256:
					return false
		for topic in person.knowledge:
			var fact=person.knowledge[topic]
			if not topic is String or topic.length()>100 or not fact is Dictionary or not _whole(fact.get("event"),1,int(data.next_event)-1) or not characters.has(fact.get("source")) or not _number(fact.get("confidence"),0,1):
				return false
		if not person.pending.is_empty() and (not characters.has(person.pending.get("from")) or person.pending.get("kind") not in ["request_help","offer_cooperation"] or not _whole(person.pending.get("minute"),0,state_life.clock.minute) or not _whole(person.pending.get("event"),1,int(data.next_event)-1)):
			return false
		for memory in person.memory+person.summaries:
			if not _valid_event(memory,int(data.next_event)) or not memory.get("source") is String or not characters.has(memory.source) or not memory.get("witnessed") is bool or not memory.get("interpretation") is String or not memory.get("effects") is Dictionary:
				return false
		if not data.relations.get(id) is Dictionary or data.relations[id].size()>characters.size():
			return false
		for other in data.relations[id]:
			var relation = data.relations[id][other]
			if not characters.has(other) or not relation is Dictionary or not relation.get("history") is Array or relation.history.size()>8:
				return false
			if not relation.get("last_summary","") is String or str(relation.get("last_summary","")).length()>700:
				return false
			for key in ["attachment","trust","respect","dislike"]:
				if not _number(relation.get(key),-100 if key!="dislike" else 0,100):
					return false
			for event in relation.history:
				if not _whole(event,1,int(data.next_event)-1):
					return false
	var previous := 0
	for event in data.history:
		if not _valid_event(event,int(data.next_event)) or int(event.id)<=previous or not event.get("witnesses") is Array or not event.get("effects") is Dictionary:
			return false
		if event.witnesses.size()>characters.size():
			return false
		if not event.get("misleading",false) is bool or event.has("original_kind") and not LABELS.has(event.original_kind):
			return false
		for witness in event.witnesses:
			if not characters.has(witness):
				return false
		for witness in event.effects:
			if not characters.has(witness) or not _valid_effects(event.effects[witness]):
				return false
		previous=int(event.id)
	for id in data.projects:
		var job = data.projects[id]
		if not state_life.people.has(id) or not job is Dictionary or job.get("recipe")!="iron_ingot" or not _whole(job.get("progress"),0,20) or not _whole(job.get("started_event"),1,int(data.next_event)-1) or ledger.owners["process:social:"+id].items!={"test_iron_ore":2}:
			return false
	for id in state_life.people:
		if not data.projects.has(id) and not ledger.owners["process:social:"+id].items.is_empty():
			return false
	characters=data.characters.duplicate(true)
	relations=data.relations.duplicate(true)
	history=data.history.duplicate(true)
	projects=data.projects.duplicate(true)
	next_event=int(data.next_event)
	last_minute=int(data.last_minute)
	seed=int(data.seed)
	receipts=data.receipts.duplicate()
	return true

func _valid_event(event: Variant, next: int) -> bool:
	if event is Dictionary:
		if not event.get("subject","") is String or str(event.get("subject","")).length()>40 or not event.get("statement","") is String or str(event.get("statement","")).length()>512:
			return false
		if event.has("statement_source") and not characters.has(event.statement_source):
			return false
		if event.has("accounts"):
			if not _valid_accounts(event.accounts,next):
				return false
			for account in event.accounts.values():
				if account.basis=="verified" and (not event.get("witnessed",false) or account.kind!=event.get("kind","") or account.get("actor",event.get("actor",""))!=event.get("actor","") or account.get("target",event.get("target",""))!=event.get("target","")):
					return false
	return event is Dictionary and _whole(event.get("id"),1,next-1) and _whole(event.get("minute"),0,1000000000) and LABELS.has(event.get("kind")) and characters.has(event.get("actor")) and characters.has(event.get("target")) and event.get("consequence") is String and event.consequence.length()<=512 and event.get("reason","") is String and str(event.get("reason","")).length()<=1024 and _whole(event.get("topic",0),0,next-1) and _valid_effects(event.get("effects",{}),event.has("witnesses"))

func _valid_effects(value: Variant, group: bool = false) -> bool:
	if not value is Dictionary:
		return false
	if group or value.is_empty():
		return true
	if not characters.has(value.get("toward")) or not value.get("delta") is Dictionary or value.delta.size()>4:
		return false
	for key in value.delta:
		if key not in ["attachment","trust","respect","dislike"] or not _number(value.delta[key],-100,100):
			return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high
static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value)==floorf(float(value))

# Reports are evidence attached to an existing memory, never a second truth ledger.
func _record_account(listener: String, speaker: String, claim: Dictionary, minute: int, statement: String) -> void:
	for memory in characters[listener].memory+characters[listener].summaries:
		if int(memory.id)!=int(claim.id):
			continue
		if not memory.has("accounts"):
			memory["accounts"]={}
		var basis: String="account" if claim.get("witnessed",false) else "rumour"
		if memory.witnessed and memory.kind==claim.kind and memory.actor==claim.actor and memory.target==claim.target:
			basis="verified"
		var text: String=(statement if not statement.is_empty() else str(claim.consequence)).left(384)
		var prior: Dictionary=memory.accounts.get(speaker,{})
		var statements: Array=[]
		if not prior.is_empty() and prior.kind==claim.kind and prior.get("actor",claim.actor)==claim.actor and prior.get("target",claim.target)==claim.target:
			statements=prior.get("statements",[prior.statement]).duplicate()
			if text in statements and prior.basis==basis:
				return
		if text not in statements:
			statements.append(text)
		if statements.size()>4:
			statements.pop_front()
		memory.accounts[speaker]={"source":speaker,"origin":str(claim.get("source",speaker)),"kind":claim.kind,"actor":claim.actor,"target":claim.target,"minute":minute,"order":next_event-1,"basis":basis,"statement":text,"statements":statements,"confidence":clampf((float(relation_view(listener,speaker).trust)+100)/200,0.1,0.9)}
		if memory.accounts.size()>MAX_ACCOUNTS:
			var sources: Array=memory.accounts.keys()
			sources.sort_custom(func(a:String,b:String):return a<b if int(memory.accounts[a].get("order",0))==int(memory.accounts[b].get("order",0)) else int(memory.accounts[a].get("order",0))<int(memory.accounts[b].get("order",0)))
			memory.accounts.erase(sources[0])
		return

func _valid_accounts(value: Variant, _next: int) -> bool:
	if not value is Dictionary or value.size()>MAX_ACCOUNTS:
		return false
	for source in value:
		var entry=value[source]
		if not characters.has(source) or not entry is Dictionary or entry.get("source")!=source or not characters.has(entry.get("origin")) or not LABELS.has(entry.get("kind")) or (entry.has("actor") and not characters.has(entry.actor)) or (entry.has("target") and not characters.has(entry.target)) or entry.get("basis") not in ["account","rumour","verified"] or not _whole(entry.get("minute"),0,1000000000) or not _whole(entry.get("order",1),1,_next-1) or not _number(entry.get("confidence"),0.1,0.9) or not entry.get("statement") is String or entry.statement.length()>384:
			return false
		if entry.has("statements"):
			if not entry.statements is Array or entry.statements.is_empty() or entry.statements.size()>4:
				return false
			for text in entry.statements:
				if not text is String or text.length()>384:
					return false

	return true
