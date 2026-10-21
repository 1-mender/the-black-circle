extends RefCounted
## Отдельные навыки практики, без общего уровня/классов. Ограничения — будущая точка расширения.
const NAMES := {"melee":"Владение ближним оружием","defense":"Защита","mining":"Горное дело"}
var experience := {"melee":0.0,"defense":0.0,"mining":0.0}
var limits: Dictionary = {}
func rank(id: String) -> int:
	return mini(int(limits.get(id,100)),floori(sqrt(float(experience.get(id,0))/10.0)))
func practice(id: String, meaningful: bool, difficulty: float = 10.0) -> float:
	if not meaningful or not experience.has(id) or difficulty<=0:
		return 0.0
	if rank(id)>=int(limits.get(id,100)):
		return 0.0
	var before: float=experience[id]
	var gain := 6.0/pow(1.0+float(rank(id))/difficulty,2)
	experience[id]=minf(10.0*pow(int(limits.get(id,100)),2),before+gain)
	return float(experience[id])-before
func progress(id: String) -> float:
	var current:=rank(id)
	return clampf((float(experience[id])-10.0*current*current)/float(10*(2*current+1)),0,1)
func to_save() -> Dictionary:
	return {"experience":experience.duplicate(),"limits":limits.duplicate()}
func load_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("experience") is Dictionary or not data.get("limits") is Dictionary or data.experience.size()!=NAMES.size():
		return false
	for id in NAMES:
		var value=data.experience.get(id)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>100000:
			return false
	for id in data.limits:
		var value=data.limits[id]
		if not NAMES.has(id) or not (value is int or value is float) or value<0 or value>100 or float(value)!=floorf(float(value)):
			return false
	experience=data.experience.duplicate()
	limits=data.limits.duplicate()
	return true
