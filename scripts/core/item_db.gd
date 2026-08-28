extends Node

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	LEGENDARY,
	MYTHIC
}

var ITEMS: Dictionary = {
	"poncho_reforzado": {
		"id": "poncho_reforzado",
		"name": "Poncho Reforzado",
		"description": "+10% resistencia a daño",
		"rarity": Rarity.COMMON,
		"stats": {
			"damage_reduction": 0.10
		}
	},
	"mochila_cuero": {
		"id": "mochila_cuero",
		"name": "Mochila de Cuero",
		"description": "+15% cantidad de proyectiles/área",
		"rarity": Rarity.COMMON,
		"stats": {
			"projectile_amount_mult": 0.15,
			"area_mult": 0.15
		}
	},
	"aguardiente_bendito": {
		"id": "aguardiente_bendito",
		"name": "Aguardiente Bendito",
		"description": "+8% velocidad de ataque",
		"rarity": Rarity.COMMON,
		"stats": {
			"attack_speed_mult": 0.08
		}
	},
	"botas_caminante": {
		"id": "botas_caminante",
		"name": "Botas de Caminante",
		"description": "+12% velocidad de movimiento",
		"rarity": Rarity.COMMON,
		"stats": {
			"move_speed_mult": 0.12
		}
	},
	"ojo_mohan_comun": {
		"id": "ojo_mohan_comun",
		"name": "Ojo de Mohán (común)",
		"description": "+1 alcance de recolección de XP",
		"rarity": Rarity.COMMON,
		"stats": {
			"xp_range_bonus": 1.0
		}
	},
	"amuleto_tumbaga": {
		"id": "amuleto_tumbaga",
		"name": "Amuleto de Tumbaga",
		"description": "+10% de suerte (drop rate y crítico)",
		"rarity": Rarity.UNCOMMON,
		"stats": {
			"luck_mult": 0.10
		}
	},
	"reloj_pendulo_roto": {
		"id": "reloj_pendulo_roto",
		"name": "Reloj de Péndulo Roto",
		"description": "-10% cooldown global",
		"rarity": Rarity.UNCOMMON,
		"stats": {
			"cooldown_reduction": 0.10
		}
	},
	"vela_anima": {
		"id": "vela_anima",
		"name": "Vela de Ánima",
		"description": "Regeneración de vida pasiva lenta",
		"rarity": Rarity.UNCOMMON,
		"stats": {
			"hp_regen": 1.0 # regenera 1 HP por segundo (o por tick)
		}
	}
}

func get_item(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	return {}

func get_all_items() -> Array:
	return ITEMS.values()

func get_items_by_rarity(rarity: int) -> Array:
	var result = []
	for item in ITEMS.values():
		if item["rarity"] == rarity:
			result.append(item)
	return result
