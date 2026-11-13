extends Node

## Cuánto tarda cada fase de la generación del mapa (solo CPU). MAP_SCENE elige la escena.

const DUNGEON_PHASES := ["_layout_rooms", "_carve", "_find_walls", "_compute_wall_dist", "_build_floor", "_build_walls",
	"@rooms", "_place_cliffs", "_place_torches", "_place_rock_art", "_place_mushrooms", "_place_cave_decor",
	"_build_single_props", "_build_prop_nodes", "_build_grass", "_build_crystals", "_build_breakables", "_build_extra"]
const SURVIVAL_PHASES := ["_setup_noise", "_pick_layout", "_build_terrain", "_scatter_props", "_build_prop_nodes"]

func _ready() -> void:
	var path := OS.get_environment("MAP_SCENE")
	if path == "":
		path = "res://scenes/core/main_dungeon.tscn"
	GameData.game_mode = "dungeon" if path.contains("dungeon") else "survival"
	var t0 := Time.get_ticks_usec()
	var main := (load(path) as PackedScene).instantiate()
	add_child(main)
	print("add_child total: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await get_tree().create_timer(2.0).timeout
	var map := main.get_node("ProceduralMap")
	t0 = Time.get_ticks_usec()
	map.generate(1234)
	print("generate() entero: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await get_tree().create_timer(0.5).timeout
	# Por fases (mismo orden que generate)
	map._clear()
	var phases: Array = DUNGEON_PHASES if map is DungeonMap else SURVIVAL_PHASES
	if map is DungeonMap:
		map.rooms.clear()
		map._cells.clear()
		map._owner.clear()
		map._wall_dist.clear()
		map._walls.clear()
		map._outer.clear()
		map._wall_boxes.clear()
		map._grass.clear()
		map._breakables.clear()
		map._crystals.clear()
		map._torch_anchors.clear()
		map._bake_sources.clear()
		map._cliff_spots.clear()
		map._torch_spots.clear()
		map._anchor_room.clear()
		map._prop_cells.clear()
	map._rng.seed = 1234
	for ph in phases:
		t0 = Time.get_ticks_usec()
		if ph == "@rooms":
			for i in map.rooms.size():
				map._decorate_room(i)
		else:
			map.call(ph)
		print("  %-22s %6.1f ms" % [ph, (Time.get_ticks_usec() - t0) / 1000.0])
	get_tree().quit(0)
