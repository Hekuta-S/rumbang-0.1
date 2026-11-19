extends Node

## La simulación completa de enemigos en C++ (EnemySimNative) se comporta como el bucle GDScript
## (EnemyManager + EnemyData.update): la misma horda en el mismo mapa, una vez con cada camino, y se
## comparan resultados globales (se acercan al jugador, le pegan, disparan, mueren, se empujan) además de
## que el objeto EnemyData quede al día (posición, alerta, vida). También mide el coste por tick.
## Sin la extensión compilada la prueba se salta (no falla).
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

const ENEMIES := 300
const TICKS := 300

var _player: Node3D

func _ready() -> void:
	if not ClassDB.class_exists(&"EnemySimNative"):
		print("SKIPPED: extensión nativa no cargada (bin/rumbang_native.gdextension)")
		get_tree().quit(0)
		return
	var map := ProceduralMap.new()
	map.map_seed = 27
	add_child(map)
	EnemyMotion.reset()
	await get_tree().process_frame
	EnemyMotion.available()
	var scr := GDScript.new()
	scr.source_code = "extends Node3D\nvar hits := 0\nvar velocity := Vector3.ZERO\nfunc take_damage(_d): hits += 1\n"
	scr.reload()
	_player = Node3D.new()
	_player.set_script(scr)
	_player.add_to_group("player")
	add_child(_player)

	var gd: Dictionary = await _run(false)
	var cpp: Dictionary = await _run(true)
	print("GDScript: ", gd)
	print("C++:      ", cpp)
	_check(cpp["native"], "la simulación en C++ estaba activa")
	_check(not gd["native"], "la pasada GDScript no usó el C++")
	_check(cpp["bad"] == 0, "sin posiciones inválidas (NaN o bajo el suelo)")
	_check(cpp["mean_dist"] < cpp["start_dist"] * 0.85, "la horda se acerca al jugador (%.1f -> %.1f m)" % [cpp["start_dist"], cpp["mean_dist"]])
	_check(absf(cpp["mean_dist"] - gd["mean_dist"]) < maxf(gd["mean_dist"] * 0.25, 2.0), "distancia media parecida a la del GDScript")
	_check(cpp["hits"] > 0, "los cuerpo a cuerpo golpean al jugador (%d)" % cpp["hits"])
	_check(cpp["hits"] >= gd["hits"] * 0.5 and cpp["hits"] <= gd["hits"] * 2.0 + 3, "golpes parecidos al GDScript (%d vs %d)" % [cpp["hits"], gd["hits"]])
	_check(cpp["killed"] == gd["killed"], "las muertes a mitad del bucle reciclan bien")
	# Algunas balas de mago acaban dando a otros enemigos (bullet.gd), así que los vivos pueden variar un poco
	_check(absi(cpp["alive"] - gd["alive"]) <= 8, "vivos al final parecidos (%d vs %d)" % [cpp["alive"], gd["alive"]])
	_check(cpp["alerted"] == cpp["alive"], "is_alerted escrito de vuelta en el objeto")
	_check(cpp["kb_moved"] > 1.0, "el empujón (take_damage) mueve al enemigo en C++ (%.2f m)" % cpp["kb_moved"])
	_check(cpp["tokens"] <= HiveMind.MELEE_TOKENS, "tokens de ataque dentro del límite (%d)" % cpp["tokens"])
	_check(cpp["vis_ok"], "casillas de dibujo = enemigos vivos")
	_check(cpp["sep_mean"] > gd["sep_mean"] * 0.7, "la separación reparte como el GDScript (vecino medio %.2f vs %.2f m)" % [cpp["sep_mean"], gd["sep_mean"]])
	print("Coste por tick: GDScript %.3f ms, C++ %.3f ms" % [gd["ms"], cpp["ms"]])
	_check(cpp["ms"] < gd["ms"], "el C++ es más rápido")
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)

func _run(native: bool) -> Dictionary:
	EnemyManager.native_sim_enabled = native
	HiveMind.reset()
	EnemyRegistry.clear()
	var mgr := EnemyManager.new()
	add_child(mgr)
	mgr.set_physics_process(false)       # el test llama al bucle a mano para medir solo su coste
	_player.hits = 0
	_player.global_position = Vector3(0, EnemyMotion.height_at(0, 0), 0)
	seed(1234)
	var ens: Array = []
	var start := 0.0
	for i in ENEMIES:
		var a := float(i) / ENEMIES * TAU
		var r := 18.0 + float(i % 7) * 2.0
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = EnemyMotion.height_at(p.x, p.z)
		var e := EnemyManager.spawn(i % 6, p)
		e.alert()
		ens.append(e)
		start += r
	start /= ENEMIES
	var used_native := EnemyManager.using_native_sim()
	var killed := 0
	var kb_moved := 0.0
	var spent := 0
	var kb_target: EnemyData = null
	var kb_from := Vector3.ZERO
	for t in TICKS:
		await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		mgr._physics_process(1.0 / 60.0)
		spent += Time.get_ticks_usec() - t0
		if t == 60:
			# Mata a 30 a mitad de partida (swap-remove en los dos lados)
			for k in 30:
				var e: EnemyData = ens[k * 7 % ENEMIES]
				if not e.recycled:
					e.take_damage(1e6)
					killed += 1
		if t == 90:
			for e: EnemyData in ens:
				if not e.recycled:
					kb_target = e
					break
			kb_from = kb_target.global_position
			kb_target.take_damage(0.1, Vector3(20, 0, 0))
		if t == 96 and kb_target != null:
			kb_moved = Vector2(kb_target.global_position.x - kb_from.x, kb_target.global_position.z - kb_from.z).length()
	var alive := 0
	var alerted := 0
	var bad := 0
	var dsum := 0.0
	var pts: Array = []
	for e: EnemyData in ens:
		if e.recycled:
			continue
		alive += 1
		if e.is_alerted:
			alerted += 1
		var p: Vector3 = e.global_position
		if is_nan(p.x) or is_nan(p.z) or p.y < EnemyMotion.height_at(p.x, p.z) - 0.5:
			bad += 1
		dsum += Vector2(p.x, p.z).length()
		pts.append(Vector2(p.x, p.z))
	# Distancia media al vecino más cercano
	var sep_sum := 0.0
	for i in pts.size():
		var best := INF
		for j in pts.size():
			if j != i:
				best = minf(best, (pts[i] as Vector2).distance_to(pts[j]))
		sep_sum += best
	var sep_mean := sep_sum / maxf(pts.size(), 1)
	var vis_ok := true
	var tokens := HiveMind.tokens_used
	if used_native:
		var n := 0
		for k in EnemyVisuals.KEYS.size():
			n += EnemyManager.sim.vis_count(k)
		vis_ok = n == alive
	var res := {
		"native": used_native, "alive": alive, "alerted": alerted, "killed": killed, "bad": bad,
		"start_dist": start, "mean_dist": dsum / maxf(alive, 1), "hits": _player.hits, "kb_moved": kb_moved,
		"tokens": tokens, "vis_ok": vis_ok, "sep_mean": sep_mean, "ms": float(spent) / TICKS / 1000.0,
	}
	EnemyManager.recycle_all()
	mgr.queue_free()
	await get_tree().process_frame
	return res
