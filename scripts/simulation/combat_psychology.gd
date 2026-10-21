extends RefCounted
## Compatible actor contract. Observations must already be filtered by perception.
## Does not select a victim, read world state, or turn civilians into combatants.
static func evaluate(previous: Dictionary, profile: Dictionary, observations: Dictionary, delta: float) -> Dictionary:
	var seen: Array=previous.get("seen_defeats",[]).duplicate()
	var fear: float=float(previous.get("fear",0))
	for id in observations.get("defeated_allies",[]):
		if id not in seen:
			seen.append(id)
			fear+=25
	var wounded: bool=float(observations.get("health_fraction",1))<0.3
	var close: bool=float(observations.get("threat_distance",INF))<280
	fear=clampf(fear+(15.0 if wounded and close else -2.0)*maxf(0,delta),0,100)
	var courage: float=clampf(float(profile.get("courage",50)),0,100)
	var motivation: float=clampf(float(profile.get("motivation",50)),0,100)
	var retreat: bool=fear>courage+motivation*0.25
	var refuse: bool=retreat or bool(previous.get("pursuit_refused",false)) and fear>=15
	return {"fear":fear,"seen_defeats":seen,"retreat":retreat,"pursuit_refused":refuse,
		"reason":"Страх сильнее мотивации: отступить" if retreat else ("Мотивация позволяет продолжить" if fear>0 else "Явной опасности не наблюдает")}
