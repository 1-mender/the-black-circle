extends Control
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
## A cinematic layer over the actual, still running meeting place.
signal close_requested
signal trade_requested(target: String)
const Session=preload("res://scripts/simulation/conversation_session.gd")
const Art=preload("res://scripts/data/conversation_art.gd")
var session: RefCounted
var window: Control
var portrait: TextureRect
var context: RichTextLabel
var feedback: Label
var trade_button: Button
var actions: Dictionary={}
var buttons: Array[Button]=[]
var answers: VBoxContainer
var speech: PanelContainer
var heading: Label
var speaker: Label
var source: Label
var pause_label: Label
var transition: Tween
var built_choices := ""
var elapsed := 0.0
var initial_focus := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window=self
	mouse_filter=Control.MOUSE_FILTER_STOP
	var backdrop:=ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop_shader:=ShaderMaterial.new()
	backdrop_shader.shader=preload("res://shaders/conversation_backdrop.gdshader")
	backdrop.material=backdrop_shader
	add_child(backdrop)
	# Letterbox and thin warm edges keep the map recognisable beneath the portrait.
	for bottom in [false,true]:
		var bar:=ColorRect.new()
		bar.color=UIStyle.BACKGROUND
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		bar.offset_top=-24 if bottom else 0
		bar.offset_bottom=0 if bottom else 24
		add_child(bar)
	heading=Label.new()
	heading.add_theme_font_size_override("font_size",14)
	heading.add_theme_color_override("font_color",UIStyle.GOLD)
	add_child(heading)
	portrait=TextureRect.new()
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	answers=VBoxContainer.new()
	answers.add_theme_constant_override("separation",10)
	add_child(answers)
	speech=PanelContainer.new()
	speech.add_theme_stylebox_override("panel",panel_style(UIStyle.BACKGROUND,UIStyle.BORDER,20))
	add_child(speech)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",7)
	speech.add_child(box)
	speaker=Label.new()
	speaker.add_theme_font_size_override("font_size",18)
	speaker.add_theme_color_override("font_color",UIStyle.GOLD)
	box.add_child(speaker)
	context=RichTextLabel.new()
	context.bbcode_enabled=false
	context.add_theme_font_size_override("normal_font_size",20)
	context.add_theme_color_override("default_color",UIStyle.TEXT)
	context.custom_minimum_size.y=0
	context.scroll_active=false
	context.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(context)
	source=Label.new()
	source.add_theme_font_size_override("font_size",13)
	source.add_theme_color_override("font_color",UIStyle.MUTED)
	box.add_child(source)
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",14)
	feedback.add_theme_color_override("font_color",UIStyle.GOLD)
	add_child(feedback)
	pause_label=Label.new()
	pause_label.add_theme_font_size_override("font_size",14)
	pause_label.add_theme_color_override("font_color",UIStyle.MUTED)
	add_child(pause_label)
	resized.connect(_layout)
	hide()

static func panel_style(background: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style:=UIStyle.style()
	style.bg_color=background
	style.border_color=border
	style.set_border_width_all(1)
	style.corner_radius_top_left=7
	style.corner_radius_bottom_right=7
	style.set_content_margin_all(margin)
	return style

func open(state: RefCounted, id: String) -> void:
	session=Session.new()
	session.start(state,id)
	portrait.texture=load(Art.portrait_path(id))
	portrait.tooltip_text=Art.portrait_note(id)
	heading.text=Art.portrait_note(id)
	heading.visible=not heading.text.is_empty()
	speaker.text=Session.Language.display_name(id)
	built_choices=""
	show()
	_layout()
	refresh()
	modulate.a=0.0
	if transition!=null and transition.is_valid():
		transition.kill()
	transition=create_tween()
	transition.tween_property(self,"modulate:a",1.0,0.24).set_trans(Tween.TRANS_SINE)

func close() -> void:
	if transition!=null and transition.is_valid():
		transition.kill()
	hide()

func _layout() -> void:
	if speech==null:
		return
	var viewport_size:=get_viewport_rect().size
	var edge:=maxf(40,viewport_size.x*0.055)
	heading.position=Vector2(edge,42)
	var scale_factor:=clampf(viewport_size.y/720,1.0,1.5)
	for entry in [[context,"normal_font_size",20],[speaker,"font_size",18],[source,"font_size",13],[heading,"font_size",14],[feedback,"font_size",14],[pause_label,"font_size",14]]:
		var font_size:=roundi(float(entry[2])*scale_factor)
		if entry[0].get_theme_font_size(entry[1])!=font_size:
			entry[0].add_theme_font_size_override(entry[1],font_size)
	for button in buttons:
		button.custom_minimum_size.y=44*scale_factor
		if button.get_theme_font_size("font_size")!=roundi(16*scale_factor):
			button.add_theme_font_size_override("font_size",roundi(16*scale_factor))
	var characters_per_line:=maxf(30,(viewport_size.x-2*edge-40)/(10.5*scale_factor))
	var lines:=ceili(float(context.text.length())/characters_per_line)
	var speech_height:=maxf(clampf(96+24*lines,142,216)*scale_factor,context.get_content_height()+116*scale_factor)
	var speech_top:=viewport_size.y-38-speech_height
	var portrait_height:=minf(490*scale_factor,viewport_size.y*0.60)
	portrait.position=Vector2(viewport_size.x*0.105,speech_top-portrait_height+12)
	portrait.size=Vector2(minf(440*scale_factor,viewport_size.x*0.36),portrait_height)
	answers.position=Vector2(viewport_size.x*0.54,maxf(112,viewport_size.y*0.235))
	answers.size.x=viewport_size.x-edge-answers.position.x
	speech.position=Vector2(edge,speech_top)
	speech.size=Vector2(viewport_size.x-2*edge,speech_height)
	feedback.position=Vector2(answers.position.x,speech_top-48)
	feedback.size=Vector2(answers.size.x,42)
	pause_label.position=Vector2(edge,viewport_size.y-28)
	pause_label.text="1–4: ответ   ·   ↑↓ / Enter: выбор   ·   E / Esc: закончить   ·   Space: пауза"

func refresh() -> void:
	if session==null:
		return
	session.refresh_state()
	if context.text!=session.line:
		context.text=session.line
		context.get_v_scroll_bar().value=0
	source.text=session.provenance
	source.hide()
	feedback.text="Пауза: можно читать. Для ответа продолжите время (Space)." if session.state.life.clock.paused else session.refusal
	var signature:=JSON.stringify(session.choices)
	if signature!=built_choices:
		built_choices=signature
		initial_focus=false
		for child in answers.get_children():
			answers.remove_child(child)
			child.queue_free()
		buttons.clear()
		actions.clear()
		trade_button=null
		for i in range(session.choices.size()):
			var choice: Dictionary=session.choices[i]
			var button:=Button.new()
			button.text="%d   %s"%[i+1,choice.text]
			button.alignment=HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size.y=44
			button.add_theme_font_size_override("font_size",16)
			button.add_theme_color_override("font_color",UIStyle.TEXT)
			button.add_theme_stylebox_override("normal",panel_style(Color(UIStyle.BACKGROUND,0.96),UIStyle.BORDER,12))
			button.add_theme_stylebox_override("hover",panel_style(UIStyle.HOVER,UIStyle.GOLD,12))
			button.add_theme_stylebox_override("focus",panel_style(Color(0,0,0,0),UIStyle.GOLD,12))
			button.pressed.connect(func():choose(choice.id))
			answers.add_child(button)
			buttons.append(button)
			actions[choice.id]=button
			if choice.id=="self":
				actions["talk"]=button
			if choice.id=="trade":
				trade_button=button
	_layout()
	for i in range(buttons.size()):
		var reason: String=session.reason_for(session.choices[i].id)
		buttons[i].disabled=not reason.is_empty()
		buttons[i].tooltip_text=reason
	if visible and not initial_focus and actions.has("self") and not actions.self.disabled:
		actions.self.grab_focus()
		initial_focus=true
	if visible and get_viewport().gui_get_focus_owner()==null:
		for i in range(buttons.size()):
			if not buttons[i].disabled and (session.choices[i].id!="leave" or session.ended):
				buttons[i].grab_focus()
				break

func choose(id: String) -> void:
	var result: Dictionary=session.choose(id)
	if result.get("close",false):
		close_requested.emit()
	elif result.get("trade",false):
		trade_requested.emit(session.npc_id)
	else:
		refresh()

func choose_number(index: int) -> void:
	if index>=0 and index<session.choices.size():
		choose(session.choices[index].id)

func _process(delta: float) -> void:
	if not visible:
		return
	elapsed+=delta
	if elapsed>=0.2:
		elapsed=0
		refresh()
