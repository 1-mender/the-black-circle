extends SceneTree
const State=preload("res://scripts/simulation/world_state.gd")
const Skills=preload("res://scripts/simulation/skill_state.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func run() -> void:
	var skills:=Skills.new()
	check(skills.practice("melee",false)==0 and skills.rank("melee")==0,"Meaningless practice gives no XP")
	var early:float=skills.practice("melee",true)
	skills.experience.melee=4000
	check(skills.practice("melee",true)<early,"Simple challenges give less XP at higher proficiency")
	skills.limits.melee=20
	check(skills.practice("melee",true)==0,"Optional future proficiency limit is respected without racial defaults")
	var state:=State.new()
	var cost:float=state.rpg.mining_cost()
	state.mine("iron_01")
	state.mine("iron_01")
	state.mine("iron_01")
	check(state.rpg.skills.rank("mining")>0 and state.rpg.mining_cost()<cost,"Actual extraction improves mining stamina efficiency")
	var mining:float=state.rpg.skills.experience.mining
	state.mine("iron_01")
	state.mine("unknown")
	check(state.rpg.skills.experience.mining==mining,"Empty or invalid deposit cannot grant XP")
	state.location_id="arena"
	state.player_position=Vector2(744,480)
	state.rpg.fighter.position=state.player_position
	state.rpg.claim_kit(state.economy)
	for enemy in state.combat.enemies.values():
		enemy.cooldown=100.0
	state.combat.enemies.melee_01.position=Vector2(1200,480)
	state.combat.request_attack(state,state.player_position+Vector2.LEFT*100)
	state.combat.advance(state,0.5)
	check(state.rpg.skills.experience.melee==0,"Swinging at empty space gives no weapon XP")
	state.rpg.fighter.cooldown=0
	state.combat.enemies.melee_01.position=Vector2(796,480)
	state.combat.request_attack(state,Vector2(796,480))
	state.combat.advance(state,0.25)
	check(state.rpg.skills.experience.melee>0,"Actual weapon hit grants practice")
	var before:float=state.rpg.stats(state.catalog).attack
	state.rpg.skills.practice("melee",true)
	check(state.rpg.stats(state.catalog).attack>before,"Weapon proficiency affects attack strength")
	state.rpg.fighter.attack_elapsed=-1.0
	state.rpg.fighter.cooldown=0
	state.rpg.fighter.hurt=0
	state.rpg.fighter.stamina=100
	state.rpg.fighter.blocking=true
	state.rpg.fighter.facing=Vector2.RIGHT
	var enemy:Dictionary=state.combat.enemies.melee_01
	enemy.position=state.player_position+Vector2(48,0)
	enemy.cooldown=0
	enemy.hurt=0
	enemy.facing=Vector2.LEFT
	state.combat.begin_attack(enemy,state.combat.enemy_stats(enemy),state.player_position)
	state.combat.advance(state,0.25)
	check(state.rpg.skills.experience.defense>0,"Successful hostile block grants defense practice")
	var defense:float=state.rpg.skills.experience.defense
	state.combat.advance(state,0.1)
	check(state.rpg.skills.experience.defense==defense,"Holding block without another impact grants no free XP")
	for _i in range(20):
		state.combat._practice(state,enemy,"defense")
	check(enemy.defense_practice==8,"Practice budget per enemy is finite and persisted")
	var cap:float=state.rpg.skills.experience.defense
	state.combat._practice(state,enemy,"defense")
	check(state.rpg.skills.experience.defense==cap,"Same enemy cannot be farmed indefinitely")
	state.rpg.fighter.blocking=false
	var restored:=State.new()
	check(restored.apply_save(state.to_save()),"Skill state loads alongside existing save")
	check(restored.rpg.skills.to_save()==state.rpg.skills.to_save() and restored.combat.enemies.melee_01.defense_practice==8,"Practice and anti-farming counters restore")
	var legacy:Dictionary=State.new().to_save()
	legacy.version=4
	legacy.erase("adventure")
	legacy.erase("expedition_combat")
	legacy.rpg.erase("skills")
	for id in State.Adit.fixed_owners():
		legacy.economy.ledger.owners.erase(id)
		legacy.economy.ledger.wallets.erase(id)
	check(State.new().apply_save(legacy),"Real v4 schema without new owners or skill fields migrates")
	print("SKILL TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
