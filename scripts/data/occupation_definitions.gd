extends RefCounted
## Test occupations and their existing production inputs/outputs. No canonical lore.

const ROLES := {
	"miner": {"action": "extract", "location": "mine", "source": "deposit", "destination": "workshop",
		"inventory_owner": "npc:", "sites": ["iron_01", "copper_01", "iron_02"], "carry_limit": 4},
	"smith": {"action": "craft", "location": "town", "source": "workshop", "destination": "finished",
		"inventory_owner": "npc:", "escrow_owner": "process:worker:", "shop_template": "test_smith",
		"recipes": ["iron_tool", "copper_trinket", "iron_ingot", "copper_ingot"]},
	"merchant": {"action": "deliver", "location": "town", "source": "finished", "destination": "shop",
		"inventory_owner": "npc:", "shop_template": "test_merchant"},
	"metalworker": {"action": "social_craft", "location": "town", "source": "workshop", "destination": "workshop"},
	"carrier": {"action": "daily_work", "location": "town"},
	"mason": {"action": "daily_work", "location": "town"},
	"guard": {"action": "daily_work", "location": "town"},
	"scribe": {"action": "daily_work", "location": "town"},
	"artisan": {"action": "daily_work", "location": "town"},
}
