## GameData.gd — Autoload Singleton
## Stores character definitions and the player's selection across scenes.
extends Node

var selected_index: int = 0

var cache_enemy_models: Dictionary = {}
var cache_enemy_textures: Dictionary = {}
var cache_enemy_anims: Dictionary = {}
var cache_bullet_mats: Dictionary = {}

## All playable characters defined here.
## Add new characters to this array to make them appear in the selection screen.
const CHARACTERS: Array = [
	{
		"id": "mikeura",
		"name": "Mikeura",
		"subtitle": "Guerrero del Escudo",
		"lore": "Portador de una armadura ancestral imbuida con magia de barrera. Su escudo no es solo protección — es su arma más poderosa.",
		"color": Color(0.2, 0.55, 1.0),
		"portrait_label": "M",
		"stats": {
			"max_hp": 10.0,
			"max_shield": 8.0,
			"max_energy": 200.0,
			"move_speed": 8.5,
		},
		"passive_name": "Escudo Irrompible",
		"passive_color": Color(0.35, 0.75, 1.0),
		"passive_desc": "El escudo mitiga el 55% del daño recibido. No se recarga mientras conserve carga. Al vaciarse por completo, genera un estallido que empuja a todos los enemigos cercanos.",
	},
	{
		"id": "heckler",
		"name": "Heckler",
		"subtitle": "Zombi Teletransportador",
		"lore": "Un no muerto que olvidó cómo correr, pero aprendió a rasgar el espacio-tiempo. Usa su propio brazo desprendible como un bumerán letal.",
		"color": Color(0.4, 0.7, 0.3),
		"portrait_label": "H",
		"stats": {
			"max_hp": 15.0,
			"max_shield": 0.0,
			"max_energy": 150.0,
			"move_speed": 7.0,
		},
		"passive_name": "Paso del Vacío",
		"passive_color": Color(0.5, 0.8, 0.4),
		"passive_desc": "No puede correr. Al usar la tecla de correr, consume 40 de energía para teletransportarse instantáneamente hacia adelante.",
	},
	{
		"id": "vangry",
		"name": "Vangry",
		"subtitle": "Titán Radiactivo",
		"lore": "Forjado en un reactor nuclear derretido, Vangry convirtió la radiación que lo quemó en su mayor arma. Los enemigos que se acercan se pudren en su aura tóxica.",
		"color": Color(0.5, 0.9, 0.25),
		"portrait_label": "V",
		"stats": {
			"max_hp": 12.0,
			"max_shield": 3.0,
			"max_energy": 150.0,
			"move_speed": 7.8,
		},
		"passive_name": "Zona de Radiación",
		"passive_color": Color(0.45, 1.0, 0.3),
		"passive_desc": "Una pequeña zona radiactiva rodea a Vangry y daña continuamente a todos los enemigos que se encuentren dentro de ella.",
	},
	{
		"id": "bronch",
		"name": "Bronch",
		"subtitle": "Químico de Esporas",
		"lore": "Botánico chiflado obsesionado con hongos mutantes. Su bazuca lanza esporas que explotan en nubes corrosivas, devorando todo lo que tocan.",
		"color": Color(0.78, 0.92, 0.25),
		"portrait_label": "B",
		"stats": {
			"max_hp": 13.0,
			"max_shield": 3.0,
			"max_energy": 160.0,
			"move_speed": 7.2,
		},
		"passive_name": "Esporas Superpotenciadas",
		"passive_color": Color(0.8, 0.95, 0.3),
		"passive_desc": "Las esporas de Bronch son más potentes: el impacto y las nubes de la bazuca infligen +50% de daño y duran más tiempo.",
	},
	{
		"id": "crane",
		"name": "Crane",
		"subtitle": "Asesina de Doble Daga",
		"lore": "Sombra de la noche, Crane baila entre sus enemigos con dos dagas gemelas — una roja, una azul. Cortes veloces de corto alcance, y un golpe cruzado con ambas dagas para rematar.",
		"color": Color(1.0, 0.35, 0.55),
		"portrait_label": "C",
		"stats": {
			"max_hp": 9.0,
			"max_shield": 4.0,
			"max_energy": 160.0,
			"move_speed": 9.2,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Crane aún no tiene pasiva asignada. Por ahora confía en sus dagas gemelas roja y azul.",
	},
	{
		"id": "kaionz",
		"name": "Kaionz",
		"subtitle": "Maestro del Viento",
		"lore": "Forjado en el ojo de un huracán eterno, Kaionz convirtió el viento en sus propios puños. Cada golpe es una ráfaga de aire comprimido. Al chocar sus dos puños, genera una onda expansiva que ralentiza a todos los enemigos cercanos.",
		"color": Color(0.55, 0.88, 1.0),
		"portrait_label": "K",
		"stats": {
			"max_hp": 11.0,
			"max_shield": 5.0,
			"max_energy": 180.0,
			"move_speed": 9.0,
		},
		"passive_name": "Viento Perpetuo",
		"passive_color": Color(0.55, 0.88, 1.0),
		"passive_desc": "Kaionz se mueve más rápido que sus rivales y el cooldown de su habilidad se reduce un 15%. El viento siempre sopla a su favor.",
	},
	{
		"id": "tatan",
		"name": "Tatan",
		"subtitle": "Duende Alquimista",
		"lore": "Un astuto duende experto en alquimia y polvos mágicos. Su morral nunca se vacía de brebajes explosivos, curativos y estimulantes.",
		"color": Color(0.4, 0.85, 0.5),
		"portrait_label": "T",
		"stats": {
			"max_hp": 10.0,
			"max_shield": 4.0,
			"max_energy": 220.0,
			"move_speed": 8.8,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Tatan aún no tiene pasiva asignada. Confía plenamente en sus polvos alquímicos de tres modos.",
	},
	{
		"id": "joel",
		"name": "Joel",
		"subtitle": "Druida de la Floresta",
		"lore": "Vehemente guardián de un bosque ancestral, Joel canaliza la esencia de la naturaleza en serpientes de esmeralda. Al atacar, invoca tres serpientes que se abren en abanico: una al centro y dos en los bordes.",
		"color": Color(0.3, 0.85, 0.4),
		"portrait_label": "J",
		"stats": {
			"max_hp": 11.0,
			"max_shield": 4.0,
			"max_energy": 220.0,
			"move_speed": 8.0,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Joel aún no tiene pasiva asignada. Por ahora confía en sus serpientes de esmeralda disparadas en cono.",
	},
	{
		"id": "riva",
		"name": "Riva",
		"subtitle": "Llamarada Veloz",
		"lore": "Corredora curtida en las cenizas de la forja volcánica. Cuanto más corre, más velocidad acumula: al llegar a su máximo entra en ráfaga y el suelo bajo sus pies arde, dejando una estela de humo hirviente que quema a todo lo que pisa.",
		"color": Color(1.0, 0.45, 0.1),
		"portrait_label": "R",
		"stats": {
			"max_hp": 10.0,
			"max_shield": 3.0,
			"max_energy": 180.0,
			"move_speed": 7.5,
		},
		"passive_name": "Pies Humeantes",
		"passive_color": Color(1.0, 0.6, 0.15),
		"passive_desc": "Mientras se mueve, la velocidad de Riva aumenta progresivamente. Al alcanzar su velocidad máxima entra en ráfaga: súper carrera con la animación riva-corre-rapido y deja una estela de humo abrasador que quema a los enemigos por segundo.",
	},
	{
		"id": "garri",
		"name": "Garri",
		"subtitle": "Orco Punk",
		"lore": "Un orco con cresta y actitud desafiante. Lanza su hacha giratoria que se mantiene en el aire despedazando a quien se acerque.",
		"color": Color(0.1, 0.8, 0.4),
		"portrait_label": "G",
		"stats": {
			"max_hp": 15.0,
			"max_shield": 2.0,
			"max_energy": 120.0,
			"move_speed": 7.0,
		},
		"passive_name": "Actitud Punk",
		"passive_color": Color(0.2, 0.9, 0.3),
		"passive_desc": "Garri no tiene miedo al peligro. Su hacha giratoria es su mejor defensa y ataque.",
	},
	{
		"id": "saimon",
		"name": "Saimon",
		"subtitle": "Maestro Elemental",
		"lore": "Un enigmático mago capaz de manipular los cinco elementos primordiales. Dispara proyectiles elementales en una secuencia constante: Fuego, Hielo, Viento, Agua y Planta.",
		"color": Color(0.8, 0.4, 0.9),
		"portrait_label": "S",
		"stats": {
			"max_hp": 9.0,
			"max_shield": 5.0,
			"max_energy": 250.0,
			"move_speed": 7.5,
		},
		"passive_name": "Sin pasiva",
		"passive_color": Color(0.6, 0.6, 0.65),
		"passive_desc": "Saimon aún no tiene pasiva asignada. Confía en su ciclo de proyectiles elementales.",
	},
]

func get_selected() -> Dictionary:
	if selected_index >= 0 and selected_index < CHARACTERS.size():
		return CHARACTERS[selected_index]
	return {}

## Applies the selected character's stats and passive to the player node.
func apply_to_player(player: CharacterBody3D) -> void:
	var char_data := get_selected()
	if char_data.is_empty():
		return

	var stats: Dictionary = char_data.get("stats", {})
	if stats.has("max_hp"):     player.max_hp     = stats["max_hp"]
	if stats.has("max_shield"): player.max_shield = stats["max_shield"]
	if stats.has("max_energy"): player.max_energy = stats["max_energy"]
	if stats.has("move_speed"): player.move_speed  = stats["move_speed"]

	# Assign passive based on character id
	match char_data.get("id", ""):
		"mikeura":
			player.passive = PassiveShieldWarrior.new()
			player.passive.apply_to_player(player)
		"vangry":
			player.passive = PassiveVangry.new()
			player.passive.apply_to_player(player)
		"bronch":
			player.passive = PassiveBronch.new()
			player.passive.apply_to_player(player)
		"kaionz":
			player.passive = PassiveKaionz.new()
			player.passive.apply_to_player(player)
		"riva":
			player.passive = PassiveRiva.new()
			player.passive.apply_to_player(player)
		"heckler":
			player.passive = PassiveHeckler.new()
			player.passive.apply_to_player(player)
		"tatan":
			# Tatan has no dedicated passive yet; fall through with no passive.
			player.passive = null
func preload_assets() -> void:
	var paths = [
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
	
	for path in paths:
		if path.ends_with(".fbx"):
			if not cache_enemy_models.has(path):
				cache_enemy_models[path] = load(path)
		elif path.ends_with(".png"):
			if not cache_enemy_textures.has(path):
				cache_enemy_textures[path] = load(path)
		else:
			load(path) # Cache it in memory for Godot's internal ResourceCache
