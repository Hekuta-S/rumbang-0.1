class_name EquipmentDB
extends RefCounted

## Equipo de la mazmorra: casco, pechera, pantalones, dos talismanes y el arma que llevas en la mano.
## Cada pieza es un Dictionary (se guarda tal cual en SaveManager.meta["equipment"]):
##   {uid, slot, base, name, rarity, stats: {clave: valor}, set?, weapon? (solo slot "arma")}
## Las claves de "stats" son las de PlayerStatBlock (ver su cabecera); PlayerEquipment las suma.
## Stats libres: cada pieza sortea sus stats del mismo pool sea de la ranura que sea; la rareza
## (ItemDB.Rarity) decide cuántas trae y lo fuertes que son.

## Tipos de pieza. Los talismanes ocupan cualquiera de las dos ranuras de talismán.
const KINDS := ["casco", "pechera", "pantalones", "talisman", "arma"]
const KIND_NAMES := {"casco": "Casco", "pechera": "Pechera", "pantalones": "Pantalones",
	"talisman": "Talismán", "arma": "Arma"}
const KIND_ICONS := {"casco": "⛑", "pechera": "🛡", "pantalones": "👖", "talisman": "🔮", "arma": "⚔"}

## Bases por tipo: id -> {name, set?}
const BASES := {
	"casco": {
		"sombrero_vueltiao": {"name": "Sombrero Vueltiao", "set": "arriero"},
		"casco_minero": {"name": "Casco de Minero"},
		"capucha_brujo": {"name": "Capucha de Brujo"},
		# "helmet": modelo 3D que se ve en la cabeza (CharacterLookApplier.set_helmet; ajuste en resources/helmet_fit.json)
		"yelmo_conquistador": {"name": "Yelmo de Conquistador", "set": "conquistador", "helmet": "cruzado"},
		"yelmo_astado": {"name": "Yelmo Astado", "helmet": "cornudo"},
		"casco_vikingo": {"name": "Casco Vikingo", "helmet": "vikingo"},
		"casco_nordico": {"name": "Casco Nórdico", "helmet": "nordico"},
		"yelmo_fantasia": {"name": "Yelmo de Fantasía", "helmet": "fantasia"},
		"yelmo_coronado": {"name": "Yelmo Coronado", "helmet": "coronado", "set": "sombra"},
	},
	"pechera": {
		"ruana_paramo": {"name": "Ruana del Páramo", "set": "arriero"},
		"coraza_cuero": {"name": "Coraza de Cuero"},
		"poncho_lana": {"name": "Poncho de Lana"},
		"peto_tumbaga": {"name": "Peto de Tumbaga", "set": "conquistador"},
		# "armor": set del pack embersstorm que se ve en el torso (CharacterLookApplier.set_armor; ajuste en armor_fit.json)
		"coraza_sombra": {"name": "Coraza de Sombra", "armor": "sombra", "set": "sombra"},
		"coraza_fuego": {"name": "Coraza de Fuego", "armor": "fuego", "set": "fuego"},
		"coraza_escarcha": {"name": "Coraza de Escarcha", "armor": "frio", "set": "frio"},
		"coraza_natural": {"name": "Coraza Natural", "armor": "natural", "set": "natural"},
	},
	"pantalones": {
		"calzas_arriero": {"name": "Calzas de Arriero", "set": "arriero"},
		"pantalon_dril": {"name": "Pantalón de Dril"},
		"bombachos_llano": {"name": "Bombachos del Llano"},
		"grebas_hierro": {"name": "Grebas de Hierro", "set": "conquistador"},
		# "armor": igual que en las pecheras, pero las piezas de pierna (muslo, rodilla, espinilla)
		"grebas_sombra": {"name": "Grebas de Sombra", "armor": "sombra", "set": "sombra"},
		"grebas_fuego": {"name": "Grebas de Fuego", "armor": "fuego", "set": "fuego"},
		"grebas_escarcha": {"name": "Grebas de Escarcha", "armor": "frio", "set": "frio"},
		"grebas_naturales": {"name": "Grebas Naturales", "armor": "natural", "set": "natural"},
	},
	"talisman": {
		"amuleto_jaguar": {"name": "Amuleto del Jaguar"},
		"piedra_esmeralda": {"name": "Piedra de Esmeralda"},
		"escapulario": {"name": "Escapulario Viejo"},
		"colmillo_caiman": {"name": "Colmillo de Caimán"},
		"ojo_mohan": {"name": "Ojo del Mohán"},
		# Talismanes de set: cuentan como pieza de su set elemental (junto a la armadura y el arma del mismo elemento)
		"totem_ardiente": {"name": "Tótem Ardiente", "set": "fuego"},
		"colmillo_helado": {"name": "Colmillo Helado", "set": "frio"},
		"semilla_viva": {"name": "Semilla Viva", "set": "natural"},
		"sello_sombra": {"name": "Sello de Sombra", "set": "sombra"},
	},
}

## Sets: bonus extra al llevar 2 y 3 piezas del mismo set.
const SETS := {
	"arriero": {"name": "Arriero", "bonus": {
		2: {"move_speed": 0.10, "energy_regen": 0.15},
		3: {"extra_jumps": 1, "gold": 0.15}}},
	"conquistador": {"name": "Conquistador", "bonus": {
		2: {"armor": 0.08, "max_energy": 15.0},
		3: {"damage": 0.15, "max_hp": 4.0}}},
	# Armadura de Sombra completa (yelmo coronado + coraza + grebas): la única que cae como botín
	"sombra": {"name": "Sombra", "bonus": {
		2: {"damage": 0.08, "max_mana": 15.0},
		3: {"attack_speed": 0.10, "armor": 0.06, "max_hp": 4.0},
		4: {"perk": "set_sombra"},
		5: {"damage": 0.12, "armor": 0.06, "element_power": 0.4}}},
	# Sets elementales (Fase 3): coraza + grebas + talismán del elemento + arma con ese elemento en la mano (4 piezas).
	# El nivel 4 cambia cómo juegas: "perk" = efecto de PERKS, "element_power" = fuerza extra del elemento del arma.
	"fuego": {"name": "Brasa Viva", "bonus": {
		2: {"damage": 0.06}, 3: {"attack_speed": 0.08, "energy_regen": 0.10},
		4: {"perk": "set_fuego", "element_power": 0.4}}},
	"frio": {"name": "Escarcha Eterna", "bonus": {
		2: {"armor": 0.05}, 3: {"max_hp": 4.0, "hp_regen": 0.15},
		4: {"perk": "set_frio", "element_power": 0.4}}},
	"natural": {"name": "Raíz Antigua", "bonus": {
		2: {"hp_regen": 0.15}, 3: {"max_hp": 4.0, "move_speed": 0.06},
		4: {"perk": "set_natural", "element_power": 0.4}}},
}
## Claves de un nivel de set que no son stats de PlayerStatBlock.
const SET_SPECIAL_KEYS := ["perk", "element_power"]

## Botín: solo caen las piezas con modelo 3D en el personaje: los cascos del pack (todos tienen "helmet") y la
## armadura completa más reciente (LOOT_ARMOR_SET: coraza y grebas). Las demás bases (gorros, ponchos, sets viejos del
## pack...) siguen existiendo para no romper partidas guardadas, pero ya no se sortean ni se venden. Talismanes y
## armas no cambian (no tienen modelo propio; las armas son las de WEAPONS).
## Desde la Fase 2 caen las armaduras de los cuatro elementos (solo Sombra forma set con el yelmo coronado).
const LOOT_ARMOR_SET := "sombra"   # el set con bonus de piezas

static func lootable_bases(kind: String) -> Array:
	var out: Array = []
	var bases: Dictionary = BASES.get(kind, {})
	for id in bases:
		var b: Dictionary = bases[id]
		match kind:
			"casco":
				if b.has("helmet"):
					out.append(id)
			"pechera", "pantalones":
				if b.has("armor"):   # Fase 2: caen los 4 elementos (fuego, escarcha, selva, sombra)
					out.append(id)
			_:
				out.append(id)
	return out

## Pool de stats: [mínimo, máximo] en rareza común. "int": valor entero fijo (solo desde rara).
## En la mazmorra no hay tamaño de ataque ni golpes/proyectiles extra (ver PlayerStatBlock.DUNGEON_IGNORED):
## el equipo da recursos (energía y maná) en su lugar.
## Fase 1 del plan de mejora: valores ~1.5x más altos para que una pieza se note.
const STAT_POOL := {
	"damage": [0.08, 0.15],
	"attack_speed": [0.06, 0.12],
	"cooldown_reduction": [0.05, 0.09],
	"armor": [0.04, 0.08],
	"max_hp": [3.0, 6.0],
	"hp_regen": [0.15, 0.30],
	"move_speed": [0.06, 0.12],
	"jump_height": [0.08, 0.16],
	"magnet": [1.5, 3.0],
	"gold": [0.12, 0.22],
	"max_energy": [12.0, 22.0],
	"energy_regen": [0.12, 0.22],
	"energy_cost": [0.05, 0.10],
	"max_mana": [12.0, 22.0],
	"mana_regen": [0.15, 0.30],
	"extra_jumps": "int",
}

## Cada tipo de pieza tiene su estilo: "main" = stats protagonistas (el primero sale SIEMPRE de aquí),
## "extra" = los que pueden acompañarlo. Un casco es de maná y enfriamiento; unos pantalones, de movilidad.
const SLOT_STATS := {
	"casco": {"main": ["cooldown_reduction", "max_mana", "mana_regen"], "extra": ["energy_cost", "damage", "magnet", "armor"]},
	"pechera": {"main": ["max_hp", "armor", "hp_regen"], "extra": ["max_energy", "damage", "energy_regen", "max_hp"]},
	"pantalones": {"main": ["move_speed", "energy_regen", "max_energy"], "extra": ["jump_height", "energy_cost", "armor", "extra_jumps"]},
	"talisman": {"main": ["damage", "attack_speed", "gold", "magnet"], "extra": ["cooldown_reduction", "hp_regen", "extra_jumps", "mana_regen"]},
	"arma": {"main": ["damage", "attack_speed"], "extra": ["cooldown_reduction", "energy_cost", "max_mana"]},
}

## Efectos especiales (a partir de rareza Rara): hacen algo, no solo suman. Campos:
##   trigger: evento que lo dispara -- dodge | kill | finisher | parry | hurt (PlayerEquipment.notify)
##            o condición permanente -- hp_low (<35 % de vida) | hp_full (>=90 %) | always
##   buff {stat: valor} durante dur s · heal (fracción de vida máx.) · energy / mana (puntos) · cd (reposo entre usos)
##   slots: tipos de pieza donde puede salir · unique: solo en piezas legendarias fijas.
## No usar max_hp ni hp_regen en buff (PlayerStatBlock los aplica una sola vez).
const PERKS := {
	"pies_niebla": {"name": "Pies de Niebla", "trigger": "dodge", "buff": {"damage": 0.25}, "dur": 3.0,
		"slots": ["pantalones", "talisman"], "desc": "Tras esquivar: +25% daño 3 s"},
	"zancada": {"name": "Zancada", "trigger": "dodge", "buff": {"move_speed": 0.30}, "dur": 2.5,
		"slots": ["pantalones"], "desc": "Tras esquivar: +30% velocidad 2,5 s"},
	"gallardo": {"name": "Gallardo", "trigger": "dodge", "energy": 12.0, "cd": 1.5,
		"slots": ["pantalones", "talisman"], "desc": "Al esquivar recuperas 12 de energía"},
	"sed_mana": {"name": "Sed de Maná", "trigger": "kill", "mana": 6.0,
		"slots": ["casco", "talisman"], "desc": "Cada baja te da 6 de maná"},
	"racha": {"name": "Racha", "trigger": "kill", "buff": {"attack_speed": 0.20}, "dur": 3.0,
		"slots": ["talisman", "arma"], "desc": "Cada baja: +20% velocidad de ataque 3 s"},
	"sangre_fresca": {"name": "Sangre Fresca", "trigger": "kill", "heal": 0.02, "cd": 0.5,
		"slots": ["pechera", "arma"], "desc": "Cada baja cura un 2% de tu vida"},
	"sangre_acero": {"name": "Sangre y Acero", "trigger": "kill", "energy": 10.0,
		"slots": ["arma"], "desc": "Cada baja te da 10 de energía"},
	"piel_piedra": {"name": "Piel de Piedra", "trigger": "hurt", "buff": {"armor": 0.15}, "dur": 4.0, "cd": 6.0,
		"slots": ["pechera", "casco"], "desc": "Al recibir un golpe: +15% armadura 4 s"},
	"furia_acumulada": {"name": "Furia Acumulada", "trigger": "hurt", "buff": {"attack_speed": 0.30}, "dur": 3.0, "cd": 5.0,
		"slots": ["arma", "talisman"], "desc": "Al recibir un golpe: +30% velocidad de ataque 3 s"},
	"ojo_verdugo": {"name": "Ojo del Verdugo", "trigger": "finisher", "buff": {"damage": 0.35}, "dur": 6.0,
		"slots": ["talisman", "arma", "casco"], "desc": "Tras un remate: +35% daño 6 s"},
	"rematador": {"name": "Rematador", "trigger": "finisher", "heal": 0.10,
		"slots": ["arma", "pechera"], "desc": "Los remates curan un 10% extra"},
	"contragolpe": {"name": "Contragolpe", "trigger": "parry", "buff": {"damage": 0.40}, "dur": 4.0,
		"slots": ["talisman", "arma", "pechera"], "desc": "Tras un parry: +40% daño 4 s"},
	"ultimo_aliento": {"name": "Último Aliento", "trigger": "hp_low", "buff": {"damage": 0.25, "armor": 0.10},
		"slots": ["pechera", "talisman", "casco"], "desc": "Con poca vida (<35%): +25% daño y +10% armadura"},
	"plenitud": {"name": "Plenitud", "trigger": "hp_full", "buff": {"damage": 0.15},
		"slots": ["talisman", "casco", "arma"], "desc": "Con la vida casi llena: +15% daño"},
	# ── De set (nivel 4 de los sets; nova = onda que afecta a los enemigos cercanos) ──
	"set_fuego": {"name": "Brasa Viva", "trigger": "kill", "buff": {"damage": 0.15}, "dur": 3.0, "cd": 0.5,
		"nova": {"element": "fuego", "radius": 4.0, "dps": 6.0}, "unique": true, "slots": [],
		"desc": "Cada baja: onda de fuego que quema a los cercanos y +15% daño 3 s"},
	"set_frio": {"name": "Escarcha Eterna", "trigger": "hurt", "buff": {"armor": 0.20}, "dur": 3.0, "cd": 5.0,
		"nova": {"element": "frio", "radius": 5.0}, "unique": true, "slots": [],
		"desc": "Al recibir un golpe: onda helada que ralentiza a los cercanos y +20% armadura 3 s"},
	"set_natural": {"name": "Raíz Antigua", "trigger": "kill", "heal": 0.03, "cd": 0.5,
		"nova": {"element": "natural", "radius": 4.0, "dps": 4.0}, "unique": true, "slots": [],
		"desc": "Cada baja: nube venenosa a los cercanos y cura un 3%"},
	"set_sombra": {"name": "Sombra Completa", "trigger": "dodge", "buff": {"cooldown_reduction": 0.15, "move_speed": 0.15}, "dur": 3.0,
		"unique": true, "slots": [], "desc": "Tras esquivar: -15% enfriamiento y +15% velocidad 3 s"},
	# ── Únicos (solo en las legendarias fijas) ──
	"rey_caido": {"name": "Voluntad del Rey Caído", "trigger": "kill", "mana": 10.0, "buff": {"cooldown_reduction": 0.15}, "dur": 4.0,
		"unique": true, "slots": ["casco"], "desc": "Cada baja: +10 de maná y -15% enfriamiento 4 s"},
	"muralla_sombra": {"name": "Muralla de Sombra", "trigger": "hurt", "buff": {"armor": 0.25}, "dur": 3.0, "cd": 4.0, "heal": 0.04,
		"unique": true, "slots": ["pechera"], "desc": "Al recibir un golpe: +25% armadura 3 s y cura un 4%"},
	"paso_sombra": {"name": "Paso de Sombra", "trigger": "dodge", "buff": {"move_speed": 0.35, "damage": 0.20}, "dur": 3.0,
		"unique": true, "slots": ["pantalones"], "desc": "Tras esquivar: +35% velocidad y +20% daño 3 s"},
	"mirada_mohan": {"name": "Mirada del Mohán", "trigger": "finisher", "buff": {"damage": 0.40}, "dur": 6.0, "heal": 0.15,
		"unique": true, "slots": ["talisman"], "desc": "Tras un remate: cura un 15% y +40% daño 6 s"},
	"terremoto": {"name": "Terremoto", "trigger": "kill", "energy": 15.0, "buff": {"damage": 0.20}, "dur": 3.0,
		"unique": true, "slots": ["arma"], "desc": "Cada baja: +15 de energía y +20% daño 3 s"},
	"hambre_dagas": {"name": "Hambre de Filo", "trigger": "kill", "heal": 0.03, "buff": {"attack_speed": 0.25}, "dur": 3.0,
		"unique": true, "slots": ["arma"], "desc": "Cada baja: cura un 3% y +25% velocidad de ataque 3 s"},
	"gesta_dragon": {"name": "Gesta del Matadragones", "trigger": "kill", "energy": 12.0, "buff": {"damage": 0.25}, "dur": 4.0,
		"unique": true, "slots": ["arma"], "desc": "Cada baja: +12 de energía y +25% daño 4 s"},
	"sed_obsidiana": {"name": "Sed de Obsidiana", "trigger": "kill", "heal": 0.03, "buff": {"move_speed": 0.25}, "dur": 3.0,
		"unique": true, "slots": ["arma"], "desc": "Cada baja: cura un 3% y +25% velocidad 3 s"},
}
## ── Fase 2: elementos y modificadores de arma (solo mazmorra) ──
## Elemento de un ARMA (item["element"]): cada golpe puede aplicar su efecto (ElementalHits). Las armaduras
## del pack tienen el mismo elemento (EquipmentDB.armor_of): con 1-2 piezas del mismo elemento que el arma,
## el efecto es más fuerte ("resonancia"); con 2 piezas y un arma sin elemento, la armadura lo presta a media fuerza.
##   chance: probabilidad por golpe · dps: fracción del daño del golpe que hace por segundo · dur: segundos
const ELEMENTS := {
	"fuego": {"name": "Fuego", "label": "de Fuego", "color": Color(1.0, 0.5, 0.15), "chance": 0.35, "dps": 0.6, "dur": 3.0,
		"desc": "Quema al enemigo (daño con el tiempo)"},
	"frio": {"name": "Escarcha", "label": "de Escarcha", "color": Color(0.5, 0.85, 1.0), "chance": 0.45, "slow": 0.55, "dur": 2.5,
		"desc": "Ralentiza al enemigo un 45%"},
	"natural": {"name": "Selva", "label": "de la Selva", "color": Color(0.45, 1.0, 0.3), "chance": 0.5, "dps": 0.35, "dur": 4.0,
		"desc": "Envenena (se acumula hasta 5 veces)"},
	"sombra": {"name": "Sombra", "label": "de Sombra", "color": Color(0.7, 0.4, 1.0), "chance": 1.0, "drain": 0.06,
		"desc": "Roba un 6% del daño como vida"},
}
## Lo que da cada pieza de armadura de un elemento (por pieza, solo en la mazmorra).
const ARMOR_ELEMENT_STATS := {
	"fuego": {"damage": 0.05}, "frio": {"armor": 0.04}, "natural": {"hp_regen": 0.12}, "sombra": {"cooldown_reduction": 0.03},
}
const ELEMENT_CHANCE := [0.0, 0.25, 0.6, 1.0, 1.0]   ## probabilidad de que un arma salga con elemento por rareza
const RESONANCE_PER_PIECE := 0.25                      ## +25% de fuerza por pieza de armadura del mismo elemento

## Modificadores propios de cada arma (item["wmod"]): se suman a los de Player.get_weapon_modifiers.
## size/damage/lifesteal suman; cooldown multiplica.
const WEAPON_MODS := {
	WeaponData.WeaponType.MACE: {
		"crater": {"name": "Cráter Ancho", "mods": {"size": 0.25}, "desc": "+25% área del mazazo"},
		"pesada": {"name": "Cabeza Pesada", "mods": {"damage": 0.2, "cooldown": 1.1}, "desc": "+20% daño, golpes un 10% más lentos"}},
	WeaponData.WeaponType.GREATSWORD: {
		"tajo": {"name": "Tajo Ancho", "mods": {"size": 0.25}, "desc": "+25% alcance de los tajos"},
		"pesada": {"name": "Hoja Pesada", "mods": {"damage": 0.2, "cooldown": 1.1}, "desc": "+20% daño, golpes un 10% más lentos"}},
	WeaponData.WeaponType.SWORD: {
		"filo": {"name": "Filo Largo", "mods": {"size": 0.2}, "desc": "+20% alcance de los golpes"},
		"templada": {"name": "Hoja Templada", "mods": {"damage": 0.15}, "desc": "+15% daño"}},
	WeaponData.WeaponType.DAGGERS: {
		"filo": {"name": "Filo Veloz", "mods": {"cooldown": 0.85}, "desc": "-15% tiempo entre ataques"},
		"sed": {"name": "Sed de Sangre", "mods": {"lifesteal": 0.04}, "desc": "4% del daño se convierte en vida"}},
	WeaponData.WeaponType.SPEAR_LANCE: {
		"larga": {"name": "Asta Larga", "mods": {"size": 0.25}, "desc": "+25% alcance"},
		"punta": {"name": "Punta Afilada", "mods": {"damage": 0.15}, "desc": "+15% daño"}},
	WeaponData.WeaponType.FLAME_THROWER: {
		"camara": {"name": "Cámara Ancha", "mods": {"size": 0.25}, "desc": "+25% área de la llama"},
		"carburante": {"name": "Carburante", "mods": {"damage": 0.2}, "desc": "+20% daño"}},
	WeaponData.WeaponType.SPORE_BAZOOKA: {
		"carga": {"name": "Carga Doble", "mods": {"size": 0.3}, "desc": "+30% radio de la explosión"},
		"esporas": {"name": "Esporas Densas", "mods": {"damage": 0.15}, "desc": "+15% daño"}},
	WeaponData.WeaponType.TRI_SHOTGUN: {
		"corto": {"name": "Cañón Corto", "mods": {"cooldown": 0.85}, "desc": "-15% tiempo entre disparos"},
		"perdigones": {"name": "Perdigones", "mods": {"damage": 0.15}, "desc": "+15% daño"}},
	WeaponData.WeaponType.DUSTS: {
		"nube": {"name": "Nube Densa", "mods": {"size": 0.25}, "desc": "+25% área de los polvos"},
		"potente": {"name": "Mezcla Potente", "mods": {"damage": 0.2}, "desc": "+20% daño"}},
	WeaponData.WeaponType.SERPENTS: {
		"hambre": {"name": "Espíritus Hambrientos", "mods": {"lifesteal": 0.04}, "desc": "4% del daño se convierte en vida"},
		"furia": {"name": "Espíritus Furiosos", "mods": {"damage": 0.15}, "desc": "+15% daño"}},
}
const WMOD_CHANCE := [0.0, 0.5, 1.0, 1.0, 1.0]

## Probabilidad de traer efecto especial por rareza (Común, Poco común, Rara, Legendaria, Mítica).
const PERK_CHANCE := [0.0, 0.0, 0.6, 1.0, 1.0]

## Legendarias fijas: piezas con nombre, stats y efecto propios (no se sortean). Caen con probabilidad
## LEGENDARY_CHANCE al salir una pieza de su rareza o superior del mismo tipo. "base" da el modelo 3D.
const LEGENDARY_CHANCE := 0.35
const LEGENDARIES := {
	"corona_rey": {"slot": "casco", "base": "yelmo_coronado", "name": "Corona del Rey Caído", "rarity": 4,
		"stats": {"cooldown_reduction": 0.12, "max_mana": 25.0, "damage": 0.10, "mana_regen": 0.20}, "perk": "rey_caido"},
	"coraza_vacio": {"slot": "pechera", "base": "coraza_sombra", "name": "Coraza del Vacío", "rarity": 4,
		"stats": {"max_hp": 10.0, "armor": 0.12, "hp_regen": 0.30, "max_energy": 20.0}, "perk": "muralla_sombra"},
	"grebas_cazador": {"slot": "pantalones", "base": "grebas_sombra", "name": "Grebas del Cazador Nocturno", "rarity": 3,
		"stats": {"move_speed": 0.16, "energy_regen": 0.22, "jump_height": 0.12}, "perk": "paso_sombra"},
	"ojo_ancestral": {"slot": "talisman", "base": "ojo_mohan", "name": "Ojo Ancestral del Mohán", "rarity": 4,
		"stats": {"damage": 0.15, "attack_speed": 0.10, "gold": 0.20, "magnet": 3.0}, "perk": "mirada_mohan"},
	"maza_terremoto": {"slot": "arma", "weapon": WeaponData.WeaponType.MACE, "name": "Maza del Terremoto", "rarity": 3,
		"stats": {"damage": 0.22, "energy_cost": 0.08, "cooldown_reduction": 0.06}, "perk": "terremoto",
		"element": "fuego", "wmod": "crater", "skin": 3},
	"dagas_hambre": {"slot": "arma", "weapon": WeaponData.WeaponType.DAGGERS, "name": "Dagas del Hambre", "rarity": 3,
		"stats": {"attack_speed": 0.16, "damage": 0.12, "move_speed": 0.06}, "perk": "hambre_dagas",
		"element": "sombra", "wmod": "filo", "skin": 3},
	"matadragones": {"slot": "arma", "weapon": WeaponData.WeaponType.GREATSWORD, "name": "Matadragones", "rarity": 3,
		"stats": {"damage": 0.20, "energy_cost": 0.06, "move_speed": 0.08}, "perk": "gesta_dragon",
		"element": "fuego", "wmod": "pesada", "skin": 1},
	"espadon_obsidiana": {"slot": "arma", "weapon": WeaponData.WeaponType.GREATSWORD, "name": "Espadón de Obsidiana", "rarity": 3,
		"stats": {"damage": 0.14, "attack_speed": 0.10, "cooldown_reduction": 0.06}, "perk": "sed_obsidiana",
		"element": "sombra", "wmod": "tajo", "skin": 3},
}
const STAT_NAMES := {
	"damage": "daño", "attack_speed": "vel. de ataque", "cooldown_reduction": "enfriamiento",
	"armor": "armadura", "max_hp": "vida máx.", "hp_regen": "regeneración",
	"move_speed": "velocidad", "jump_height": "salto", "magnet": "imán", "gold": "oro",
	"max_energy": "energía máx.", "energy_regen": "recarga de energía", "energy_cost": "ahorro de energía",
	"max_mana": "maná máx.", "mana_regen": "recarga de maná",
	"extra_jumps": "salto extra",
}
## Stats que se muestran como porcentaje.
const PERCENT_STATS := ["damage", "attack_speed", "cooldown_reduction", "armor", "move_speed",
	"jump_height", "gold", "energy_regen", "energy_cost", "mana_regen"]

## Por rareza: nº de stats y multiplicador de su valor.
const RARITY_AFFIXES := [1, 2, 2, 3, 4]
const RARITY_POWER := [1.0, 1.25, 1.5, 1.85, 2.3]
const RARITY_NAMES := ["Común", "Poco común", "Rara", "Legendaria", "Mítica"]
const RARITY_COLORS := [Color(0.82, 0.82, 0.82), Color(0.4, 1.0, 0.45), Color(0.35, 0.65, 1.0),
	Color(1.0, 0.6, 0.15), Color(1.0, 0.3, 0.85)]

## Armas que pueden aparecer como pieza (las que tienen animaciones de mazmorra).
const WEAPONS := [
	WeaponData.WeaponType.SPEAR_LANCE, WeaponData.WeaponType.FLAME_THROWER,
	WeaponData.WeaponType.SPORE_BAZOOKA, WeaponData.WeaponType.TRI_SHOTGUN,
	WeaponData.WeaponType.DUSTS, WeaponData.WeaponType.SERPENTS,
	WeaponData.WeaponType.DAGGERS, WeaponData.WeaponType.MACE, WeaponData.WeaponType.GREATSWORD,
	WeaponData.WeaponType.SWORD,
]

# ───────────────────────────── Sorteo ─────────────────────────────

## Rareza ponderada (los pesos de ItemDB); `min_rarity` sube el suelo (cofres, jefes).
static func roll_rarity(rng: RandomNumberGenerator = null, min_rarity: int = 0) -> int:
	var weights: Dictionary = ItemDB.RARITY_WEIGHT
	var total := 0.0
	for r in weights:
		if int(r) >= min_rarity:
			total += float(weights[r])
	var roll := _randf(rng) * total
	for r in weights:
		if int(r) < min_rarity:
			continue
		roll -= float(weights[r])
		if roll <= 0.0:
			return int(r)
	return clampi(min_rarity, 0, RARITY_AFFIXES.size() - 1)

## Pieza nueva. kind "" = tipo al azar (las armas salen menos).
static func roll(kind: String = "", rarity: int = -1, rng: RandomNumberGenerator = null, min_rarity: int = 0, allow_legendary: bool = true) -> Dictionary:
	if kind == "":
		kind = "arma" if _randf(rng) < 0.15 else KINDS[_randi(rng) % 4]
	if rarity < 0:
		rarity = roll_rarity(rng, min_rarity)
	rarity = clampi(rarity, 0, RARITY_AFFIXES.size() - 1)
	var legend := _maybe_legendary(kind, rarity, rng) if allow_legendary else ""
	if legend != "":
		return legendary_item(legend)
	var item := {"uid": "%d_%d" % [Time.get_ticks_usec(), _randi(rng) % 100000], "slot": kind, "rarity": rarity}
	if kind == "arma":
		var w: int = WEAPONS[_randi(rng) % WEAPONS.size()]
		item["weapon"] = w
		item["base"] = "arma_%d" % w
		item["name"] = String(WeaponData.weapon_names.get(w, "Arma"))
		_roll_weapon_traits(item, rarity, rng)
	else:
		var bases: Dictionary = BASES[kind]
		var ids: Array = lootable_bases(kind)
		var base_id: String = ids[_randi(rng) % ids.size()]
		item["base"] = base_id
		item["name"] = String(bases[base_id]["name"])
		if bases[base_id].has("set"):
			item["set"] = String(bases[base_id]["set"])
	item["stats"] = roll_stats(rarity, rng, kind)
	var perk := roll_perk(kind, rarity, rng)
	if perk != "":
		item["perk"] = perk
	return item

## Elemento y modificador propio de un arma, según su rareza. Cambia el nombre ("Maza Rúnica de Fuego").
## Usa item["weapon"], así que se vuelve a llamar si cambia el arma.
static func _roll_weapon_traits(item: Dictionary, rarity: int, rng: RandomNumberGenerator) -> void:
	for k in ["element", "wmod", "set"]:
		item.erase(k)
	item["name"] = String(WeaponData.weapon_names.get(int(item["weapon"]), "Arma"))
	if int(item["weapon"]) == WeaponData.WeaponType.GREATSWORD:
		# Cada espadón sale con uno de los cuatro modelos (GreatswordModels), que le da el nombre
		item["skin"] = _randi(rng) % GreatswordModels.count()
		item["name"] = GreatswordModels.skin_name(int(item["skin"]))
	elif int(item["weapon"]) == WeaponData.WeaponType.SWORD:
		item["skin"] = _randi(rng) % SwordModels.count()
		item["name"] = SwordModels.skin_name(int(item["skin"]))
	elif int(item["weapon"]) == WeaponData.WeaponType.DAGGERS:
		item["skin"] = _randi(rng) % DaggerModels.count()
		item["name"] = DaggerModels.skin_name(int(item["skin"]))
	elif int(item["weapon"]) == WeaponData.WeaponType.MACE:
		item["skin"] = _randi(rng) % MaceModels.count()
		item["name"] = MaceModels.skin_name(int(item["skin"]))
	if _randf(rng) < ELEMENT_CHANCE[clampi(rarity, 0, ELEMENT_CHANCE.size() - 1)]:
		var ids: Array = ELEMENTS.keys()
		item["element"] = String(ids[_randi(rng) % ids.size()])
		item["name"] = "%s %s" % [item["name"], ELEMENTS[item["element"]]["label"]]
		item["set"] = item["element"]   # el arma con elemento cuenta como pieza del set de ese elemento
	var mods: Dictionary = WEAPON_MODS.get(int(item["weapon"]), {})
	if not mods.is_empty() and _randf(rng) < WMOD_CHANCE[clampi(rarity, 0, WMOD_CHANCE.size() - 1)]:
		var mids: Array = mods.keys()
		item["wmod"] = String(mids[_randi(rng) % mids.size()])

## Elemento de una pieza ("" si no tiene). Armas: el suyo; pechera/pantalones: el de su set del pack.
static func element_of(item: Dictionary) -> String:
	if String(item.get("slot", "")) == "arma":
		var e := String(item.get("element", ""))
		return e if ELEMENTS.has(e) else ""
	return armor_of(item)

## Definición del modificador propio de un arma ({} si no tiene).
static func wmod_of(item: Dictionary) -> Dictionary:
	if String(item.get("slot", "")) != "arma":
		return {}
	return WEAPON_MODS.get(int(item.get("weapon", -1)), {}).get(String(item.get("wmod", "")), {})

## Efecto especial al azar para una pieza de ese tipo y rareza ("" = sin efecto).
static func roll_perk(kind: String, rarity: int, rng: RandomNumberGenerator = null) -> String:
	if _randf(rng) >= PERK_CHANCE[clampi(rarity, 0, PERK_CHANCE.size() - 1)]:
		return ""
	var ids: Array = []
	for id in PERKS:
		var p: Dictionary = PERKS[id]
		if not p.get("unique", false) and (p["slots"] as Array).has(kind):
			ids.append(id)
	return "" if ids.is_empty() else String(ids[_randi(rng) % ids.size()])

## Id de la legendaria que sustituye a este sorteo ("" = pieza normal).
static func _maybe_legendary(kind: String, rarity: int, rng: RandomNumberGenerator) -> String:
	if rarity < ItemDB.Rarity.LEGENDARY or _randf(rng) >= LEGENDARY_CHANCE:
		return ""
	var ids: Array = []
	for id in LEGENDARIES:
		var l: Dictionary = LEGENDARIES[id]
		if l["slot"] == kind and int(l["rarity"]) <= rarity:
			ids.append(id)
	return "" if ids.is_empty() else String(ids[_randi(rng) % ids.size()])

## Pieza fija de LEGENDARIES (siempre con los mismos stats y efecto).
static func legendary_item(id: String) -> Dictionary:
	var l: Dictionary = LEGENDARIES[id]
	var item := {"uid": "%d_%d" % [Time.get_ticks_usec(), randi() % 100000], "slot": l["slot"],
		"rarity": int(l["rarity"]), "name": String(l["name"]), "legendary": id,
		"stats": (l["stats"] as Dictionary).duplicate(), "perk": String(l["perk"])}
	if l["slot"] == "arma":
		item["weapon"] = int(l["weapon"])
		item["base"] = "arma_%d" % int(l["weapon"])
		for k in ["element", "wmod"]:
			if l.has(k):
				item[k] = String(l[k])
		if l.has("skin"):
			item["skin"] = int(l["skin"])
		if item.has("element"):
			item["set"] = item["element"]
	else:
		item["base"] = String(l["base"])
		var b: Variant = BASES.get(l["slot"], {}).get(l["base"])
		if b is Dictionary and b.has("set"):
			item["set"] = String(b["set"])
	return item

## Pieza de arma concreta (la que eliges en un portal o tienes de partida): sin stats si es común.
static func weapon_item(w: int, rarity: int = 0, rng: RandomNumberGenerator = null) -> Dictionary:
	var item := roll("arma", rarity, rng, 0, false)
	item["weapon"] = w
	var perk := String(item.get("perk", ""))
	if perk != "" and not (PERKS[perk]["slots"] as Array).has("arma"):
		item.erase("perk")
	item["base"] = "arma_%d" % w
	_roll_weapon_traits(item, rarity, rng)
	if rarity == 0:
		item["stats"] = {}
	return item

## `kind` ("casco", "pechera"... ver SLOT_STATS): el primer stat sale de los protagonistas del tipo y el
## resto de sus stats posibles. Con kind "" o desconocido, todo el pool.
static func roll_stats(rarity: int, rng: RandomNumberGenerator = null, kind: String = "") -> Dictionary:
	var allowed := func(k): return not (STAT_POOL[k] is String) or rarity >= ItemDB.Rarity.RARE
	var pool: Array = STAT_POOL.keys().filter(allowed)
	var main: Array = []
	if SLOT_STATS.has(kind):
		main = (SLOT_STATS[kind]["main"] as Array).filter(allowed)
		var extra: Array = (SLOT_STATS[kind]["extra"] as Array).filter(allowed)
		pool = main.duplicate()
		for k in extra:
			if not pool.has(k):
				pool.append(k)
	var power: float = RARITY_POWER[rarity]
	var out := {}
	for i in RARITY_AFFIXES[rarity]:
		if pool.is_empty():
			break
		var src: Array = main if i == 0 and not main.is_empty() else pool
		var key: String = src[_randi(rng) % src.size()]
		pool.erase(key)
		main.erase(key)
		var range_v = STAT_POOL[key]
		if range_v is String:
			out[key] = 1
		else:
			var v: float = lerpf(float(range_v[0]), float(range_v[1]), _randf(rng)) * power
			var step := 0.01 if key in PERCENT_STATS or key == "hp_regen" else (1.0 if key in ["max_energy", "max_mana"] else 0.5)
			out[key] = snappedf(v, step)
	return out

# ───────────────────────────── Datos / texto ─────────────────────────────

## Ranura(s) donde puede ir una pieza.
static func slots_for(item: Dictionary) -> Array:
	match String(item.get("slot", "")):
		"talisman":
			return ["talisman_1", "talisman_2"]
		"":
			return []
		var s:
			return [s]

static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)]

static func rarity_name(item: Dictionary) -> String:
	return RARITY_NAMES[clampi(int(item.get("rarity", 0)), 0, RARITY_NAMES.size() - 1)]

static func format_stat(key: String, value: float) -> String:
	var name := String(STAT_NAMES.get(key, key))
	if key in PERCENT_STATS:
		return "%+d%% %s" % [int(round(value * 100.0)), name]
	if STAT_POOL.get(key) is String:
		return "+%d %s" % [int(value), name]
	if key == "max_energy" or key == "max_mana":
		return "%+d %s" % [int(round(value)), name]
	if key == "magnet":
		return "%+.1f m %s" % [value, name]
	if key == "hp_regen":
		return "%+.2f/s %s" % [value, name]
	return "%+.1f %s" % [value, name]

static func describe_stats(stats: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for k in stats:
		lines.append(format_stat(String(k), float(stats[k])))
	return lines

## Texto de una pieza: "Sombrero Vueltiao (Rara) · +8% daño, +2.5 vida máx. · Set Arriero"
static func describe(item: Dictionary) -> String:
	if item.is_empty():
		return "—"
	var parts: Array = ["%s (%s)" % [item.get("name", "?"), rarity_name(item)]]
	var st := describe_stats(item.get("stats", {}))
	if not st.is_empty():
		parts.append(", ".join(st))
	if element_text(item) != "":
		parts.append(element_text(item))
	if not wmod_of(item).is_empty():
		parts.append("✦ " + String(wmod_of(item)["name"]) + ": " + String(wmod_of(item)["desc"]))
	if perk_of(item).size() > 0:
		parts.append("★ " + perk_text(item))
	if item.has("set") and SETS.has(item["set"]):
		parts.append("Set " + String(SETS[item["set"]]["name"]))
	return " · ".join(parts)

## "Elemento Fuego: Quema al enemigo..." ("" si no tiene). En armaduras explica la resonancia.
static func element_text(item: Dictionary) -> String:
	var e := element_of(item)
	if e == "":
		return ""
	var el: Dictionary = ELEMENTS[e]
	if String(item.get("slot", "")) == "arma":
		return "Elemento %s: %s" % [el["name"], el["desc"]]
	return "Armadura de %s: refuerza las armas de %s" % [el["name"], el["name"]]

## Líneas extra de una pieza para la UI (elemento, modificador de arma, efecto especial), en este orden.
static func trait_lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if element_text(item) != "":
		out.append(element_text(item))
	var w := wmod_of(item)
	if not w.is_empty():
		out.append("✦ %s: %s" % [w["name"], w["desc"]])
	if perk_text(item) != "":
		out.append("★ " + perk_text(item))
	return out

## Definición del efecto especial de una pieza ({} si no tiene).
static func perk_of(item: Dictionary) -> Dictionary:
	var id := String(item.get("perk", ""))
	return PERKS.get(id, {})

## "Pies de Niebla: Tras esquivar: +25% daño 3 s" ("" si no tiene efecto).
static func perk_text(item: Dictionary) -> String:
	var p := perk_of(item)
	return "" if p.is_empty() else "%s: %s" % [p["name"], p["desc"]]

## Modelo 3D de casco de una pieza ("" si no es un casco o su base no tiene modelo).
static func helmet_of(item: Dictionary) -> String:
	if String(item.get("slot", "")) != "casco":
		return ""
	var base: Variant = BASES["casco"].get(String(item.get("base", "")))
	return String(base.get("helmet", "")) if base is Dictionary else ""

## Set del pack de armaduras de una pechera o de unos pantalones ("" si es otra ranura o su base no tiene modelo).
static func armor_of(item: Dictionary) -> String:
	var slot := String(item.get("slot", ""))
	if slot != "pechera" and slot != "pantalones":
		return ""
	var base: Variant = BASES[slot].get(String(item.get("base", "")))
	return String(base.get("armor", "")) if base is Dictionary else ""

## Una pieza leída de JSON (los números vuelven como float) o rota: null si no vale.
static func sanitize(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = (v as Dictionary).duplicate(true)
	var kind := String(d.get("slot", ""))
	if not KINDS.has(kind):
		return {}
	d["rarity"] = clampi(int(d.get("rarity", 0)), 0, RARITY_AFFIXES.size() - 1)
	if kind == "arma":
		if not d.has("weapon"):
			return {}
		d["weapon"] = int(d["weapon"])
	var stats := {}
	if d.get("stats") is Dictionary:
		for k in d["stats"]:
			if STAT_POOL.has(String(k)):
				var val := float(d["stats"][k])
				stats[String(k)] = int(val) if STAT_POOL[String(k)] is String else val
	d["stats"] = stats
	if d.has("perk") and not PERKS.has(String(d["perk"])):
		d.erase("perk")
	if d.has("legendary") and not LEGENDARIES.has(String(d["legendary"])):
		d.erase("legendary")
	if d.has("element") and (kind != "arma" or not ELEMENTS.has(String(d["element"]))):
		d.erase("element")
	if kind == "arma" and d.has("element"):
		d["set"] = d["element"]   # partidas guardadas antes de la Fase 3
	if d.has("wmod") and wmod_of(d).is_empty():
		d.erase("wmod")
	d["name"] = String(d.get("name", "Pieza"))
	return d

static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng else randf()

static func _randi(rng: RandomNumberGenerator) -> int:
	return int(rng.randi() if rng else randi())
