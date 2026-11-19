extends Node

## El movimiento de enemigos en C++ (EnemyMotionNative) da lo mismo que el GDScript (EnemyMotion.move):
## miles de pasos al azar (llano, mesetas, obstáculos, puentes, empuje del jugador) en varios mapas.
## También mide cuánto tarda cada uno. Sin la extensión compilada la prueba se salta (no falla).
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

const STEPS := 4000
const TOL := 0.002

func _ready() -> void:
	if not ClassDB.class_exists(&"EnemyMotionNative"):
		print("SKIPPED: extensión nativa no cargada (bin/rumbang_native.gdextension)")
		get_tree().quit(0)
		return
	var worst := 0.0
	var mismatches := 0
	var on_bridge := 0
	var pushed := 0
	var t_gd := 0
	var t_cpp := 0
	var e := EnemyData.new(EnemyData.EnemyType.NORMAL_GOBLIN)
	for map_seed in [3, 27, 144, 512]:
		var map := ProceduralMap.new()
		map.map_seed = map_seed
		add_child(map)
		EnemyMotion.reset()
		await get_tree().process_frame
		_check(EnemyMotion.available(), "mapa %d disponible" % map_seed)
		EnemyMotion.height_at(0, 0)       # construye
		var native: Object = EnemyMotion._native
		_check(native != null, "mapa %d: movimiento en C++ activo" % map_seed)
		if native == null:
			continue
		var half: float = float(map.get("play_half")) if map.get("play_half") != null else 60.0
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed
		var bridges: Array = map.get_bridges()
		for i in STEPS:
			var pos: Vector2
			var bi := -1
			if not bridges.is_empty() and i % 5 == 0:
				# Sobre un puente: punto de la tabla
				var k := rng.randi() % bridges.size()
				var br: Dictionary = bridges[k]
				var t := rng.randf_range(0.05, 0.95)
				pos = (br["a"] as Vector2).lerp(br["b"], t)
				bi = k
			else:
				pos = Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			var gy := EnemyMotion.height_at(pos.x, pos.y) if bi < 0 else EnemyMotion.bridge_deck(bi, pos)
			var vel := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			var dt := 1.0 / 30.0 * float(1 << (rng.randi() % 3))
			var pp := Vector3(pos.x + rng.randf_range(-1.2, 1.2), 0, pos.y + rng.randf_range(-1.2, 1.2))
			# GDScript
			e.global_position = Vector3(pos.x, gy, pos.y)
			e.ground_y = gy
			e.bridge_i = bi
			EnemyMotion._native = null
			var t0 := Time.get_ticks_usec()
			EnemyMotion.move(e, vel, dt, pp)
			t_gd += Time.get_ticks_usec() - t0
			var a_pos := e.global_position
			var a_bi := e.bridge_i
			# C++
			e.global_position = Vector3(pos.x, gy, pos.y)
			e.ground_y = gy
			e.bridge_i = bi
			EnemyMotion._native = native
			t0 = Time.get_ticks_usec()
			EnemyMotion.move(e, vel, dt, pp)
			t_cpp += Time.get_ticks_usec() - t0
			var b_pos := e.global_position
			var d := a_pos.distance_to(b_pos)
			worst = maxf(worst, d)
			if d > TOL or a_bi != e.bridge_i:
				mismatches += 1
				if mismatches <= 5:
					print("  distinto: mapa %d paso %d gd=%s/%d c++=%s/%d" % [map_seed, i, a_pos, a_bi, b_pos, e.bridge_i])
			if a_bi >= 0:
				on_bridge += 1
			if Vector2(a_pos.x, a_pos.z).distance_to(Vector2(pos.x, pos.y)) > 0.0 and Vector2(a_pos.x, a_pos.z).distance_to(Vector2(pp.x, pp.z)) <= 0.951:
				pushed += 1
		map.queue_free()
		await get_tree().process_frame
	_check(mismatches == 0, "C++ = GDScript en %d pasos (peor diferencia %.5f m, %d sobre puentes)" % [STEPS * 4, worst, on_bridge])
	print("TIEMPO: GDScript %.2f us/paso, C++ %.2f us/paso (%.1fx)" % [float(t_gd) / (STEPS * 4), float(t_cpp) / (STEPS * 4), float(t_gd) / maxf(float(t_cpp), 1.0)])
	print("ALL NATIVE MOTION CHECKS PASSED" if not _fail else "NATIVE MOTION CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
