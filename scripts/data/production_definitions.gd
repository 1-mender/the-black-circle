extends RefCounted
## Тестовые точки и настройки, без нового канонического устройства организаций.

const WORKBENCH := Vector2(720, 864)
const MINE_MINUTES := 20
const CARRY_LIMIT := 4
const DELIVERY_MINUTES := 5
const OWNERS: Array[String] = ["player", "workshop", "finished", "shop:test_smith", "shop:test_merchant",
	"npc:test_npc", "npc:test_smith", "npc:test_miner", "npc:test_merchant", "process:smith", "process:player", "equipment", "consumed"]
const LABELS: Dictionary = {"workshop": "Склад материалов", "finished": "Готовая продукция",
	"shop:test_merchant": "Товары магазина", "npc:test_miner": "У шахтёра", "npc:test_merchant": "В доставке"}
