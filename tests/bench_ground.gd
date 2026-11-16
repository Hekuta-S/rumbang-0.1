extends Node

## Coste de dibujo del mapa de supervivencia sin enemigos (necesita ventana y --disable-vsync):
##   godot --path . --disable-vsync res://tests/bench_ground.tscn
## GROUND_OLD=1 vuelve al suelo procedural (dark_ground) y a los props planos, para comparar con el cartoon
## horneado. BENCH_SECONDS (8). Imprime la media de ms por frame.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	var old := OS.get_environment("GROUND_OLD") == "1"
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	if old:
		(main.get_node("ProceduralMap") as ProceduralMap).use_toon_props = false
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var waves: Node = null
	for i in 900:
		await get_tree().process_frame
		waves = main.find_child("WaveManager", true, false)
		if waves and waves.get("_running"):
			break
	if waves:
		waves.set_process(false)
	if old:
		var ground := main.get_node("ProceduralMap/Ground") as MeshInstance3D
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/dark_ground.gdshader")
		ground.mesh.surface_set_material(0, mat)
	await get_tree().create_timer(3.0).timeout
	var secs := float(OS.get_environment("BENCH_SECONDS")) if OS.get_environment("BENCH_SECONDS") != "" else 8.0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while (Time.get_ticks_usec() - t0) < int(secs * 1e6):
		await get_tree().process_frame
		frames += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	print("BENCH suelo=%s  %.3f ms/frame  (%.0f FPS, %d frames)" % ["viejo" if old else "cartoon", ms, 1000.0 / ms, frames])
	get_tree().quit(0)
