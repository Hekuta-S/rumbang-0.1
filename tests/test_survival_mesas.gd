extends Node

## Mapa de supervivencia: mesetas con paredes que el jugador no sube andando, rampas transitables y
## enemigos que van en línea recta y trepan la pared (EnemyMotion.resolve_step), más despacio.
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	var total := 0
	var zigs := 0
	var tops_ok := true
	var walls_ok := true
	var ramps_ok := true
	var reach_ok := true
	var vantage_ok := true
	var clear_ok := true
	var detect_ok := true
	var climb_slow_ok := true
	var pads := 0
	var pads_ok := true
	var chutes := 0
	var chute_ok := true
	var bridges := 0
	var bridge_ok := true
	var barrels := 0
	for map_seed in [3, 11, 27, 58, 91, 144, 202, 377, 512, 999]:
		var map := ProceduralMap.new()
		map.map_seed = map_seed
		add_child(map)
		EnemyMotion.reset()
		await get_tree().process_frame
		var mesas: Array = map.get_mesas()
		total += mesas.size()
		var roots := 0
		for i in mesas.size():
			var m: Dictionary = mesas[i]
			var c: Vector2 = m["c"]
			var r: float = m["r"]
			var top: float = m["top"]
			if int(m["parent"]) >= 0:
				zigs += 1
			else:
				roots += 1
			# 1. La cima está a su altura (en la base de un zigurat se mira fuera del segundo piso)
			var probe := c
			for j in mesas.size():
				if int(mesas[j]["parent"]) == i:
					probe = c + Vector2(r * 0.75, 0.0) if not map._on_ramp_of(m, c + Vector2(r * 0.75, 0.0), 1.0) else c - Vector2(r * 0.75, 0.0)
			if absf(map.get_height_at(probe.x, probe.y) - top) > 0.5:
				tops_ok = false
				print("  cima ", map_seed, "/", i, ": ", map.get_height_at(c.x, c.y), " vs ", top)
			# 2. Pared: en una dirección sin rampa hay un tramo que nadie sube (> 52°)
			var wall_dir := Vector2.ZERO
			for k in 16:
				var a := TAU * float(k) / 16.0
				var d := Vector2.from_angle(a)
				if not map._on_ramp_of(m, c + d * r, 3.0):
					wall_dir = d
					break
			var steep := 0.0
			var x := r - 3.0
			while x < r + 3.0:
				var p0 := c + wall_dir * x
				var p1 := c + wall_dir * (x + 0.2)
				steep = maxf(steep, map.get_height_at(p0.x, p0.y) - map.get_height_at(p1.x, p1.y))
				x += 0.2
			if steep < 0.2 * 1.3:
				walls_ok = false
				print("  pared baja ", map_seed, "/", i, ": ", steep)
			# 3. Rampas: del pie a la cima, ningún paso supera 45°
			for rp in m["ramps"]:
				var rd: Vector2 = rp["dir"]
				var u: float = r + float(rp["len"]) + 1.5
				var worst := 0.0
				while u > r - 2.5:
					var a0 := c + rd * u
					var a1 := c + rd * (u - 0.2)
					worst = maxf(worst, map.get_height_at(a1.x, a1.y) - map.get_height_at(a0.x, a0.y))
					u -= 0.2
				if worst > 0.2:
					ramps_ok = false
					print("  rampa empinada ", map_seed, "/", i, ": ", worst / 0.2)
			# 4. Un enemigo en línea recta (EnemyMotion.resolve_step) llega arriba trepando, más lento que andando
			var root := i
			while int(mesas[root]["parent"]) >= 0:
				root = int(mesas[root]["parent"])
			var rr: float = mesas[root]["r"]
			var first: Vector2 = (mesas[root]["ramps"][0] as Dictionary)["dir"]
			for rot in [0.4, 1.6, 2.8, -1.9]:
				var start: Vector2 = (mesas[root]["c"] as Vector2) - first.rotated(rot) * (rr + 6.0)
				climb_slow_flag = true
				if not _walk_up(map, i, start):
					reach_ok = false
					print("  no llega arriba ", map_seed, "/", i, " c=", c, " r=", r, " top=", top, " desde ", start)
				else:
					# Si la línea recta cruza la pared (no una rampa), tuvo que trepar más despacio
					var rc: Vector2 = mesas[root]["c"]
					var wall_pt: Vector2 = rc + (start - rc).normalized() * rr
					if not climb_slow_flag and int(mesas[i]["parent"]) < 0 and not map._on_ramp_of(mesas[root], wall_pt, 1.5):
						climb_slow_ok = false
						print("  no trepó despacio ", map_seed, "/", i, " desde ", start)
		# 5. Detección del jugador arriba (cima más alta) y abajo
		for i in mesas.size():
			var mc: Vector2 = mesas[i]["c"]
			var on_top := Vector3(mc.x, map.get_height_at(mc.x, mc.y), mc.y)
			var expect := i
			for j in mesas.size():
				if int(mesas[j]["parent"]) == i:
					expect = j
			EnemyMotion._route_frame = -1
			if EnemyMotion.player_mesa(on_top) != expect:
				detect_ok = false
			var below: Vector2 = mc + Vector2(float(mesas[i]["r"]) + 1.0, 0.0).rotated(0.3)
			EnemyMotion._route_frame = -1
			if int(mesas[i]["parent"]) < 0 and EnemyMotion.player_mesa(Vector3(below.x, map.get_height_at(below.x, below.y), below.y)) == i 					and map.get_height_at(below.x, below.y) < float(mesas[i]["top"]) - 2.0:
				detect_ok = false
		# 6. Runas lanzadoras: casi una por meseta, y la parábola llega a la cima sin chocar con la pared
		pads += map.get_jump_pads().size()
		for jp in map.get_jump_pads():
			var from: Vector3 = jp["pos"]
			var to: Vector3 = jp["target"]
			var v := JumpPad.launch_velocity(from, to)
			var q := from
			var t := 0.0
			var hit_wall := false
			while t < 5.0:
				v.y -= JumpPad.GRAVITY / 60.0
				q += v / 60.0
				t += 1.0 / 60.0
				var gh := map.get_height_at(q.x, q.z)
				if v.y < 0.0 and q.y <= gh:
					break
				if q.y < gh - 0.3:
					hit_wall = true
			if hit_wall or Vector2(q.x - to.x, q.z - to.z).length() > 1.5 or absf(q.y - to.y) > 1.0:
				pads_ok = false
				print("  runa falla ", map_seed, " ", from, " -> ", to, " cae en ", q, " choca=", hit_wall)
		# 7. Toboganes: deslizarse desde arriba acaba más rápido de lo que empezó
		for m in mesas:
			for rp in m["ramps"]:
				if not rp.get("chute", false):
					continue
				chutes += 1
				var rd: Vector2 = rp["dir"]
				var c0: Vector2 = (m["c"] as Vector2) + rd * (float(m["r"]) - 1.0)
				var pos := Vector3(c0.x, map.get_height_at(c0.x, c0.y), c0.y)
				var v := Vector3(rd.x, 0, rd.y) * 6.0
				for n in 600:
					var cd: Vector2 = map.chute_dir_at(pos.x, pos.z)
					if cd == Vector2.ZERO:
						break
					v = PlayerMovementController.slide_step(v, PlayerMovementController.ground_gradient(pos), 22.0, 1.0 / 60.0, map.slide_friction_at(pos.x, pos.z))
					pos += v / 60.0
					pos.y = map.get_height_at(pos.x, pos.z)
				if v.length() < 10.0:
					chute_ok = false
					print("  tobogán lento ", map_seed, ": ", v.length())
		# 8. Puentes: la tabla apoya a ras en las dos cimas, deja hueco debajo y los enemigos la cruzan
		for br in map.get_bridges():
			bridges += 1
			var a: Vector2 = br["a"]
			var b: Vector2 = br["b"]
			if absf(map.get_height_at(a.x, a.y) - float(br["ya"])) > 0.12 or absf(map.get_height_at(b.x, b.y) - float(br["yb"])) > 0.12:
				bridge_ok = false
				print("  puente sin apoyo ", map_seed, " ", map.get_height_at(a.x, a.y), "/", br["ya"])
			var ma: Dictionary = mesas[int(br["ma"])]
			var mb: Dictionary = mesas[int(br["mb"])]
			var start: Vector2 = (ma["c"] as Vector2).lerp(a, 0.5)
			var goal: Vector2 = (mb["c"] as Vector2).lerp(b, 0.5)
			var q := start
			var y := EnemyMotion.height_at(q.x, q.y)
			var bi := -1
			var used := false
			var low := false
			for n in 3000:
				if q.distance_to(goal) < 0.5:
					break
				var r4 := EnemyMotion.step_layers(q, (goal - q).limit_length(0.15), y, bi)
				q = Vector2(r4.x, r4.y)
				y = r4.z
				bi = int(r4.w)
				used = used or bi >= 0
				var t := (q - a).dot(b - a) / (b - a).length_squared()
				if t > 0.1 and t < 0.9 and y < lerpf(float(br["ya"]), float(br["yb"]), t) - 0.3:
					low = true
			if not used or low or q.distance_to(goal) > 0.6 or absf(y - float(mb["top"])) > 0.6:
				bridge_ok = false
				print("  no cruza el puente ", map_seed, " usado=", used, " cae=", low, " fin=", q, " y=", y)
			# Por debajo se pasa sin subirse
			var mid := a.lerp(b, 0.5)
			var side := Vector2(-(b - a).y, (b - a).x).normalized()
			var q2 := mid + side * 8.0
			var y2 := EnemyMotion.height_at(q2.x, q2.y)
			var bi2 := -1
			for n in 200:
				var r4 := EnemyMotion.step_layers(q2, -side * 0.15, y2, bi2)
				q2 = Vector2(r4.x, r4.y)
				y2 = r4.z
				bi2 = int(r4.w)
				if bi2 >= 0:
					bridge_ok = false
					print("  se subió al puente desde abajo ", map_seed)
					break
		barrels += map.get_barrel_spots().size()
		# 9. Un punto alto por meseta (el piso más alto) y sin props sobre las paredes
		if map.get_vantage_points().size() != roots:
			vantage_ok = false
		for kind in map._instances:
			if kind in ["pillar", "rock_a", "mushroom", "brazier"]:
				continue                      # decoración propia de las mesetas
			for t in map._instances[kind]:
				var o: Vector3 = (t as Transform3D).origin
				if map._near_mesa(Vector2(o.x, o.z), 0.0):
					clear_ok = false
		map.queue_free()
		await get_tree().process_frame
	_check(total >= 20, "salen mesetas en todos los mapas (%d en 10 semillas, %d pisos de zigurat)" % [total, zigs])
	_check(tops_ok, "las cimas están a su altura")
	_check(walls_ok, "las paredes no se suben andando")
	_check(ramps_ok, "las rampas se suben (≤ 45°)")
	_check(reach_ok, "los enemigos trepan la pared en línea recta, también al segundo piso")
	_check(climb_slow_ok, "trepar es más lento que andar")
	_check(detect_ok, "se detecta al jugador arriba de cada meseta (y no al pie)")
	_check(pads >= int(total * 0.75), "runas lanzadoras en casi todas las mesetas (%d de %d)" % [pads, total])
	_check(pads_ok, "las runas dejan en la cima sin chocar con la pared")
	_check(chutes >= 3 and chute_ok, "toboganes: deslizarse por el barro gana velocidad (%d toboganes)" % chutes)
	_check(bridges >= 2 and bridge_ok, "puentes a ras de las cimas, los enemigos los cruzan y por debajo se pasa (%d puentes)" % bridges)
	_check(barrels >= 40, "barriles explosivos repartidos (%d)" % barrels)
	_check(vantage_ok, "un punto alto por meseta")
	_check(clear_ok, "los props del mapa no tapan mesetas ni rampas")
	EnemyMotion.reset()
	get_tree().quit(1 if _fail else 0)

## Va en línea recta hacia la cima de la meseta `target` con EnemyMotion.resolve_step (pasos de 0,15 m).
## Al llegar comprueba que en la pared avanzó más despacio.
func _walk_up(map: ProceduralMap, target: int, start: Vector2) -> bool:
	EnemyMotion.available()
	var m: Dictionary = map.get_mesas()[target]
	var goal: Vector2 = m["c"]
	var p := start
	var y := EnemyMotion.height_at(p.x, p.y)
	var slow_steps := 0
	for n in 4000:
		if p.distance_to(goal) < 1.0:
			if y < float(m["top"]) - 1.0:
				return false
			if slow_steps == 0:
				climb_slow_flag = false
			return true
		var step := (goal - p).limit_length(0.15)
		var r := EnemyMotion.resolve_step(p, step, y)
		var np := Vector2(r.x, r.y)
		if np.distance_to(p) < step.length() * 0.9:
			slow_steps += 1
		p = np
		y = r.z
	return false

var climb_slow_flag := true
