extends Node

## Barrio del Desagüe (SewerDistrict, historia 008): mapa de 320 m, canales hundidos con paredes que nadie
## sube andando, escaleras, agua que frena, puentes a ras de orilla que cruzan los enemigos y un tallado que
## sale igual con la misma semilla (LAN).
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	var size_ok := true
	var mesa_ok := true
	var floor_ok := true
	var wall_ok := true
	var water_ok := true
	var stair_ok := true
	var bridge_ok := true
	var cross_ok := true
	var wade_ok := true
	var props_ok := true
	var blend_ok := true
	var canal_bridges := 0
	var gen_ms := 0.0
	var seeds := [3, 11, 27, 58, 91, 144, 202, 377]
	for map_seed in seeds:
		var t0 := Time.get_ticks_usec()
		var map := ProceduralMap.new()
		map.map_seed = map_seed
		add_child(map)
		gen_ms += float(Time.get_ticks_usec() - t0) / 1000.0
		EnemyMotion.reset()
		await get_tree().process_frame
		var d: SewerDistrict = map.district
		if map.half_size != 160.0 or d == null or d.canals.size() < 3:
			size_ok = false
			print("  sin barrio ", map_seed)
			map.queue_free()
			await get_tree().process_frame
			continue
		# 1. Ninguna meseta dentro del barrio
		for m in map.get_mesas():
			if d.contains(m["c"], float(m["r"])):
				mesa_ok = false
				print("  meseta en el barrio ", map_seed, " ", m["c"])
		var main_u: Vector2 = d.local_range(d.canals[0])[0]
		# 2. Suelo del canal, orilla a nivel de calle y agua
		for v in [-60.0, -20.0, 25.0, 70.0]:
			var mid := d.to_world((main_u.x + main_u.y) * 0.5, v)
			if d._in_stair(mid, 1.0):
				continue
			var hf := map.get_height_at(mid.x, mid.y)
			if absf(hf - d.floor_y) > 0.05:
				floor_ok = false
				print("  suelo ", map_seed, " v=", v, ": ", hf, " vs ", d.floor_y)
			var bank := d.to_world(main_u.x - 3.0, v)
			if not d._in_stair(bank, 1.0) and not map._near_bridge(bank, 1.0) and absf(map.get_height_at(bank.x, bank.y) - d.street_y) > 0.05:
				floor_ok = false
				print("  orilla ", map_seed, " v=", v, ": ", map.get_height_at(bank.x, bank.y), " vs ", d.street_y)
			if not map.is_water(Vector3(mid.x, hf, mid.y)) or map.is_water(Vector3(bank.x, d.street_y, bank.y)):
				water_ok = false
			# 3. Pared: de la orilla al fondo hay un tramo de más de 52° (lo que EnemyMotion ya no sube andando)
			if d._in_stair(d.to_world(main_u.x, v), 2.0):
				continue
			var steep := 0.0
			var u := main_u.x - 3.0
			while u < main_u.x + 1.0:
				var p0 := d.to_world(u, v)
				var p1 := d.to_world(u + 0.2, v)
				steep = maxf(steep, map.get_height_at(p0.x, p0.y) - map.get_height_at(p1.x, p1.y))
				u += 0.2
			if steep < 0.2 * 1.3:
				wall_ok = false
				print("  pared suave ", map_seed, " v=", v, ": ", steep / 0.2)
		# 4. Escaleras: del fondo a la orilla sin pasos de más de 45°
		if d.stairs.size() < 3:
			stair_ok = false
		for s in d.stairs:
			var from: Vector2 = s["from"]
			var dir: Vector2 = s["dir"]
			var mn: Vector2 = s["min"]
			var mx: Vector2 = s["max"]
			var c := (mn + mx) * 0.5
			var lat := Vector2(-dir.y, dir.x)
			var start := from + lat * (c - from).dot(lat) - dir * 0.6
			var worst := 0.0
			var t := 0.0
			while t < float(s["len"]) + 1.0:
				var a := start + dir * t
				var b := start + dir * (t + 0.2)
				worst = maxf(worst, map.get_height_at(b.x, b.y) - map.get_height_at(a.x, a.y))
				t += 0.2
			var top := start + dir * (float(s["len"]) + 1.2)
			if worst > 0.2 or absf(map.get_height_at(top.x, top.y) - d.street_y) > 0.3:
				stair_ok = false
				print("  escalera ", map_seed, ": paso ", worst / 0.2, " arriba ", map.get_height_at(top.x, top.y))
		# 5. Puentes a ras de orilla que un enemigo cruza sin caer al agua
		EnemyMotion.available()
		for br in map.get_bridges():
			if not br.get("canal", false):
				continue
			canal_bridges += 1
			var a: Vector2 = br["a"]
			var b: Vector2 = br["b"]
			if absf(map.get_height_at(a.x, a.y) - float(br["ya"])) > 0.12 or absf(map.get_height_at(b.x, b.y) - float(br["yb"])) > 0.12:
				bridge_ok = false
				print("  puente sin apoyo ", map_seed, " ", map.get_height_at(a.x, a.y), " / ", br["ya"])
				continue
			var dirb := (b - a).normalized()
			var q := a - dirb * 2.0
			var goal := b + dirb * 2.0
			var y := EnemyMotion.height_at(q.x, q.y)
			var bi := -1
			var low := false
			var used := false
			for n in 2000:
				if q.distance_to(goal) < 0.3:
					break
				var r := EnemyMotion.step_layers(q, (goal - q).limit_length(0.12), y, bi)
				q = Vector2(r.x, r.y)
				y = r.z
				bi = int(r.w)
				if bi >= 0:
					used = true
				if y < d.street_y - 0.5:
					low = true
			if not used or low or q.distance_to(goal) > 0.5:
				bridge_ok = false
				print("  puente no cruzado ", map_seed, " usado=", used, " cayó=", low)
		# 6. Sin puente: baja al canal y trepa la otra pared, más despacio que en llano
		var vfree := 0.0
		for v in [-75.0, -35.0, 15.0, 60.0, 95.0]:
			var ok := true
			for br in map.get_bridges():
				if br.get("canal", false) and absf(d.to_local(br["a"]).y - v) < 6.0:
					ok = false
			for s in d.stairs:
				if absf(d.to_local(((s["min"] as Vector2) + (s["max"] as Vector2)) * 0.5).y - v) < 6.0:
					ok = false
			for c in d.canals.slice(1):
				if absf(float(c["cross_v"]) - v) < 8.0:
					ok = false
			if ok:
				vfree = v
				break
		var p := d.to_world(main_u.x - 4.0, vfree)
		var goal2 := d.to_world(main_u.y + 4.0, vfree)
		var y2 := EnemyMotion.height_at(p.x, p.y)
		var steps := 0
		var dipped := false
		for n in 3000:
			if p.distance_to(goal2) < 0.3:
				break
			var r := EnemyMotion.resolve_step(p, (goal2 - p).limit_length(0.12), y2)
			p = Vector2(r.x, r.y)
			y2 = r.z
			steps += 1
			if y2 < d.floor_y + 0.1:
				dipped = true
		var flat := int((main_u.y - main_u.x + 8.0) / 0.12)
		if p.distance_to(goal2) > 0.3 or not dipped or steps <= flat + 3:
			cross_ok = false
			print("  cruce a pie ", map_seed, ": llegó=", p.distance_to(goal2) < 0.3, " bajó=", dipped, " pasos ", steps, " / llano ", flat)
		# 7. Props fuera de los canales y de las escaleras
		for kind in map._instances:
			for xf: Transform3D in map._instances[kind]:
				var pp := Vector2(xf.origin.x, xf.origin.z)
				if d.in_canal(pp, 0.2) or d._in_stair(pp, 0.2):
					props_ok = false
					print("  prop en el canal ", map_seed, " ", kind, " ", pp)
		# 8. La transición del campo a la calle se puede andar (< 45°)
		for v in [-100.0, -50.0, 0.0, 50.0, 100.0]:
			var worst := 0.0
			var u := SewerDistrict.DEPTH_START - SewerDistrict.BLEND - 4.0
			while u < SewerDistrict.DEPTH_START + 2.0:
				var p0 := d.to_world(u, v)
				var p1 := d.to_world(u + 0.3, v)
				if not map._near_mesa(p0, 2.0):
					worst = maxf(worst, absf(map.get_height_at(p1.x, p1.y) - map.get_height_at(p0.x, p0.y)) / 0.3)
				u += 0.3
			if worst > 1.0:
				blend_ok = false
				print("  transición empinada ", map_seed, " v=", v, ": ", worst)
		if map.get_node_or_null("Water") == null:
			water_ok = false
		map.queue_free()
		EnemyMotion.reset()
		await get_tree().process_frame
	# 9. Frena al jugador en el agua (slow_mult del controlador de movimiento)
	var map2 := ProceduralMap.new()
	map2.map_seed = 27
	add_child(map2)
	await get_tree().process_frame
	var d2 := map2.district
	var fake := FakePlayer.new()
	fake.add_to_group("player")
	var mc := FakeMC.new()
	fake.movement_controller = mc
	add_child(fake)
	var mu: Vector2 = d2.local_range(d2.canals[0])[0]
	var wp := d2.to_world((mu.x + mu.y) * 0.5, 0.0)
	fake.global_position = Vector3(wp.x, d2.floor_y, wp.y)
	d2.tick(0.016)
	wade_ok = fake.movement_controller != null and is_equal_approx(mc.slow_mult, SewerDistrict.WATER_SLOW)
	# 10. Misma semilla, mismo barrio (LAN)
	var map3 := ProceduralMap.new()
	map3.map_seed = 27
	add_child(map3)
	await get_tree().process_frame
	var same := map3.district.canals.size() == d2.canals.size() and map3.district.axis == d2.axis and map3.district.side_sign == d2.side_sign
	if same:
		for i in d2.canals.size():
			if map3.district.canals[i]["min"] != d2.canals[i]["min"] or map3.district.canals[i]["max"] != d2.canals[i]["max"]:
				same = false
		var hs2: PackedFloat32Array = map2._heights
		var hs3: PackedFloat32Array = map3._heights
		same = same and hs2 == hs3
	print("  generar un mapa: %.0f ms de media, %d vértices de lado" % [gen_ms / float(seeds.size()), map2._side])
	_check(size_ok, "el mapa mide 320 m y tiene el Barrio del Desagüe con canal principal y desagües")
	_check(mesa_ok, "ninguna meseta cae dentro del barrio")
	_check(floor_ok, "canales hundidos a su altura y orillas a nivel de calle")
	_check(wall_ok, "las paredes del canal superan 52° (los enemigos las trepan despacio, el jugador no las sube)")
	_check(water_ok, "hay agua en los canales y no en las orillas")
	_check(stair_ok, "las escaleras suben del fondo a la orilla sin pasos de más de 45°")
	_check(bridge_ok and canal_bridges >= seeds.size() * 3, "puentes a ras de orilla que los enemigos cruzan sin caer (%d)" % canal_bridges)
	_check(cross_ok, "sin puente, un enemigo baja al canal y trepa la otra orilla más despacio")
	_check(props_ok, "ningún prop dentro de un canal ni de una escalera")
	_check(blend_ok, "la transición del campo a la calle se puede andar")
	_check(wade_ok, "el agua frena al jugador")
	_check(same, "misma semilla, mismo barrio y mismas alturas")
	EnemyMotion.reset()
	get_tree().quit(1 if _fail else 0)

class FakePlayer:
	extends Node3D
	var movement_controller: Object = null

class FakeMC:
	extends RefCounted
	var slow_mult := 1.0
	var slow_until := 0.0
