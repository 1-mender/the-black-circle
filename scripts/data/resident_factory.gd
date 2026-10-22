extends RefCounted
## Deterministic initial profiles. Names are labels, never random seeds.

const GOALS := ["craft", "recognition", "help", "peace", "security", "companionship"]

static func make(serial: int, world_seed: int, position: Vector2, profession: String = "metalworker", assignment: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + serial * 104729
	var caution := rng.randi_range(20, 90)
	var sociability := rng.randi_range(15, 90)
	var ambition := rng.randi_range(20, 90)
	var principle := rng.randi_range(25, 95)
	var aggression := clampi(rng.randi_range(10, 80) - (caution - 50) / 4, 0, 100)
	var goal: String = GOALS[rng.randi_range(0, GOALS.size() - 1)]
	var beliefs: Array = ["держать слово"] if principle >= 55 else ["добиваться своего"]
	if sociability >= 65:
		beliefs.append("помогать знакомым")
	var wishes: Array = ["полезный труд", "общение" if sociability >= 50 else "спокойный отдых"]
	var fears: Array = ["ссоры" if caution >= 60 else "неудача"]
	return {
		"definition": {"name": "Житель %d (тест)" % serial, "sprite": rng.randi_range(0, 7),
			"spawn": position, "work": assignment.get("work", position), "home": assignment.get("home", position + Vector2(48, 0)),
			"rest": assignment.get("rest", position + Vector2(0, 48)), "food": assignment.get("food", position + Vector2(0, 48)),
			"errand": assignment.get("errand", position + Vector2(-48, 0)), "profession": profession},
		"profile": {"caution": caution, "sociability": sociability, "ambition": ambition,
			"principle": principle, "aggression": aggression, "goal": goal,
			"beliefs": beliefs, "wishes": wishes, "fears": fears,
			"biography": "Житель тестового района; личность создана при появлении."}
	}
