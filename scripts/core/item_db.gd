extends Node

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	LEGENDARY,
	MYTHIC
}

## Probabilidad relativa de que un objeto de cada rareza aparezca en la elección.
const RARITY_WEIGHT := {
	Rarity.COMMON: 60.0,
	Rarity.UNCOMMON: 28.0,
	Rarity.RARE: 10.0,
	Rarity.LEGENDARY: 2.5,
	Rarity.MYTHIC: 0.5,
}

## Las claves de "stats" las interpreta PlayerStatBlock (ver su cabecera).
## "max_stacks": veces que se puede recoger (por defecto 5). "disabled": fuera del pool.
var ITEMS: Dictionary = {
	# ── Movilidad ─────────────────────────────────────────────
	"botas_caminante": {
		"id": "botas_caminante", "name": "Botas de Caminante",
		"description": "+12% velocidad de movimiento",
		"rarity": Rarity.COMMON, "stats": {"move_speed": 0.12}, "max_stacks": 6
	},
	"pluma_condor": {
		"id": "pluma_condor", "name": "Pluma de Cóndor",
		"description": "+20% altura de salto",
		"rarity": Rarity.COMMON, "stats": {"jump_height": 0.20}, "max_stacks": 4
	},
	"alas_colibri": {
		"id": "alas_colibri", "name": "Alas de Colibrí",
		"description": "+1 salto en el aire",
		"rarity": Rarity.RARE, "stats": {"extra_jumps": 1}, "max_stacks": 3
	},
	# ── Ataque ────────────────────────────────────────────────
	"aguardiente_bendito": {
		"id": "aguardiente_bendito", "name": "Aguardiente Bendito",
		"description": "+8% velocidad de ataque",
		"rarity": Rarity.COMMON, "stats": {"attack_speed": 0.08}, "max_stacks": 6
	},
	"reloj_pendulo_roto": {
		"id": "reloj_pendulo_roto", "name": "Reloj de Péndulo Roto",
		"description": "-10% cooldown de ataques",
		"rarity": Rarity.UNCOMMON, "stats": {"cooldown_reduction": 0.10}, "max_stacks": 4
	},
	"carcaj_encantado": {
		"id": "carcaj_encantado", "name": "Carcaj Encantado",
		"description": "+1 proyectil en armas a distancia",
		"rarity": Rarity.RARE, "stats": {"extra_projectiles": 1}, "max_stacks": 5
	},
	"doble_filo": {
		"id": "doble_filo", "name": "Doble Filo",
		"description": "+1 golpe extra en armas cuerpo a cuerpo",
		"rarity": Rarity.RARE, "stats": {"melee_hits": 1}, "max_stacks": 3
	},
	"mango_hierro": {
		"id": "mango_hierro", "name": "Mango de Hierro",
		"description": "+20% tamaño de ataques cuerpo a cuerpo",
		"rarity": Rarity.UNCOMMON, "stats": {"melee_size": 0.20}, "max_stacks": 5
	},
	"polvora_gruesa": {
		"id": "polvora_gruesa", "name": "Pólvora Gruesa",
		"description": "+20% tamaño de proyectiles",
		"rarity": Rarity.UNCOMMON, "stats": {"ranged_size": 0.20}, "max_stacks": 5
	},
	"mochila_cuero": {
		"id": "mochila_cuero", "name": "Mochila de Cuero",
		"description": "+12% tamaño de ataques (cuerpo a cuerpo y proyectiles)",
		"rarity": Rarity.COMMON, "stats": {"melee_size": 0.12, "ranged_size": 0.12}, "max_stacks": 5
	},
	"colmillo_jaguar": {
		"id": "colmillo_jaguar", "name": "Colmillo de Jaguar",
		"description": "+12% daño",
		"rarity": Rarity.COMMON, "stats": {"damage": 0.12}, "max_stacks": 8
	},
	# ── Supervivencia ─────────────────────────────────────────
	"poncho_reforzado": {
		"id": "poncho_reforzado", "name": "Poncho Reforzado",
		"description": "+8% armadura (reduce el daño recibido)",
		"rarity": Rarity.COMMON, "stats": {"armor": 0.08}, "max_stacks": 8
	},
	"corazon_ceiba": {
		"id": "corazon_ceiba", "name": "Corazón de Ceiba",
		"description": "+3 vida máxima y cura esa cantidad",
		"rarity": Rarity.COMMON, "stats": {"max_hp": 3.0}, "max_stacks": 8
	},
	"vela_anima": {
		"id": "vela_anima", "name": "Vela de Ánima",
		"description": "Regenera +0.25 de vida por segundo",
		"rarity": Rarity.UNCOMMON, "stats": {"hp_regen": 0.25}, "max_stacks": 6
	},
	# ── Utilidad / economía ───────────────────────────────────
	"ojo_mohan_comun": {
		"id": "ojo_mohan_comun", "name": "Ojo de Mohán",
		"description": "+2.5 m de radio de atracción de XP",
		"rarity": Rarity.COMMON, "stats": {"magnet": 2.5}, "max_stacks": 6
	},
	"duende_travieso": {
		"id": "duende_travieso", "name": "Duende Travieso",
		"description": "+25% oro obtenido",
		"rarity": Rarity.UNCOMMON, "stats": {"gold": 0.25}, "max_stacks": 4
	},
	# ── Riesgo / recompensa ───────────────────────────────────
	"mascara_tryhard": {
		"id": "mascara_tryhard", "name": "Máscara Tryhard!!",
		"description": "+25% velocidad, +40% daño y +20% armadura... pero 50% más enemigos y aparecen más rápido",
		"rarity": Rarity.LEGENDARY, "stats": {"tryhard": 1}, "max_stacks": 1
	},
	# ── Sin efecto implementado todavía (suerte/críticos no existen) ──
	"amuleto_tumbaga": {
		"id": "amuleto_tumbaga", "name": "Amuleto de Tumbaga",
		"description": "+10% de suerte (drop rate y crítico)",
		"rarity": Rarity.UNCOMMON, "stats": {"luck_mult": 0.10}, "disabled": true
	},
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

func get_max_stacks(id: String) -> int:
	return int(get_item(id).get("max_stacks", 5))

## Objetos que todavía se pueden ofrecer: activos y sin llegar al máximo de copias.
func get_available_items(inventory: InventoryComponent = null) -> Array:
	var result: Array = []
	for item in ITEMS.values():
		if item.get("disabled", false):
			continue
		if inventory and inventory.count_item(item["id"]) >= get_max_stacks(item["id"]):
			continue
		result.append(item)
	return result

## Sortea `count` objetos distintos ponderados por rareza.
func roll_choices(inventory: InventoryComponent, count: int = 2) -> Array:
	var pool := get_available_items(inventory)
	var picks: Array = []
	while picks.size() < count and not pool.is_empty():
		var total := 0.0
		for it in pool:
			total += float(RARITY_WEIGHT.get(it["rarity"], 1.0))
		var roll := randf() * total
		var chosen: Dictionary = pool[pool.size() - 1]
		for it in pool:
			roll -= float(RARITY_WEIGHT.get(it["rarity"], 1.0))
			if roll <= 0.0:
				chosen = it
				break
		picks.append(chosen)
		pool.erase(chosen)
	return picks
