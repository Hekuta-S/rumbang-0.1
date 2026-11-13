class_name WorldDefs
extends RefCounted

## Mundos de la mazmorra: cada uno define su aspecto y su población (ver DungeonMap y DungeonEncounter).
##  name / subtitle: lo que se ve en el menú y en el cartel de nivel
##  level_themes: paletas por nivel (en ciclo): suelo, musgo, roca, color del fuego y extras
##    (crystals = nº de brillos por caverna, crystal = su color, bones = montones de huesos)
##  scene: escena de la partida (su mapa y su ambiente)
##  room_themes: decoración de las salas normales (ver DungeonMap / SewerMap._decorate_room)
##  door: estilo de las barreras de los encuentros ("runes" o "bars", ver DungeonDoor)
##  kind_weights: peso de cada tipo de enemigo en los grupos normales
##  guaranteed: tipos que siempre lleva un grupo de 4 o más
##  starter_kind (opcional): en el nivel 1, las primeras cavernas normales solo traen este tipo y sin élites
##    (DungeonEncounter.STARTER_ROOMS): un comienzo suave antes de las recetas mezcladas
##  arena_kind (opcional): tipo de la arena, la caverna vecina de la inicial (por defecto "goblin")
##  boss (opcional): tipo del jefe de los niveles de jefe (por defecto "necro")
##  swarm (opcional): {tipo: [mín, máx]}: cada elección de ese tipo trae varios (ratas)
##  recipes (opcional): RECETAS de encuentro (DungeonEncounter._kinds_for): cada caverna normal elige una, así cada
##    sala plantea un problema distinto (a quién matar primero) en vez de una mezcla al azar.
##    {id, name, min_level, weight, fixed: {tipo: nº}, fill: tipo o {tipo: peso}}: "fixed" va siempre (recortado
##    al tamaño del grupo) y el resto se rellena con "fill". Dentro de un nivel no se repite receta mientras queden.
##  roles (opcional): {tipo: fila}: dónde aparece cada tipo (0 = al fondo, los de distancia; 2 = delante, los tanques)
## El mundo elegido se guarda en GameData.world; en red lo fija el anfitrión (Net._begin).

const DEFAULT := "caves"
const ORDER := ["caves", "sewers"]

const WORLDS := {
	"caves": {
		"name": "Cavernas",
		"scene": "res://scenes/core/main_dungeon.tscn",
		"door": "runes",
		"subtitle": "Cuevas goblin: campamentos, criptas y fraguas.",
		"level_themes": [
			{"name": "Cueva goblin", "dirt": Color(0.3, 0.22, 0.15), "moss": Color(0.2, 0.24, 0.13), "rock": Color(0.21, 0.18, 0.17),
				"fire": Color(1.0, 0.5, 0.18), "crystals": 0, "crystal": Color(0.4, 1.0, 0.6), "bones": 1},
			{"name": "Gruta de cristal", "dirt": Color(0.15, 0.16, 0.23), "moss": Color(0.12, 0.21, 0.27), "rock": Color(0.15, 0.14, 0.24),
				"fire": Color(0.35, 0.75, 1.0), "crystals": 12, "crystal": Color(0.35, 0.9, 1.0), "bones": 1},
			{"name": "Catacumbas", "dirt": Color(0.25, 0.24, 0.23), "moss": Color(0.19, 0.2, 0.19), "rock": Color(0.27, 0.26, 0.26),
				"fire": Color(0.75, 0.45, 1.0), "crystals": 0, "crystal": Color(0.75, 0.45, 1.0), "bones": 4},
			{"name": "Fragua volcánica", "dirt": Color(0.2, 0.12, 0.1), "moss": Color(0.42, 0.13, 0.05), "rock": Color(0.12, 0.1, 0.1),
				"fire": Color(1.0, 0.35, 0.1), "crystals": 8, "crystal": Color(1.0, 0.42, 0.12), "bones": 1},
		],
		"room_themes": ["camp", "camp", "storage", "shrine"],
		"starter_kind": "goblin",
		"kind_weights": {"goblin": 4.0, "zombie": 2.5, "mage": 1.6, "brute": 1.3},
		"guaranteed": ["brute", "mage", "zombie"],
		"roles": {"mage": 0, "goblin": 1, "zombie": 1, "brute": 2},
		"recipes": [
			# Goblins rápidos que rodean y un mago que castiga quedarse quieto
			{"id": "patrulla", "name": "Patrulla", "min_level": 1, "weight": 3.0, "fixed": {"mage": 1}, "fill": "goblin"},
			# El bruto tapa el paso mientras dos magos disparan desde atrás: rodearlo o romperle la guardia
			{"id": "muro", "name": "Muro y artilleria", "min_level": 1, "weight": 2.5, "fixed": {"brute": 1, "mage": 2}, "fill": "goblin"},
			# Marea lenta de zombis (se levantan si no se rematan) cubriendo a un mago
			{"id": "marea", "name": "Marea muerta", "min_level": 1, "weight": 2.0, "fixed": {"mage": 1}, "fill": "zombie"},
			{"id": "mixta", "name": "Campamento", "min_level": 1, "weight": 1.5, "fixed": {}, "fill": {"goblin": 4.0, "zombie": 2.5, "mage": 1.6, "brute": 1.3}},
			# Cripta: un bruto entre zombis, hay que gestionar el suelo lleno de caídos
			{"id": "cripta", "name": "Cripta", "min_level": 2, "weight": 2.0, "fixed": {"brute": 1}, "fill": "zombie"},
			# Dos brutos: espacio cerrado, parry y esquiva constantes
			{"id": "fortaleza", "name": "Fortaleza", "min_level": 2, "weight": 1.5, "fixed": {"brute": 2}, "fill": "goblin"},
			# Aquelarre: muchos magos tras zombis, se gana yendo a por los de atrás
			{"id": "aquelarre", "name": "Aquelarre", "min_level": 3, "weight": 1.5, "fixed": {"mage": 3, "brute": 1}, "fill": "zombie"},
		],
	},
	# Mapa propio (SewerMap): ratas (normales y gordas), babosas (de basura y rojas) y el Rey Rata.
	"sewers": {
		"name": "Cloacas",
		"scene": "res://scenes/core/main_sewers.tscn",
		"door": "bars",
		"subtitle": "Alcantarillas inundadas de basura, ratas y babosas.",
		"level_themes": [
			{"name": "El colector", "dirt": Color(0.2, 0.21, 0.15), "moss": Color(0.22, 0.3, 0.12), "rock": Color(0.24, 0.2, 0.17),
				"fire": Color(0.85, 0.95, 0.45), "crystals": 4, "crystal": Color(0.5, 1.0, 0.3), "bones": 1},
			{"name": "El vertedero", "dirt": Color(0.24, 0.2, 0.14), "moss": Color(0.3, 0.26, 0.12), "rock": Color(0.2, 0.18, 0.15),
				"fire": Color(1.0, 0.7, 0.3), "crystals": 2, "crystal": Color(0.75, 0.95, 0.25), "bones": 3},
			{"name": "Planta química", "dirt": Color(0.13, 0.17, 0.15), "moss": Color(0.16, 0.36, 0.2), "rock": Color(0.16, 0.18, 0.18),
				"fire": Color(0.4, 1.0, 0.55), "crystals": 12, "crystal": Color(0.35, 1.0, 0.45), "bones": 0},
			{"name": "Nido del Rey Rata", "dirt": Color(0.19, 0.14, 0.12), "moss": Color(0.25, 0.22, 0.1), "rock": Color(0.17, 0.13, 0.12),
				"fire": Color(1.0, 0.45, 0.25), "crystals": 4, "crystal": Color(0.6, 1.0, 0.3), "bones": 4},
		],
		"room_themes": ["collector", "dump", "pumps"],
		"kind_weights": {"rat": 5.0, "rat_big": 1.2, "slug": 2.0, "slug_red": 1.3},
		"guaranteed": ["slug"],
		"swarm": {"rat": [2, 3]},
		"roles": {"slug": 0, "rat": 1, "slug_red": 1, "rat_big": 2},
		"recipes": [
			# Nido: enjambre de ratas tras una rata gorda que aguanta
			{"id": "nido", "name": "Nido", "min_level": 1, "weight": 3.0, "fixed": {"rat_big": 1}, "fill": "rat"},
			# Babosario: babosas que escupen desde lejos y rojas que revientan: no pelear encima de ellas
			{"id": "babosario", "name": "Babosario", "min_level": 1, "weight": 2.0, "fixed": {"slug_red": 2}, "fill": "slug"},
			{"id": "mixta", "name": "Vertedero", "min_level": 1, "weight": 1.5, "fixed": {}, "fill": {"rat": 5.0, "rat_big": 1.2, "slug": 2.0, "slug_red": 1.3}},
			# Colonia: dos gordas delante y una babosa al fondo, ratas por los lados
			{"id": "colonia", "name": "Colonia", "min_level": 2, "weight": 2.0, "fixed": {"rat_big": 2, "slug": 1}, "fill": "rat"},
			# Tóxico: muchas rojas entre ratas, cada baja puede ser una explosión
			{"id": "toxico", "name": "Fuga toxica", "min_level": 2, "weight": 1.5, "fixed": {"slug_red": 3}, "fill": "rat"},
		],
		"boss": "rat_king",
		"arena_kind": "slug",
	},
}

static func has(id: String) -> bool:
	return WORLDS.has(id)

## Definición del mundo (la de por defecto si el id no existe).
static func get_def(id: String) -> Dictionary:
	return WORLDS.get(id, WORLDS[DEFAULT])
