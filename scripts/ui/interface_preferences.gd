extends RefCounted
## Local presentation settings, deliberately outside game saves and simulation.
var show_interaction:=true
var master_volume:=1.0
var fullscreen:=false
var path:="user://interface.cfg"
func load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load(path)==OK:
		var value: Variant=config.get_value("interface","show_interaction",true)
		if value is bool:
			show_interaction=value
		value=config.get_value("audio","master_volume",1.0)
		if value is float or value is int:
			master_volume=clampf(float(value),0.0,1.0)
		value=config.get_value("display","fullscreen",false)
		if value is bool:
			fullscreen=value
func set_interaction(value: bool) -> Error:
	show_interaction=value
	return _save()
func set_volume(value: float) -> Error:
	master_volume=clampf(value,0.0,1.0)
	return _save()
func set_fullscreen(value: bool) -> Error:
	fullscreen=value
	return _save()
func _save() -> Error:
	var config:=ConfigFile.new()
	config.load(path)
	config.set_value("interface","show_interaction",show_interaction)
	config.set_value("audio","master_volume",master_volume)
	config.set_value("display","fullscreen",fullscreen)
	return config.save(path)
