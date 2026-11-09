## GameData.gd — Autoload Singleton
## Stores character definitions and the player's selection across scenes.
extends Node

var selected_index: int = 0
## Modo de juego: "survival" (oleadas en mapa abierto) o "dungeon" (mazmorra estilo Soul Knight).
var game_mode: String = "survival"
## Mundo de la mazmorra (ver WorldDefs): "caves" o "sewers". Se elige en el menú; en red lo fija el anfitrión.
var world: String = WorldDefs.DEFAULT

## Vida extra de base, igual para todos los personajes (afinar aquí).
const BASE_HP_BONUS := 15.0
## Velocidad de movimiento de todos los personajes en la mazmorra (× la de su ficha). La supervivencia
## usa la de la ficha sin cambios.
const DUNGEON_MOVE_SPEED_MULT := 0.8
## Ritmo más pausado en supervivencia (~38% más lento) para jugador y enemigos.
const SURVIVAL_PLAYER_SPEED_MULT := 0.62
const SURVIVAL_ENEMY_SPEED_MULT := 0.62

var cache_enemy_models: Dictionary = {}
var cache_enemy_textures: Dictionary = {}
var cache_enemy_anims: Dictionary = {}
var cache_bullet_mats: Dictionary = {}
## Recursos cargados en segundo plano (ver AssetPreloader); se mantienen aquí para que Godot no los descarte.
var cache_preloaded: Dictionary = {}

## Animaciones de cada personaje jugable (carpeta assets/models/<personaje>/).
const ANIM_FILES := {
	"joel": { "idle": "joel-idle.fbx", "walk": "joel-caminar.fbx", "run": "joel-corre.fbx", "jump": "joel-salto.fbx" },
	"riva": { "idle": "riva-base.fbx", "walk": "riva-caminar.fbx", "run": "riva-correr.fbx", "jump": "riva-salto.fbx", "fast": "riva-correr-rapido.fbx", "strafe": "riva-caminar-lado.fbx" },
	"bronch": { "idle": "bronch-idle.fbx", "walk": "bronch-caminar.fbx", "run": "bronch-correr.fbx", "jump": "bronch-saltar.fbx" },
	"mikeura": { "idle": "mikeura_idle.fbx", "walk": "mikeura_caminar.fbx", "run": "mikeura-correr.fbx", "jump": "mikeura-saltar.fbx",
		"shout": "mikeura_grito.fbx" },
	"tatan": { "idle": "idle.fbx", "walk": "caminar.fbx", "run": "tatan-correr.fbx" },
	"vangry": { "idle": "vangry-idle.fbx", "walk": "vangry-caminar.fbx", "run": "vangry-correr.fbx", "jump": "Jumping.fbx" },
	"garri": { "idle": "garri-idle.fbx", "walk": "garri-caminar.fbx", "run": "garri-correr.fbx", "jump": "garri-saltar.fbx" },
	"saimon": { "idle": "saimon-idle.fbx", "walk": "saimon-caminar.fbx", "run": "saimon-correr.fbx", "jump": "saimon-saltar.fbx" }
}

## Todos los archivos (modelos de animación + textura) que necesita el personaje en partida.
func get_character_asset_paths(char_id: String) -> Array[String]:
	if not ANIM_FILES.has(char_id):
		char_id = "mikeura"
	var files: Dictionary = ANIM_FILES[char_id]
	var folder := char_id
	var out: Array[String] = []
	for key in files:
		out.append("res://assets/models/%s/%s" % [folder, files[key]])
	out.append(get_texture_path(char_id))
	# Animaciones de su arma inicial (por arma: WeaponAnimSets) y su modelo si es un arma sujeta
	var initial: Array = initial_weapons()
	if not initial.is_empty():
		out.append_array(WeaponAnimSets.asset_paths(int(initial[0])))
	return out

## Modelos y texturas del Nigromante (aparece a los 7:10: se precargan para que no haya tirón).
const BOSS_ASSET_PATHS: Array[String] = [
	"res://assets/models/entities/enemigos/goblins/bosses/necromancer/ataque_idle_necroboss.fbx",
	"res://assets/models/entities/enemigos/goblins/bosses/necromancer/caminar_necro_boss.fbx",
	"res://assets/models/entities/enemigos/goblins/bosses/necromancer/invocar_zombies_necro.fbx",
	"res://assets/models/entities/enemigos/goblins/bosses/necromancer/invocar_erupciones.fbx",
	"res://assets/textures/enemigos/textura_necro_boss.png",
]

## All playable characters defined here.
## Add new characters to this array to make them appear in the selection screen.
const CHARACTERS: Array = [
	{
		"id": "mikeura",
		"name": "Mikeura",
		"subtitle": "Guerrero de la Espalanza",
		"lore": "Portador de una armadura ancestral y de una lanza de tres puntas. Firme en el suelo, nunca da un paso atrás.",
		"color": Color(0.2, 0.55, 1.0),
		"portrait_label": "M",
		"stats": {
			"max_hp": 20.0,
			"move_speed": 7.8,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Mikeura aún no tiene pasiva asignada. Su fuerza está en el combo de la espalanza.",
	},
	{
		"id": "heckler",
		"name": "Heckler",
		"subtitle": "Zombi Teletransportador",
		"lore": "Un no muerto que olvidó cómo correr, pero aprendió a rasgar el espacio-tiempo. Usa su propio brazo desprendible como un bumerán letal.",
		"color": Color(0.4, 0.7, 0.3),
		"portrait_label": "H",
		"stats": {
			"max_hp": 16.0,
			"move_speed": 8.2,
		},
		"passive_name": "Paso del Vacío",
		"passive_color": Color(0.5, 0.8, 0.4),
		"passive_desc": "Su habilidad (tecla E) lo teletransporta instantáneamente 10 metros hacia donde se mueve, atravesando el vacío en lugar de activar el Berserk.",
		"initial_weapons": [WeaponData.WeaponType.ZOMBIE_ARM],
	},
	{
		"id": "vangry",
		"name": "Vangry",
		"subtitle": "Titán Radiactivo",
		"lore": "Forjado en un reactor nuclear derretido, Vangry convirtió la radiación que lo quemó en su mayor arma. Los enemigos que se acercan se pudren en su aura tóxica.",
		"color": Color(0.5, 0.9, 0.25),
		"portrait_label": "V",
		"stats": {
			"max_hp": 18.0,
			"move_speed": 7.5,
		},
		"passive_name": "Zona de Radiación",
		"passive_color": Color(0.45, 1.0, 0.3),
		"passive_desc": "Una pequeña zona radiactiva rodea a Vangry y daña continuamente a todos los enemigos que se encuentren dentro de ella.",
		"initial_weapons": [WeaponData.WeaponType.FLAME_THROWER],
	},
	{
		"id": "bronch",
		"name": "Bronch",
		"subtitle": "Químico de Esporas",
		"lore": "Botánico chiflado obsesionado con hongos mutantes. Su bazuca lanza esporas que explotan en nubes corrosivas, devorando todo lo que tocan.",
		"color": Color(0.78, 0.92, 0.25),
		"portrait_label": "B",
		"stats": {
			"max_hp": 15.0,
			"move_speed": 7.6,
		},
		"passive_name": "Esporas Superpotenciadas",
		"passive_color": Color(0.8, 0.95, 0.3),
		"passive_desc": "Las esporas de Bronch son más potentes: el impacto y las nubes de la bazuca infligen +50% de daño y duran más tiempo.",
		"initial_weapons": [WeaponData.WeaponType.SPORE_BAZOOKA],
	},
	{
		"id": "tatan",
		"name": "Tatan",
		"subtitle": "Duende Alquimista",
		"lore": "Un astuto duende experto en alquimia y polvos mágicos. Su morral nunca se vacía de brebajes explosivos, curativos y estimulantes.",
		"color": Color(0.4, 0.85, 0.5),
		"portrait_label": "T",
		"stats": {
			"max_hp": 12.0,
			"move_speed": 8.8,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Tatan aún no tiene pasiva asignada. Confía plenamente en sus polvos alquímicos de tres modos.",
		"initial_weapons": [WeaponData.WeaponType.DUSTS],
	},
	{
		"id": "joel",
		"name": "Joel",
		"subtitle": "Druida de la Floresta",
		"lore": "Vehemente guardián de un bosque ancestral, Joel canaliza la esencia de la naturaleza en espíritus de animales. Al atacar, invoca al Dragón de Komodo, que azota con la cola y deja a los enemigos sangrando.",
		"color": Color(0.3, 0.85, 0.4),
		"portrait_label": "J",
		"stats": {
			"max_hp": 16.0,
			"move_speed": 8.0,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Joel aún no tiene pasiva asignada. Por ahora confía en sus espíritus animales.",
		"initial_weapons": [WeaponData.WeaponType.SERPENTS],
	},
	{
		"id": "riva",
		"name": "Riva",
		"subtitle": "Llamarada Veloz",
		"lore": "Corredora curtida en las cenizas de la forja volcánica. Cuanto más corre, más velocidad acumula: al llegar a su máximo entra en ráfaga y el suelo bajo sus pies arde, dejando una estela de humo hirviente que quema a todo lo que pisa.",
		"color": Color(1.0, 0.45, 0.1),
		"portrait_label": "R",
		"stats": {
			"max_hp": 13.0,
			"move_speed": 6.0,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "El personaje personalizable no tiene pasiva: todo depende de su espalanza y de lo que encuentre.",
		"initial_weapons": [WeaponData.WeaponType.SPEAR_LANCE],
	},
	{
		"id": "garri",
		"name": "Garri",
		"subtitle": "Orco Punk",
		"lore": "Un orco con cresta y actitud desafiante. Lanza su hacha giratoria que se mantiene en el aire despedazando a quien se acerque.",
		"color": Color(0.1, 0.8, 0.4),
		"portrait_label": "G",
		"stats": {
			"max_hp": 24.0,
			"move_speed": 7.2,
		},
		"passive_name": "Actitud Punk",
		"passive_color": Color(0.2, 0.9, 0.3),
		"passive_desc": "Garri no tiene miedo al peligro. Su hacha giratoria es su mejor defensa y ataque.",
		"initial_weapons": [WeaponData.WeaponType.SPINNING_AXE],
	},
	{
		"id": "saimon",
		"name": "Saimon",
		"subtitle": "Maestro Elemental",
		"lore": "Un enigmático mago capaz de manipular los cinco elementos primordiales. Dispara proyectiles elementales en una secuencia constante: Fuego, Hielo, Viento, Agua y Planta.",
		"color": Color(0.8, 0.4, 0.9),
		"portrait_label": "S",
		"stats": {
			"max_hp": 11.0,
			"move_speed": 8.0,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Saimon aún no tiene pasiva asignada. Confía en su ciclo de proyectiles elementales.",
		"initial_weapons": [WeaponData.WeaponType.ELEMENTS_CYCLE],
	},
]

## Solo se juega con UN personaje: el personalizable (cuerpo base hecho a partir de Riva, ver CharacterLook).
## El resto de fichas siguen aquí pero ocultas; añadir su id para volver a usarlas.
const UNLOCKED_CHARACTERS: Array[String] = ["riva"]

func is_character_unlocked(char_id: String) -> bool:
	return UNLOCKED_CHARACTERS.has(char_id)

func is_index_unlocked(index: int) -> bool:
	if index < 0 or index >= CHARACTERS.size():
		return false
	return is_character_unlocked(String(CHARACTERS[index].get("id", "")))

func first_unlocked_index() -> int:
	for i in CHARACTERS.size():
		if is_index_unlocked(i):
			return i
	return 0

## Modelo idle (.fbx) de cada personaje.
## Misma tabla que usa PlayerAnimationController.setup_model(); se usa en la vista previa del menú.
const IDLE_MODELS := {
	"mikeura": "mikeura/mikeura_idle.fbx",
	"heckler": "mikeura/mikeura_idle.fbx",   # sin modelo propio: en juego usa el de Mikeura
	"vangry": "vangry/vangry-idle.fbx",
	"bronch": "bronch/bronch-idle.fbx",
	"tatan": "tatan/idle.fbx",
	"joel": "joel/joel-idle.fbx",
	"riva": "riva/riva-base.fbx",
	"garri": "garri/garri-idle.fbx",
	"saimon": "saimon/saimon-idle.fbx",
}

func get_idle_model_path(char_id: String) -> String:
	var rel: String = IDLE_MODELS.get(char_id, "")
	return "" if rel == "" else "res://assets/models/" + rel

func get_texture_path(char_id: String) -> String:
	if char_id == CharacterLook.CHAR_ID:
		return CharacterLookApplier.DETAIL_PATH   # el modelo base se colorea por materiales
	var tex_id := "mikeura" if char_id == "heckler" else char_id
	return "res://assets/textures/entities/%s/texture_%s.png" % [tex_id, tex_id]

func _ready() -> void:
	selected_index = custom_index()
	load_armory()

# ───────────── Yunque del salón: arma inicial de la mazmorra (personaje personalizable) ─────────────
## Armas que se pueden equipar en el yunque del Salón (DungeonHub). La espalanza es la de siempre.
const DUNGEON_WEAPONS: Array[int] = [WeaponData.WeaponType.SPEAR_LANCE, WeaponData.WeaponType.DAGGERS, WeaponData.WeaponType.MACE,
	WeaponData.WeaponType.GREATSWORD, WeaponData.WeaponType.SWORD]
## Modelo de espadón (GreatswordModels) que lleva el yunque cuando no hay uno equipado con otro.
var greatsword_skin: int = 0
## Modelo de espada de una mano (SwordModels), igual que el del espadón.
var sword_skin: int = 0
## Modelo de daga (DaggerModels) y de maza (MaceModels) que se muestran en el yunque y en la partida.
var dagger_skin: int = 0
var mace_skin: int = 0
var armory_path := "user://armeria.cfg"
var dungeon_weapon: int = WeaponData.WeaponType.SPEAR_LANCE

func load_armory() -> void:
	var cfg := ConfigFile.new()
	dungeon_weapon = WeaponData.WeaponType.SPEAR_LANCE
	if cfg.load(armory_path) == OK:
		var w := int(cfg.get_value("mazmorra", "arma", dungeon_weapon))
		if can_carry_into_dungeon(w):
			dungeon_weapon = w

## El yunque ofrece DUNGEON_WEAPONS, pero el arma que llevabas en la mano al acabar la última partida
## (PlayerEquipment) puede ser cualquiera de las que salen en la mazmorra (EquipmentDB.WEAPONS).
func can_carry_into_dungeon(w: int) -> bool:
	return DUNGEON_WEAPONS.has(w) or EquipmentDB.WEAPONS.has(w)

func set_dungeon_weapon(w: int) -> void:
	if not can_carry_into_dungeon(w) or (w == dungeon_weapon and FileAccess.file_exists(armory_path)):
		return
	dungeon_weapon = w
	var cfg := ConfigFile.new()
	cfg.load(armory_path)
	cfg.set_value("mazmorra", "arma", w)
	cfg.save(armory_path)

## Armas con las que empieza la partida: en la mazmorra el personaje personalizable lleva la del yunque;
## en supervivencia cada personaje la suya de siempre.
func initial_weapons() -> Array:
	var c := get_selected()
	if game_mode == "dungeon" and String(c.get("id", "")) == CharacterLook.CHAR_ID:
		return [dungeon_weapon]
	return c.get("initial_weapons", [WeaponData.WeaponType.SPEAR_LANCE])

func get_selected() -> Dictionary:
	if selected_index >= 0 and selected_index < CHARACTERS.size():
		var c: Dictionary = CHARACTERS[selected_index]
		if c.get("id", "") == CharacterLook.CHAR_ID:
			c = c.duplicate()
			c["name"] = CharacterLook.current().char_name   # el nombre lo pone el jugador
		return c
	return {}

## Índice en CHARACTERS del personaje personalizable.
func custom_index() -> int:
	for i in CHARACTERS.size():
		if CHARACTERS[i].get("id", "") == CharacterLook.CHAR_ID:
			return i
	return 0

## Applies the selected character's stats and passive to the player node.
func apply_to_player(player: CharacterBody3D) -> void:
	var char_data := get_selected()
	if char_data.is_empty():
		return

	var stats: Dictionary = char_data.get("stats", {})
	# Vida extra para TODOS los personajes (se suma a la vida propia de cada uno)
	if stats.has("max_hp"):     player.max_hp     = float(stats["max_hp"]) + BASE_HP_BONUS
	if stats.has("move_speed"): player.move_speed  = stats["move_speed"]
	if game_mode == "dungeon":
		player.move_speed *= DUNGEON_MOVE_SPEED_MULT
	elif game_mode == "survival":
		player.move_speed *= SURVIVAL_PLAYER_SPEED_MULT

	# Assign passive based on character id
	match char_data.get("id", ""):
		"vangry":
			player.passive = PassiveVangry.new()
			player.passive.apply_to_player(player)
		"bronch":
			player.passive = PassiveBronch.new()
			player.passive.apply_to_player(player)
		"riva":
			# El personaje personalizable no tiene pasiva (Pies Humeantes queda en PassiveRiva, sin usar)
			player.passive = null
		"heckler":
			player.passive = PassiveHeckler.new()
			player.passive.apply_to_player(player)
		"tatan":
			# Tatan has no dedicated passive yet; fall through with no passive.
			player.passive = null
func preload_assets() -> void:
	var paths = preload_paths()
	_preload_from(paths)

func preload_paths() -> Array:
	var all := _preload_list()
	# Con enemigos dibujados por MultiMesh (animación horneada) los FBX de enemigos ya no hacen falta
	# (en la mazmorra los goblins son nodos con su propio FBX, así que sí se cargan)
	if EnemyVisuals.is_available() and game_mode != "dungeon":
		return all.filter(func(p): return not String(p).ends_with(".fbx"))
	return all

func _preload_list() -> Array:
	return [
		"res://assets/models/entities/enemigos/goblins/idle_magoblin.fbx",
		"res://assets/models/entities/enemigos/goblins/caminar_magoblin.fbx",
		"res://assets/models/entities/enemigos/goblins/goblin_idle_zombie.fbx",
		"res://assets/models/entities/enemigos/goblins/goblin_caminar_zombie.fbx",
		"res://assets/models/entities/enemigos/goblins/idle_goblin_bruto.fbx",
		"res://assets/models/entities/enemigos/goblins/caminar_goblin_bruto.fbx",
		"res://assets/models/entities/enemigos/goblins/idle_normal_goblin.fbx",
		"res://assets/models/entities/enemigos/goblins/caminar_normal_goblin.fbx",
		"res://assets/textures/enemigos/textura_mago_goblin.png",
		"res://assets/textures/enemigos/textura_zombie_goblin.png",
		"res://assets/textures/enemigos/textura_goblin_bruto.png",
		"res://assets/textures/enemigos/texture_normal_goblin.png",
		"res://scripts/objects/floating_damage.gd",
		"res://scenes/objects/bullet.tscn",
		"res://scenes/objects/weapon_pickup.tscn",
		"res://scenes/objects/xp_orb.tscn",
		"res://scenes/objects/item_pickup.tscn"
	]

func _preload_from(paths: Array) -> void:
	for path in paths:
		if path.ends_with(".fbx"):
			if not cache_enemy_models.has(path):
				cache_enemy_models[path] = load(path)
		elif path.ends_with(".png"):
			if not cache_enemy_textures.has(path):
				cache_enemy_textures[path] = load(path)
		else:
			load(path) # Cache it in memory for Godot's internal ResourceCache
