extends RefCounted
## Приоритетные правила с гистерезисом; расписание — только базовый план.

static func choose(resident: Dictionary, minute: int) -> Dictionary:
	var hour := floori(float(minute % 1440) / 60.0)
	var previous: String = resident["task"]
	if resident["fatigue"] >= 80.0 or (previous == "rest" and resident["fatigue"] > 30.0):
		return {"task": "rest", "reason": "fatigue"}
	if hour >= 22 or hour < 6:
		return {"task": "sleep", "reason": "night"}
	if resident["rest_need"] >= 70.0 or (previous == "rest" and resident["rest_need"] > 20.0):
		return {"task": "rest", "reason": "break"}
	if hour >= 8 and hour < 17:
		return {"task": "work", "reason": "schedule"}
	if hour >= 17 and hour < 20:
		return {"task": "errand", "reason": "evening"}
	return {"task": "rest", "reason": "rest"}
