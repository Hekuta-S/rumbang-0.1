extends Node

## Cuánto tarda en montarse (entrar al árbol + _ready) cada hijo de la escena de juego, tras la misma
## precarga que hace la pantalla de carga. Solo CPU. MAP_SCENE elige la escena.

func _ready() -> void:
	var path := OS.get_environment("MAP_SCENE")
	if path == "":
		path = "res://scenes/core/main_dungeon.tscn"
	GameData.game_mode = "dungeon" if path.contains("dungeon") else "survival"
	SceneLoader.next_scene_path = path
	GameData.preload_assets()
	var LoadingScreen := load("res://scripts/ui/loading_screen.gd")
	LoadingScreen.cache_run_data_sync()
	if GameData.game_mode == "dungeon":
		for m in DungeonGoblin.warm_models():
			(m as Node).free()
	var ps := load(path) as PackedScene
	var all: Array = []
	_walk("res://assets", all)
	var before := {}
	for p in all:
		before[p] = ResourceLoader.has_cached(p)
	for pass_i in 2:
		print("pasada ", pass_i + 1)
		var main := ps.instantiate()
		var kids := main.get_children()
		for k in kids:
			main.remove_child(k)
		var holder := Node3D.new()
		add_child(holder)
		for k in kids:
			var t0 := Time.get_ticks_usec()
			holder.add_child(k)
			print("  %-24s %7.1f ms" % [k.name, (Time.get_ticks_usec() - t0) / 1000.0])
		await get_tree().create_timer(0.5).timeout
		if pass_i == 0:
			# Lo que la escena ha tenido que leer del disco al montarse (no estaba precargado)
			var missed: Array = []
			for p in all:
				if not before[p] and ResourceLoader.has_cached(p):
					missed.append(p)
			print("  no precargados: ", missed.size())
			# WRITE_MANIFEST=1: los apunta en resources/preload_manifest.json para que la pantalla de carga
			# los lea en segundo plano la próxima vez (LoadingScreen.manifest_paths)
			if OS.get_environment("WRITE_MANIFEST") == "1":
				var LS := load("res://scripts/ui/loading_screen.gd")
				var data: Dictionary = LS.read_manifest()
				var merged: Array = data.get(path.get_file(), [])
				for p in missed:
					if not merged.has(p):
						merged.append(p)
				merged.sort()
				data[path.get_file()] = merged
				var f := FileAccess.open(LS.MANIFEST, FileAccess.WRITE)
				f.store_string(JSON.stringify(data, "	"))
				f.close()
				print("  manifiesto: ", merged.size(), " rutas para ", path.get_file())
		holder.queue_free()
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir + "/" + sub, out)
	for f in d.get_files():
		if f.get_extension().to_lower() in ["glb", "fbx", "png", "jpg", "wav", "ogg", "tres", "res", "gdshader"]:
			out.append(dir + "/" + f)
