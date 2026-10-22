extends RefCounted
## Encounter-local topic navigation. All lasting effects belong to SocialSimulation.
var state: RefCounted
var npc_id: String
var topic := "greeting"
var line := ""
var provenance := ""
var asked: Dictionary={}
var current_event: Dictionary={}
var available := true
var ended := false
var choices: Array[Dictionary]=[]
var refusal := ""
var requested_event := 0
var shown_reply := 0
const Speech=preload("res://scripts/simulation/npc_speech.gd")
const Language=preload("res://scripts/data/conversation_language.gd")
const PORTRAITS=preload("res://scripts/data/conversation_art.gd")

func start(world: RefCounted, target: String) -> void:
	state=world
	npc_id=target
	var person: Dictionary=state.social.characters[npc_id]
	var attitude: Dictionary=state.social.relation_view(npc_id,"player")
	var familiar: bool=person.contacts.has("player")
	available=state.social.spatial(state,npc_id).get("awake",false)
	if not available:
		line="Собеседник отдыхает и не отвечает. Лучше вернуться позже."
		ended=true
	elif attitude.dislike>65 and person.emotion.anger>50:
		line="После того, что между нами было, я сейчас говорить не хочу."
		ended=true
	elif attitude.trust>=30:
		line="Хорошо вас видеть. С вами можно говорить прямо. Что привело?"
		var remembered:=_memory_with_player()
		if not remembered.is_empty() and remembered.kind in ["help","accept","support"]:
			line="Я помню вашу поддержку. Вы пришли вовремя — для вас у меня найдётся минута."
	elif person.emotion.anger>35:
		line="День и без того неспокойный. Если у вас дело — говорите."
	elif state.life.people[npc_id].fatigue>70:
		line="Я сегодня без сил. Давайте без долгих расспросов."
	elif person.traits.aggression>65:
		line="Говорите. Только по делу."
	elif not familiar:
		line="Мы ещё не знакомы. Вы по делу или просто хотели поговорить?" if person.traits.caution>60 else "Кажется, мы ещё не встречались. О чём хотите поговорить?"
	else:
		line="Снова здравствуйте. Как ваши дела?" if person.traits.sociability>65 else "Здравствуйте. Я вас помню. Что хотели?"
	if available and not ended and not state.life.clock.paused:
		state.talk_to(npc_id)
	menu()

func _memory_with_player() -> Dictionary:
	var person: Dictionary=state.social.characters[npc_id]
	var memories: Array=person.summaries+person.memory
	for i in range(memories.size()-1,-1,-1):
		if memories[i].actor=="player" and memories[i].kind in ["help","accept","support"]:
			return memories[i]
	for i in range(memories.size()-1,-1,-1):
		if "player" in [memories[i].actor,memories[i].target] and memories[i].kind!="talk":
			return memories[i]
	return {}

func _already(subject: String) -> bool:
	if asked.has(subject):
		return true
	for memory in state.social.characters.player.memory+state.social.characters.player.summaries:
		if memory.get("subject","")==subject and npc_id in [memory.actor,memory.target]:
			return true
	return false

func menu() -> void:
	choices=[]
	if ended:
		choices.append({"id":"leave","text":"Не буду вас задерживать."})
		return
	if topic in ["greeting","topics"]:
		choices.append({"id":"self","text":"Напомните, чем вы занимаетесь." if _already("self") else "Расскажите немного о себе."})
		choices.append({"id":"conflict","text":"Хочу услышать вашу версию того спора."} if not _known_conflict().is_empty() else {"id":"news","text":"Что происходит в районе?"})
		var profession: String = str(state.life.definitions[npc_id].get("profession", ""))
		choices.append({"id":"trade","text":"Покажите ваши товары." if profession=="merchant" else "Хочу продать руду."} if profession in ["smith","merchant"] else {"id":"work","text":"Как работа? Нужна помощь?"})
	elif topic in ["news","conflict","detail","source","participant"] and not current_event.is_empty():
		if not asked.has("detail_"+str(current_event.id)):
			choices.append({"id":"detail","text":"С чего началось ваше разногласие?" if current_event.kind in ["argue","discontent"] and npc_id in [current_event.actor,current_event.target] else "А что было перед этим?"})
		if not asked.has("source_"+str(current_event.id)) and not asked.has("participant_"+str(current_event.id)):
			choices.append({"id":"source","text":"Откуда вы об этом узнали?" if not current_event.get("witnessed",false) else "Вы были рядом, когда это случилось?" if npc_id not in [current_event.actor,current_event.target] else "Как вы ладите с %s?"%Language.name_form(str(current_event.target if current_event.actor==npc_id else current_event.actor),2)})
		if choices.size()<2 and not asked.has("participant_"+str(current_event.id)) and not choices.any(func(c:Dictionary):return c.id=="source"):
			choices.append({"id":"participant","text":"А что скажете о другом участнике?"})
		if current_event.kind in ["argue","discontent"] and npc_id in [current_event.actor,current_event.target] and choices.size()<3:
			choices.append({"id":"stance","text":"Можно высказать своё мнение?"})
		if choices.size()<3:
			choices.append({"id":"topics","text":"Давайте о другом."})
	elif topic=="stance":
		choices.append({"id":"support","text":"Понимаю, почему вас это задело."})
		choices.append({"id":"oppose","text":"По-моему, вы были неправы."})
		choices.append({"id":"topics","text":"Не стану судить. Поговорим о другом."})
	elif topic=="work":
		var pending: Dictionary=state.social.characters.player.pending
		if pending.get("from","")==npc_id:
			choices.append({"id":"accept","text":"Хорошо, помогу с подготовкой."})
			choices.append({"id":"refuse","text":"Сейчас не смогу помочь."})
		else:
			choices.append({"id":"help","text":"Давайте помогу с подготовкой."})
			choices.append({"id":"request_help","text":"А вы сможете помочь мне?"})
		choices.append({"id":"topics","text":"Хотел спросить ещё кое-что."})
	elif topic=="self":
		choices.append({"id":"work","text":"Как сейчас идёт работа?"})
		choices.append({"id":"news","text":"А что у вас нового?"})
		choices.append({"id":"topics","text":"У меня другой вопрос."})
	else:
		choices.append({"id":"topics","text":"Можно ещё один вопрос?"})
	choices.append({"id":"leave","text":"Спасибо за разговор. До встречи."})

func reason_for(id: String) -> String:
	if id in ["leave","topics","stance"]:
		return ""
	if state.life.clock.threatened:
		return "Рядом опасность. Сейчас не время для разговора."
	if state.life.clock.paused:
		return "Пауза: продолжите время, чтобы ответить собеседнику."
	if id=="trade":
		return ""
	return state.social.check_action(state,"player",npc_id,"ask_news" if id in ["news","detail","conflict"] else "talk" if id in ["self","work","source","participant"] else id)

func choose(id: String) -> Dictionary:
	refusal=reason_for(id)
	if not refusal.is_empty():
		return {"ok":false,"reason":refusal}
	if id=="leave":
		ended=true
		return {"ok":true,"close":true}
	if id=="trade":
		return {"ok":true,"trade":true}
	if id in ["topics","stance"]:
		topic=id
		if id=="stance":
			line="Говорите. Только спорить у меня сейчас нет желания." if state.social.characters[npc_id].emotion.anger>35 else "Слушаю. Что вы об этом думаете?"
		menu()
		return {"ok":true}
	var social=state.social
	var person: Dictionary=social.characters[npc_id]
	var attitude: Dictionary=social.relation_view(npc_id,"player")
	var response: Dictionary={}
	provenance=""
	if id in ["news","detail","conflict","source","participant"]:
		if attitude.trust<0 or (person.emotion.anger>65 and person.traits.caution>50):
			line="Мы уже об этом говорили. Сейчас я не хочу это обсуждать." if _already("news_declined") else "Пока не хочу обсуждать это с вами. Сначала нам стоит разобраться между собой."
			var declined: Dictionary=social.execute(state,"player",npc_id,"talk",{"subject":"news_declined","statement":line})
			if not declined.ok:
				refusal=declined.reason
				return declined
			asked[id]=true
			topic="declined"
			menu()
			return {"ok":true}
		var event: Dictionary=current_event if id in ["detail","source","participant"] else _known_conflict() if id=="conflict" else _news()
		if event.is_empty():
			current_event={}
			line="Ничего нового, о чём я мог бы рассказать уверенно. Не хочу повторять пустые слухи."
			response=social.execute(state,"player",npc_id,"talk",{"subject":"news","statement":line})
		else:
			current_event=event.duplicate(true)
			var intent: String="participant" if id=="source" and npc_id in [event.actor,event.target] and event.get("witnessed",false) else id if id in ["detail","source","participant"] else "account"
			line=Speech.account(state,npc_id,event,intent).left(384)
			if intent in ["source","participant"]:
				asked[intent+"_"+str(event.id)]=true
			provenance="Источник: "+social.name_of(npc_id)+(" · рассказ очевидца, не проверен героем" if event.get("witnessed",false) else " · непроверенный слух")
			for known in social.characters.player.memory+social.characters.player.summaries:
				if int(known.id)==int(event.id) and known.witnessed and known.kind==event.kind and known.actor==event.actor and known.target==event.target:
					provenance="Источник: "+social.name_of(npc_id)+" · сверено с личным наблюдением"
			response=social.execute(state,"player",npc_id,"ask_news",{"event":int(event.id),"subject":id,"statement":line})
			topic=id if id in ["detail","source","participant"] else "conflict"
			if id=="detail":
				asked["detail_"+str(event.id)]=true
	elif id=="self":
		line="Вы уже спрашивали. " if _already("self") else ""
		line+=PORTRAITS.public_introduction(npc_id)
		if attitude.trust>=30:
			line+=" Если понадобится совет по моему делу — приходите."
		elif person.traits.sociability<30:
			line+=" О личном я говорить не люблю."
		response=social.execute(state,"player",npc_id,"talk",{"subject":"self","statement":line})
		topic="self"
	elif id=="work":
		var resident: Dictionary=state.life.people[npc_id]
		line="Сейчас отдыхаю; к работе вернусь позже." if resident.task!="work" else "Работа понемногу движется."
		if social.projects.has(npc_id):
			line="Материал для работы уже отложен. Сейчас занимаюсь своим изделием."
		elif int(person.blocked_until)>state.life.clock.minute:
			line="Работа встала: не хватает материалов. Приходится ждать или искать помощь."
		if state.social.characters.player.pending.get("from","")==npc_id:
			line+=" Мне как раз нужна помощь с подготовкой. Возьмётесь?"
		elif resident.fatigue>35:
			line+=" Поддержка с подготовкой мне бы пригодилась."
		response=social.execute(state,"player",npc_id,"talk",{"subject":"work","statement":line})
		topic="work"
	else:
		response=social.execute(state,"player",npc_id,id,{"event":int(current_event.id)} if id in ["support","oppose"] and not current_event.is_empty() else {})
		if response.ok:
			if id=="request_help":
				requested_event=int(response.event)
			line={"help":"Спасибо. Вы действительно облегчили мне работу — я это запомню.","request_help":"Дайте немного времени. Я подумаю, смогу ли помочь.","accept":"Спасибо, что согласились. Ваша помощь сейчас кстати.","refuse":"Жаль. Значит, придётся попросить кого-нибудь другого.","support":"Спасибо, что выслушали меня. От этого уже немного легче.","oppose":"Вот как вы считаете? Мне неприятно это слышать."}.get(id,str(response.reason))
			topic="response"
			if id=="oppose" and (person.traits.aggression>65 or person.emotion.anger>65):
				line="Мне неприятно это слышать. Сейчас я продолжать разговор не хочу."
				ended=true
				available=false
	if not response.get("ok",false):
		refusal="Сейчас не получается. Давайте вернёмся к этому позже."
		return response
	asked[id]=true
	if topic not in ["self","work","conflict","detail","source","participant","response"]:
		topic=id
	menu()
	return {"ok":true}

func _news() -> Dictionary:
	var memories: Array=state.social.characters[npc_id].summaries+state.social.characters[npc_id].memory
	for kinds in [["argue","discontent"],["refuse","help","accept","completed","shortage"]]:
		for involved in [true,false]:
			for i in range(memories.size()-1,-1,-1):
				var memory: Dictionary=memories[i]
				if (npc_id in [memory.actor,memory.target])!=involved:
					continue
				if memory.kind in kinds and "player" not in [memory.actor,memory.target] and int(memory.id) not in state.social.characters[npc_id].shared.get("player",[]):
					return memory
	return {}

func _account(event: Dictionary, detail: bool) -> String:
	return Speech.account(state,npc_id,event,"detail" if detail else "account")

func _known_conflict() -> Dictionary:
	var known: Array[int]=[]
	for memory in state.social.characters.player.summaries+state.social.characters.player.memory:
		known.append(int(memory.id))
	var memories: Array=state.social.characters[npc_id].summaries+state.social.characters[npc_id].memory
	for i in range(memories.size()-1,-1,-1):
		var memory: Dictionary=memories[i]
		if int(memory.id) in known and memory.kind in ["argue","discontent"] and npc_id in [memory.actor,memory.target]:
			return memory
	return {}

func refresh_state() -> void:
	if ended or state.life.clock.paused:
		return
	var person: Dictionary=state.social.characters[npc_id]
	var position: Dictionary=state.social.spatial(state,npc_id)
	if topic=="response" and requested_event>0:
		for memory in person.memory:
			if memory.actor==npc_id and memory.kind in ["accept","refuse"] and int(memory.topic)==requested_event and int(memory.id)!=shown_reply:
				line="С подготовкой я вам %s. Теперь вернусь к своим делам."%Language.past(npc_id,"помог","помогла") if memory.kind=="accept" else "Насчёт вашей просьбы... Простите, сейчас помочь не смогу."
				shown_reply=int(memory.id)
	if not position.get("awake",false) or position.get("location","")!=state.location_id or position.position.distance_to(state.player_position)>140:
		line="Простите, мне нужно отдохнуть. Давайте поговорим в другой раз."
		ended=true
		available=false
	elif person.emotion.anger>85 and state.social.relation_view(npc_id,"player").dislike>50:
		line="Меня это слишком злит. На этом закончим."
		ended=true
		available=false
	if ended:
		provenance=""
		menu()
