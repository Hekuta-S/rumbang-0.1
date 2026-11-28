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
	# ── Pasivas únicas (ItemEffects: se disparan con eventos, no suman stats) ──
	"totuma_chicha": {
		"id": "totuma_chicha", "name": "Totuma de Chicha", "kind": "passive",
		"description": "Al subir de nivel cura un 25% de la vida y te hace invulnerable 2 s",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"sangre_mohan": {
		"id": "sangre_mohan", "name": "Sangre de Mohán", "kind": "passive",
		"description": "Robo de vida: cada golpe te cura un 2% del daño hecho",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 3
	},
	"ruana_llorona": {
		"id": "ruana_llorona", "name": "Ruana de la Llorona", "kind": "passive",
		"description": "Al recibir daño lanza un grito que aturde y empuja a los cercanos (cada 8 s)",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 1
	},
	"mecha_tejo": {
		"id": "mecha_tejo", "name": "Mecha de Tejo", "kind": "passive",
		"description": "Cada 8 golpes el siguiente estalla y daña alrededor del enemigo",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 3
	},
	"sombrero_vueltiao": {
		"id": "sombrero_vueltiao", "name": "Sombrero Vueltiao", "kind": "passive",
		"description": "Cada 15 bajas suelta un remolino que daña y aparta a los cercanos",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 1
	},
	"collar_madremonte": {
		"id": "collar_madremonte", "name": "Collar de la Madremonte", "kind": "passive",
		"description": "Los enemigos que caen pueden dejar una enredadera que ralentiza",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"ojo_candileja": {
		"id": "ojo_candileja", "name": "Ojo de Candileja", "kind": "passive",
		"description": "Aura de fuego: quema a los enemigos pegados a ti",
		"rarity": Rarity.LEGENDARY, "stats": {}, "max_stacks": 1
	},
	"hamaca_abuelo": {
		"id": "hamaca_abuelo", "name": "Hamaca del Abuelo", "kind": "passive",
		"description": "Quieto 1,5 s: curas 1,5 de vida por segundo y +20% de armadura",
		"rarity": Rarity.COMMON, "stats": {}, "max_stacks": 1
	},
	"pacto_patasola": {
		"id": "pacto_patasola", "name": "Pacto de la Patasola", "kind": "passive",
		"description": "Revives una vez con la mitad de la vida; luego el pacto se rompe",
		"rarity": Rarity.LEGENDARY, "stats": {}, "max_stacks": 1
	},
	"moneda_duende": {
		"id": "moneda_duende", "name": "Moneda del Duende", "kind": "passive",
		"description": "Las gemas de XP tienen un 15% de valer el doble (más con suerte)",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 2
	},
	# ── Activas (un solo hueco, tecla E / botón de habilidad; ItemEffects) ──
	"trompo_guerra": {
		"id": "trompo_guerra", "name": "Trompo de Guerra", "kind": "active", "cooldown": 18.0,
		"description": "ACTIVA (E): un trompo gira a tu alrededor 5 s dañando a lo que toca",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 1
	},
	"machete_relampago": {
		"id": "machete_relampago", "name": "Machete Relámpago", "kind": "active", "cooldown": 8.0,
		"description": "ACTIVA (E): embestida de 8 m que corta a todo lo que cruzas",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"garrafon_aguardiente": {
		"id": "garrafon_aguardiente", "name": "Garrafón de Aguardiente", "kind": "active", "cooldown": 30.0,
		"description": "ACTIVA (E): furia 6 s, +50% velocidad de ataque pero -15% armadura",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"campana_iglesia": {
		"id": "campana_iglesia", "name": "Campana de la Iglesia", "kind": "active", "cooldown": 25.0,
		"description": "ACTIVA (E): una campanada congela 2 s a los enemigos cercanos",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 1
	},
	"totumo_polvora": {
		"id": "totumo_polvora", "name": "Totumo de Pólvora", "kind": "active", "cooldown": 10.0,
		"description": "ACTIVA (E): lanza una bomba a donde apuntas",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"silbido_mohan": {
		"id": "silbido_mohan", "name": "Silbido del Mohán", "kind": "active", "cooldown": 45.0,
		"description": "ACTIVA (E): todas las gemas del mapa vuelan hacia ti",
		"rarity": Rarity.UNCOMMON, "stats": {}, "max_stacks": 1
	},
	"tamal_emergencia": {
		"id": "tamal_emergencia", "name": "Tamal de Emergencia", "kind": "active", "cooldown": 60.0,
		"description": "ACTIVA (E): cura un 40% de la vida",
		"rarity": Rarity.RARE, "stats": {}, "max_stacks": 1
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

## "stat" (por defecto), "passive" (efecto único) o "active" (hueco de la tecla E).
func kind_of(id: String) -> String:
	return String(get_item(id).get("kind", "stat"))

func is_active(id: String) -> bool:
	return kind_of(id) == "active"

func get_max_stacks(id: String) -> int:
	return int(get_item(id).get("max_stacks", 5))

## Objetos que todavía se pueden ofrecer: activos y sin llegar al máximo de copias.
func get_available_items(inventory: InventoryComponent = null) -> Array:
	var result: Array = []
	for item in ITEMS.values():
		if item.get("disabled", false):
			continue
		if item.has("kind") and GameData.game_mode == "dungeon":
			continue   # pasivas y activas: solo supervivencia por ahora
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
