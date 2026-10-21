extends RefCounted
## Shared UI tokens. World art and HP/stamina colours are independent.
const BACKGROUND=Color("111316")
const PANEL=Color("1b1e22")
const HOVER=Color("292c31")
const BORDER=Color("696454")
const GOLD=Color("b8a476")
const TEXT=Color("dedfe2")
const MUTED=Color("969ba3")
static func style(margin: int=10, background: Color=BACKGROUND, border: Color=BORDER) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=background
	box.border_color=border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.set_content_margin_all(margin)
	return box
static func make_theme() -> Theme:
	var result:=Theme.new()
	result.default_font_size=15
	for type in ["Label","Button","CheckButton","OptionButton","LineEdit","PopupMenu","TabContainer"]:
		result.set_color("font_color",type,TEXT)
		result.set_color("font_hover_color",type,GOLD)
		result.set_color("font_pressed_color",type,GOLD)
		result.set_color("font_disabled_color",type,MUTED)
	result.set_color("default_color","RichTextLabel",TEXT)
	for type in ["Button","OptionButton","LineEdit"]:
		result.set_stylebox("normal",type,style(8,PANEL))
		result.set_stylebox("hover",type,style(8,HOVER,GOLD))
		result.set_stylebox("pressed",type,style(8,HOVER,GOLD))
		result.set_stylebox("disabled",type,style(8,BACKGROUND,Color("35383d")))
		result.set_stylebox("focus",type,style(8,Color.TRANSPARENT,GOLD))
	for type in ["PanelContainer","Panel","PopupMenu","PopupPanel","TooltipPanel"]:
		result.set_stylebox("panel",type,style())
	result.set_stylebox("panel","TabContainer",style())
	result.set_stylebox("tab_selected","TabContainer",style(8,HOVER,GOLD))
	result.set_stylebox("tab_unselected","TabContainer",style(8,PANEL))
	result.set_stylebox("background","ProgressBar",style(0,PANEL,Color.TRANSPARENT))
	return result
