extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
signal close_requested
var window: PanelContainer
var state: RefCounted
var entries: Dictionary={}
var timer:=0.0
var character_summary: Label
func _ready() -> void:
	layer=4
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(root)
	window=PanelContainer.new()
	root.add_child(window)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.offset_left=-310
	window.offset_right=310
	window.offset_top=-190
	window.offset_bottom=190
	var style:=UIStyle.style()
	style.bg_color=UIStyle.BACKGROUND
	style.border_color=UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	window.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	window.add_child(box)
	var title:=Label.new()
	title.text="Персонаж и навыки"
	title.add_theme_font_size_override("font_size",22)
	title.add_theme_color_override("font_color",UIStyle.GOLD)
	box.add_child(title)
	character_summary=Label.new()
	character_summary.add_theme_font_size_override("font_size",14)
	character_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(character_summary)
	for id in ["melee","defense","mining"]:
		var label:=Label.new()
		label.add_theme_font_size_override("font_size",16)
		box.add_child(label)
		var bar:=ProgressBar.new()
		bar.custom_minimum_size=Vector2(560,14)
		bar.max_value=1
		bar.show_percentage=false
		var fill:=UIStyle.style()
		fill.bg_color=UIStyle.GOLD
		bar.add_theme_stylebox_override("fill",fill)
		box.add_child(bar)
		entries[id]=[label,bar]
	var note:=Label.new()
	note.text="Опыт дают попадания оружием, успешные блоки и добыча.\nУдары по воздуху и пустые жилы не развивают навыки."
	note.add_theme_font_size_override("font_size",14)
	note.add_theme_color_override("font_color",UIStyle.MUTED)
	box.add_child(note)
	var close_button:=Button.new()
	close_button.text="Закрыть · N / Esc"
	close_button.focus_mode=Control.FOCUS_NONE
	close_button.pressed.connect(func():close_requested.emit())
	box.add_child(close_button)
	window.hide()
func open(value:RefCounted) -> void:
	state=value
	window.show()
	refresh()
func close() -> void:
	window.hide()
func refresh() -> void:
	if state==null:
		return
	var stats: Dictionary=state.rpg.stats(state.catalog)
	character_summary.text="%s · Здоровье %.0f / %.0f · Силы %.0f / %.0f\nАтака %.1f · Защита %.1f"%[state.character_name,state.rpg.fighter.hp,stats.max_hp,state.rpg.fighter.stamina,stats.max_stamina,stats.attack,stats.defense]
	var skills=state.rpg.skills
	for id in entries:
		var rank:int=skills.rank(id)
		var effect:String={"melee":"Атака оружием +%.2f" % (rank*0.35),"defense":"Защита +%.2f" % (rank*0.2),"mining":"Добыча: %.2f выносливости за подход" % state.rpg.mining_cost()}[id]
		entries[id][0].text="%s · %d\nПрактика %.1f / %d · %s" % [skills.NAMES[id],rank,float(skills.experience[id]),10*(rank+1)*(rank+1),effect]
		entries[id][1].value=skills.progress(id)
func _process(delta:float) -> void:
	if not window.visible:
		return
	timer+=delta
	if timer>=0.2:
		timer=0
		refresh()
