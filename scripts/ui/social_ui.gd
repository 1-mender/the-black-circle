extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
const Language=preload("res://scripts/data/conversation_language.gd")
const ConversationView=preload("res://scripts/ui/conversation_view.gd")
var dialogue: Control
var window: Control:
	get: return dialogue.window if direct else journal_window
var portrait: TextureRect:
	get: return dialogue.portrait if direct else journal_portrait
var context: Control:
	get: return dialogue.context if direct else journal_context
var feedback: Label:
	get: return dialogue.feedback if direct else journal_feedback
var trade_button: Button:
	get: return dialogue.trade_button if direct else journal_trade_button
var actions: Dictionary:
	get: return dialogue.actions if direct else journal_actions

signal close_requested
signal action_requested(target: String, action: String)
signal trade_requested(target: String)
var title: Label
var direct := false
var tabs: TabBar
var journal_portrait: TextureRect
var journal_context: Label
var journal_trade_button: Button
var action_grid: GridContainer
var journal_window: PanelContainer
var state: RefCounted
var selected_id := "test_npc"
var developer := false
var picker: OptionButton
var journal: RichTextLabel
var card: RichTextLabel
var journal_feedback: Label
var journal_actions: Dictionary = {}
var interval := 0.0
var response := ""
var dev_toggle: CheckButton

func _ready() -> void:
	layer=5
	dialogue=ConversationView.new()
	add_child(dialogue)
	dialogue.close_requested.connect(func():close_requested.emit())
	dialogue.trade_requested.connect(func(target:String):trade_requested.emit(target))
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(root)
	journal_window=PanelContainer.new()
	root.add_child(journal_window)
	var style:=UIStyle.style()
	style.bg_color=UIStyle.BACKGROUND
	style.border_color=UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	journal_window.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	journal_window.add_child(box)
	var heading:=HBoxContainer.new()
	box.add_child(heading)
	title=Label.new()
	title.text="ЖИТЕЛИ И СОБЫТИЯ · тестовый район"
	title.add_theme_color_override("font_color",UIStyle.GOLD)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button:=Button.new()
	close_button.text="Закрыть · O / Esc"
	close_button.pressed.connect(func():close_requested.emit())
	heading.add_child(close_button)
	tabs=TabBar.new()
	for caption in ["Знакомства","События","Разработчик"]:
		tabs.add_tab(caption)
	tabs.tab_changed.connect(func(index:int):
		dev_toggle.button_pressed=index==2
		refresh())
	box.add_child(tabs)
	var intro:=HBoxContainer.new()
	box.add_child(intro)
	journal_portrait=TextureRect.new()
	journal_portrait.custom_minimum_size=Vector2(64,64)
	journal_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	journal_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	intro.add_child(journal_portrait)
	journal_context=Label.new()
	journal_context.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	journal_context.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	intro.add_child(journal_context)
	journal_trade_button=Button.new()
	journal_trade_button.text="Торговать"
	journal_trade_button.pressed.connect(func():trade_requested.emit(selected_id))
	intro.add_child(journal_trade_button)
	dev_toggle=CheckButton.new()
	dev_toggle.text="Режим разработчика: полные сведения (не знания героя)"
	dev_toggle.toggled.connect(func(value:bool):developer=value;refresh())
	box.add_child(dev_toggle)
	dev_toggle.hide()
	picker=OptionButton.new()
	for id in preload("res://scripts/data/resident_definitions.gd").PEOPLE:
		picker.add_item(preload("res://scripts/data/resident_definitions.gd").PEOPLE[id].name)
		picker.set_item_metadata(picker.item_count-1,id)
	picker.item_selected.connect(func(index:int):selected_id=picker.get_item_metadata(index);refresh())
	box.add_child(picker)
	var columns:=HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",18)
	box.add_child(columns)
	journal=_text(columns)
	card=_text(columns)
	var buttons:=GridContainer.new()
	action_grid=buttons
	buttons.columns=4
	box.add_child(buttons)
	for entry in [["talk","Поговорить"],["ask_news","Спросить о событиях"],["help","Предложить помощь"],["request_help","Попросить помощь"],["accept","Поддержать просьбу"],["refuse","Отклонить просьбу"],["support","Поддержать в споре"],["oppose","Осудить конфликт"],["reconcile","Примириться"],["offer_cooperation","Сотрудничать"]]:
		var button:=Button.new()
		button.text=entry[1]
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():action_requested.emit(selected_id,entry[0]))
		buttons.add_child(button)
		journal_actions[entry[0]]=button
	journal_feedback=Label.new()
	journal_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	journal_feedback.custom_minimum_size.y=36
	journal_feedback.add_theme_color_override("font_color",UIStyle.GOLD)
	box.add_child(journal_feedback)
	root.resized.connect(_layout)
	_layout()
	journal_window.hide()

func _text(parent: Control) -> RichTextLabel:
	var text:=RichTextLabel.new()
	text.bbcode_enabled=false
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	text.custom_minimum_size=Vector2(250,170)
	text.add_theme_font_size_override("normal_font_size",15)
	parent.add_child(text)
	return text

func _layout() -> void:
	if dialogue!=null:
		dialogue._layout()
	if journal_window==null:
		return
	var size:=get_viewport().get_visible_rect().size
	var width:=minf(1040,size.x-64)
	var height:=minf(600,size.y-210)
	journal_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	journal_window.offset_left=-width/2
	journal_window.offset_right=width/2
	journal_window.offset_top=-height/2-15
	journal_window.offset_bottom=height/2-15

func open(value: RefCounted, target: String = "") -> void:
	state=value
	journal_window.hide()
	dialogue.close()
	direct=not target.is_empty()
	if direct:
		selected_id=target
		developer=false
		dialogue.open(state,target)
		return
	title.text="РАЗГОВОР" if direct else "ЖИТЕЛИ И СОБЫТИЯ · тестовый район"
	dev_toggle.button_pressed=false
	tabs.current_tab=0
	tabs.visible=not direct
	if not target.is_empty():
		selected_id=target
	for index in range(picker.item_count):
		if picker.get_item_metadata(index)==selected_id:
			picker.select(index)
	journal_window.show()
	response=""
	journal_feedback.text="Социальные действия требуют близости. Пауза останавливает мир; окно само по себе время не останавливает."
	refresh()

func close() -> void:
	dialogue.close()
	journal_window.hide()

func refresh() -> void:
	if direct:
		dialogue.refresh()
		return
	if state==null:
		return
	var social=state.social
	var known:=known_people()
	var available: Array[String]=[]
	for id in state.life.definitions:
		if developer or id in known or (direct and id==selected_id):
			available.append(id)
	var listed: Array[String]=[]
	for index in range(picker.item_count):
		listed.append(str(picker.get_item_metadata(index)))
	if available!=listed:
		picker.clear()
		for id in available:
			picker.add_item(social.name_of(id))
			picker.set_item_metadata(picker.item_count-1,id)
	if not developer and not direct and selected_id not in known:
		selected_id=str(picker.get_item_metadata(0)) if picker.item_count>0 else ""
	if selected_id.is_empty() and picker.item_count>0:
		selected_id=str(picker.get_item_metadata(0))
	journal.visible=not direct and (tabs.current_tab==1 or developer)
	card.visible=direct or tabs.current_tab!=1
	action_grid.visible=direct
	picker.visible=not direct and tabs.current_tab!=1
	journal_portrait.visible=direct
	journal_context.visible=direct
	journal_trade_button.visible=direct and selected_id in ["test_smith","test_merchant"]
	journal_trade_button.disabled=state.life.clock.paused
	journal_trade_button.tooltip_text="Продолжите время для торговли" if state.life.clock.paused else "Продажа руды" if selected_id=="test_smith" else "Покупка изделий"
	if selected_id.is_empty():
		card.text="Знакомств пока нет. Подойдите к жителям, чтобы познакомиться."
		journal.text="Нет известных событий."
		return
	if direct:
		var index: int=int(state.life.definitions[selected_id].get("sprite",0))
		var image:=AtlasTexture.new()
		image.atlas=preload("res://asset/characters/Actor1.png")
		image.region=Rect2((index%4)*144+48,floori(float(index)/4)*192,48,48)
		journal_portrait.texture=image
		var activity: String=state.life.people[selected_id].task
		journal_context.text=social.name_of(selected_id)+"\n"+{"work":"Я отвлёкся от работы. О чём хотите поговорить?","sleep":"Отдыхает. Лучше дождаться пробуждения.","rest":"Сейчас отдыхаю. Что вас привело?","walk":"Я в пути, но могу вас выслушать."}.get(activity,"Слушаю вас.")
		if state.social.characters.player.pending.get("from","")==selected_id:
			journal_context.text+="\nМне нужна помощь с подготовкой работы. Поможете?"
		if state.life.clock.paused:
			journal_context.text+="\nПауза: просмотр доступен. Продолжите время для действий."
	for index in range(picker.item_count):
		if picker.get_item_metadata(index)==selected_id:
			picker.select(index)
			break
	var events: Array = social.history if developer else social.characters.player.summaries+social.characters.player.memory
	var lines: Array[String]=["ИСТОРИЯ ГОРОДА · полная отладка" if developer else "ИЗВЕСТНО ГЕРОЮ · наблюдения и рассказы",""]
	for index in range(events.size()-1,-1,-1):
		var event: Dictionary=events[index]
		if not developer and event.kind in ["talk","inform","ask_news"] and event.get("subject","") not in ["self","work","news_declined"]:
			continue
		var day:=floori(float(event.minute)/1440)+1
		lines.append("День %d · %02d:%02d · %s\n%s → %s\n%s" % [day,floori(float(int(event.minute)%1440)/60),int(event.minute)%60,social.LABELS[event.kind],social.name_of(event.actor),social.name_of(event.target),event.consequence])
		if not developer and event.get("subject","") in ["self","work","news_declined"]:
			lines.append("В разговоре с "+Language.name_form(str(event.get("statement_source",event.target)),2,state)+":\n"+str(event.get("statement","")))
		for informant in event.get("accounts",{}):
			var account: Dictionary=event.accounts[informant]
			lines.append("Со слов "+Language.name_form(informant,3,state)+{"account":" (рассказ очевидца)","rumour":" (пересказ, не проверен)","verified":" (совпадает с увиденным мной)"}.get(account.basis,"")+": "+"\n".join(account.get("statements",[account.statement])))
		if event.has("interpretation"):
			if developer:
				lines.append(event.interpretation)
			elif not event.has("statement"):
				lines.append("Видел собственными глазами" if event.witnessed else "Узнал от "+Language.name_form(event.source,3,state)+". Пока не проверено.")
		if developer and event.get("misleading",false):
			lines.append("Сознательное искажение. Исходное событие: "+str(social.LABELS.get(event.get("original_kind",""),"неизвестно")))
		if developer and int(event.get("topic",0))>0:
			lines.append("Основание: событие #%d" % int(event.topic))
		if developer and not str(event.get("reason","")).is_empty():
			lines.append("Почему: "+str(event.reason))
		if not event.get("effects",{}).is_empty():
			lines.append(_effects(event.effects) if developer else _public_effects(event.effects))
		lines.append("")
	journal.text="\n".join(lines)
	var person: Dictionary=social.characters[selected_id]
	var relation: Dictionary=social.relation_view("player",selected_id)
	card.text=social.name_of(selected_id)+"\n\n"+attitude(relation)+"\n\n"
	if developer:
		var resident: Dictionary=state.life.people[selected_id]
		card.text+=str(person.biography)+"\n\n"
		var traits: Dictionary=person.traits
		var goal_names: Dictionary={"companionship":"Найти близкий круг","craft":"Стать полезным мастером","security":"Жить спокойно","reputation":"Заслужить доверие","recognition":"Добиться признания","help":"Поддерживать других","peace":"Сохранять мир"}
		card.text+="ID: %s\nОсторожность %.0f · общительность %.0f\nЧестолюбие %.0f · принципиальность %.0f · агрессия %.0f\nПринципы: %s\nЖелания: %s\nДолгая цель: %s\nСтрахи: %s\nГнев %.0f · страх %.0f · радость %.0f\nПлан: %s\nПричина: %s\nЗанятие: %s · цель %s\n\nЛичная память:\n" % [selected_id,traits.caution,traits.sociability,traits.ambition,traits.principle,traits.aggression,str(person.beliefs),str(person.wishes),goal_names.get(person.long_goal,person.long_goal),str(person.fears),person.emotion.anger,person.emotion.fear,person.emotion.joy,str(person.plan),str(person.reason),str(resident.activity),str(resident.goal)]
		for memory in person.summaries+person.memory:
			card.text+="#%d %s: %s (%s)\n" % [memory.id,social.LABELS[memory.kind],memory.consequence,memory.interpretation]
		card.text+="\nНАПРАВЛЕННЫЕ ОТНОШЕНИЯ ЭТОГО ЖИТЕЛЯ\n"
		for other in social.relations[selected_id]:
			var directed_relation: Dictionary=social.relations[selected_id][other]
			card.text+="%s: привязанность %.0f, доверие %.0f, уважение %.0f, неприязнь %.0f\n%s\n\n" % [social.name_of(other),directed_relation.attachment,directed_relation.trust,directed_relation.respect,directed_relation.dislike,str(directed_relation.get("last_summary",""))]
	else:
		if state.life.people[selected_id].location==state.location_id and state.player_position.distance_to(state.life.people[selected_id].position)<180 and state.adventure.clear_line(state.location_id,state.player_position,state.life.people[selected_id].position):
			card.text+="На виду: "+("Беседует" if state.life.people[selected_id].reason=="conversation" else str(preload("res://scripts/data/resident_definitions.gd").TASK_NAMES.get(state.life.people[selected_id].activity,"Занят делами")))+"\n\n"
		for memory in social.characters.player.memory:
			if selected_id in [memory.actor,memory.target]:
				card.text+="%s: %s\n%s\n\n" % [social.LABELS[memory.kind],memory.get("statement",memory.consequence),"Сказано в беседе" if memory.has("statement") else "Видел собственными глазами" if memory.witnessed else "Узнал от "+Language.name_form(memory.source,3,state)+". Пока не проверено."]
	var pending: Dictionary=social.characters.player.pending
	if not pending.is_empty():
		card.text+="\nПросьба от "+social.name_of(pending.from)+": помочь трудом с подготовкой работы. Согласие стоит 6 выносливости и даёт до 2 подготовительных рабочих минут. Можно ответить рядом с просителем."
	journal_feedback.text=response if not response.is_empty() else "Выберите ответ. Недоступные действия поясняются при наведении." if direct else "Сведения ограничены вашими встречами и услышанными рассказами."
	if developer:
		journal_feedback.text="Режим разработчика: полные сведения, недоступные герою."
	if state.life.clock.paused:
		journal_feedback.text="Пауза: можно читать и выбирать вкладки. Для действий продолжите время (Space)."
	for action in journal_actions:
		var reason: String=social.check_action(state,"player",selected_id,action)
		journal_actions[action].visible=action not in ["accept","refuse"] or (not pending.is_empty() and pending.from==selected_id)
		journal_actions[action].disabled=not reason.is_empty()
		journal_actions[action].tooltip_text=reason if not reason.is_empty() else social.LABELS[action]

func _effects(effects: Dictionary) -> String:
	var lines: Array[String]=[]
	var labels: Dictionary={"attachment":"привязанность","trust":"доверие","respect":"уважение","dislike":"неприязнь"}
	var entries: Array=[effects] if effects.has("toward") else effects.values()
	for entry in entries:
		if not entry is Dictionary or not entry.has("toward"):
			continue
		var changes: Array[String]=[]
		for key in entry.get("delta",{}):
			if float(entry.delta[key])!=0:
				changes.append("%s %+.0f" % [labels.get(key,key),entry.delta[key]])
		if not changes.is_empty():
			lines.append("К "+state.social.name_of(entry.toward)+": "+", ".join(changes))
	return "\n".join(lines)

func _process(delta: float) -> void:
	if not window.visible:
		return
	interval+=delta
	if interval>=0.5:
		interval=0
		refresh()

func known_people() -> Array[String]:
	var result: Array[String]=[]
	for id in state.social.characters.player.contacts:
		if id!="player":
			result.append(id)
	for memory in state.social.characters.player.summaries+state.social.characters.player.memory:
		for id in [memory.actor,memory.target]:
			if id!="player" and id not in result:
				result.append(id)
	for id in state.life.people:
		var person: Dictionary=state.life.people[id]
		if person.location==state.location_id and state.player_position.distance_to(person.position)<180 and state.adventure.clear_line(state.location_id,state.player_position,person.position):
			if id not in result:
				result.append(id)
	return result

func attitude(value: Dictionary) -> String:
	var descriptions: Array[String]=[]
	descriptions.append("Близкий знакомый" if value.attachment>25 else "Недавнее знакомство")
	descriptions.append("Вы доверяете этому человеку" if value.trust>25 else "Доверие ещё предстоит заслужить" if value.trust>=0 else "Вы относитесь к нему с недоверием")
	if value.respect>20:
		descriptions.append("Его поступки вызывают уважение")
	if value.dislike>15:
		descriptions.append("Между вами есть напряжение")
	return "\n".join(descriptions)

func _public_effects(effects: Dictionary) -> String:
	if not effects.has("toward"):
		return ""
	var descriptions: Array[String]=[]
	for key in effects.get("delta",{}):
		var delta: float=effects.delta[key]
		if is_zero_approx(delta):
			continue
		var positive: Dictionary={"attachment":"стали ближе","trust":"доверие укрепилось","respect":"уважение выросло","dislike":"напряжение усилилось"}
		var negative: Dictionary={"attachment":"отдалились","trust":"доверие пошатнулось","respect":"уважение снизилось","dislike":"напряжение уменьшилось"}
		descriptions.append(str((positive if delta>0 else negative).get(key,"отношение изменилось")))
	return "Ваше отношение к "+state.social.name_of(effects.toward)+": "+", ".join(descriptions) if not descriptions.is_empty() else ""
