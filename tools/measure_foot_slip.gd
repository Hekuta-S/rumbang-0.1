extends Node

## Mide si los pies patinan en la locomoción del jugador (mazmorra, headless):
##   Godot --headless --path . res://tools/measure_foot_slip.tscn -- [arma_modo,...]
## arma = maza|dagas|espalanza|espadon|espada; modo = andar (stick a medias) | correr (stick a tope, espera a
## que el espadón/espada pase a correr). Para cada caso imprime la velocidad del cuerpo, el estado, la escala de
## la locomoción, los pasos por segundo y el deslizamiento del pie apoyado: su velocidad en el mundo a lo largo
## del avance mientras es el pie más bajo. 0 = pie plantado; negativo = el pie va hacia atrás (la animación va
## demasiado deprisa); positivo = el pie avanza (la animación va lenta).

class FixedMove extends MovementSource:
	var v := Vector2(0, -1)
	func get_movement_vector() -> Vector2:
		return v

var _main: Node
var _player: CharacterBody3D
var _cam: Camera3D
var _keep_walking := false   ## espadón/espada: sin pasar a correr (note_combat cada fotograma)
var _fast := false            ## fuerza la carrera rápida del personaje

func _physics_process(_d: float) -> void:
	if _player == null:
		return
	if _keep_walking and _player.movement_controller:
		_player.movement_controller.note_combat()
	_player.set("is_riva_fast", _fast)

func _ready() -> void:
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(2.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.health_comp.max_hp = 9999.0
	player.health_comp.hp = 9999.0
	var args := OS.get_cmdline_user_args()
	var cases: Array = ["espalanza_andar", "espalanza_correr", "espada_andar", "espada_correr", "espadon_andar", "espadon_correr"]
	if args.size() > 0:
		cases = String(args[0]).split(",")
	var W := WeaponData.WeaponType
	var by_name := {"maza": W.MACE, "dagas": W.DAGGERS, "espalanza": W.SPEAR_LANCE, "espadon": W.GREATSWORD, "espada": W.SWORD}
	var mover := FixedMove.new()
	var ac = player.animation_controller
	var skel := ac._find_first_node_of_type(ac.model, "Skeleton3D") as Skeleton3D
	var feet := [skel.find_bone("mixamorig_LeftFoot"), skel.find_bone("mixamorig_RightFoot")]
	for c in cases:
		var nm := String(c).get_slice("_", 0)
		var mode := String(c).get_slice("_", 1)
		var w: int = by_name[nm]
		player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		if not player.weapon_slots.has(w):
			player.add_weapon(w)
		player.select_slot(player.weapon_slots.find(w))
		await get_tree().create_timer(0.5).timeout
		mover.v = Vector2(0, -1.0)
		var base_speed: float = player.move_speed
		if mode == "andar" and nm in ["maza", "dagas", "espalanza"]:
			player.move_speed = 2.0     # el personaje solo anda si algo lo frena
		_keep_walking = mode == "andar"
		_fast = mode == "rapido"
		_player = player
		player.input_controller._direct_sources.append(mover)
		var home := map.room_center(0) + Vector3(0, 0.3, 0)
		# Sin chocar con las paredes: vuelve al centro de la sala cada medio segundo (se conserva la velocidad)
		for j in (6 if mode == "correr" else 2):
			await get_tree().create_timer(0.5).timeout
			player.global_position = home - Vector3(0, 0, -2.0)
		var prev := [Vector3.INF, Vector3.INF]
		var slip_sum := 0.0
		var slip_n := 0
		var spd_sum := 0.0
		var n := 0
		var plant_changes := 0
		var last_plant := -1
		var t_total := 0.0
		var nat_sum := 0.0
		var samples := []   # [i, dt, [z,y] x2, scale]
		# Con SLIP_SHOTS=<prefijo>: 12 fotogramas de lado (2 por tramo entre teletransportes) en <prefijo>_<caso>.png
		var shots_prefix := OS.get_environment("SLIP_SHOTS")
		var sheet: Image = Image.create(320 * 6, 400 * 2, false, Image.FORMAT_RGBA8) if shots_prefix != "" else null
		var shot_i := 0
		if sheet and _cam == null:
			_cam = Camera3D.new()
			_cam.fov = 35.0
			_main.add_child(_cam)
			_cam.current = true
			var light := OmniLight3D.new()
			light.omni_range = 12.0
			light.light_energy = 1.4
			_cam.add_child(light)
			get_viewport().size = Vector2i(320, 400)
		for i in 240:
			if i % 40 == 0:
				player.global_position = home - Vector3(0, 0, -2.0)
				prev = [Vector3.INF, Vector3.INF]
			await get_tree().process_frame
			var dt := get_process_delta_time()
			var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
			var dir := vel.normalized()
			# Pie respecto al esqueleto (solo la animación), girado al mundo: así no influye cuándo se mueve el cuerpo
			var pos := []
			for k in 2:
				pos.append(skel.global_transform.basis * skel.get_bone_global_pose(feet[k]).origin)
			var low := 0 if pos[0].y < pos[1].y else 1
			var on_floor2: bool = player.is_on_floor() and String(ac.playback.get_current_node()) != "jump"
			if i % 40 >= 8 and on_floor2 and vel.length() > 0.5:
				samples.append([i, dt, pos[0].dot(dir), pos[0].y, pos[1].dot(dir), pos[1].y, float(ac.anim_tree.get("parameters/loco_scale/scale")), vel.length()])
			if OS.get_environment("SLIP_DUMP") != "":
				print("DUMP %d %.4f %.4f %.4f %.4f %.4f %.4f %s" % [i, dt, pos[0].dot(dir), pos[0].y, pos[1].dot(dir), pos[1].y, vel.length(), ac.playback.get_current_node()])
			if sheet and i % 40 >= 10 and i % 40 < 34 and i % 4 == 0 and shot_i < 12:
				var p := player.global_position
				var f: Vector3 = -player.mesh.global_transform.basis.z
				f.y = 0.0
				var r := Vector3(-f.z, 0.0, f.x).normalized()
				_cam.global_position = p + r * 3.6 + Vector3(0, 1.0, 0)
				_cam.look_at(p + Vector3(0, 0.9, 0))
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(320, 400)), Vector2i((shot_i % 6) * 320, (shot_i / 6) * 400))
				shot_i += 1
				prev = [Vector3.INF, Vector3.INF]
			var on_floor: bool = player.is_on_floor() and String(ac.playback.get_current_node()) != "jump"
			if i % 40 >= 8 and on_floor and prev[low] != Vector3.INF and vel.length() > 0.5 and dt > 0.0:
				var local_v: Vector3 = (pos[low] - prev[low]) / dt
				slip_sum += (local_v + vel).dot(dir)
				nat_sum += -local_v.dot(dir) / maxf(float(ac.anim_tree.get("parameters/loco_scale/scale")), 0.01)
				slip_n += 1
			if low != last_plant:
				if last_plant != -1:
					plant_changes += 1
				last_plant = low
			prev = pos
			spd_sum += vel.length()
			n += 1
			t_total += dt
		print("SLIP %-18s v=%.2f m/s estado=%s loco_scale=%.2f strafe=%.2f pasos/s=%.2f deslizamiento=%+.2f m/s (%+.0f%%) clip_a_escala_1=%.2f m/s" % [
			c, spd_sum / n, ac.playback.get_current_node(), float(ac.anim_tree.get("parameters/loco_scale/scale")),
			float(ac.anim_tree.get("parameters/legs/blend_amount")), plant_changes / t_total,
			slip_sum / maxf(slip_n, 1), 100.0 * (slip_sum / maxf(slip_n, 1)) / maxf(spd_sum / n, 0.01), nat_sum / maxf(slip_n, 1)])
		_analyze(c, samples, ac)
		if sheet:
			sheet.save_png("%s_%s.png" % [shots_prefix, c])
		player.move_speed = base_speed
		_keep_walking = false
		_fast = false
		player.input_controller._direct_sources.erase(mover)
		await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)


## Apoyo = pie a menos de 3,5 cm de su punto más bajo. Velocidad natural del clip = retroceso medio del pie apoyado
## respecto al esqueleto dividido por la escala de reproducción.
func _analyze(c: String, samples: Array, ac) -> void:
	if samples.size() < 4:
		return
	var nat := 0.0
	var nn := 0
	var slip := 0.0
	for k in 2:
		var miny := INF
		for s in samples:
			miny = minf(miny, s[3 + 2 * k])
		for j in range(1, samples.size()):
			var a: Array = samples[j - 1]
			var b: Array = samples[j]
			if int(b[0]) != int(a[0]) + 1:
				continue
			if b[3 + 2 * k] < miny + 0.035 and a[3 + 2 * k] < miny + 0.035:
				var lv: float = (b[2 + 2 * k] - a[2 + 2 * k]) / b[1]
				nat += -lv / float(b[6])
				slip += lv + float(b[7])
				nn += 1
	var cur := String(ac.playback.get_current_node())
	var anim_name := String((ac.sm.get_node(cur) as AnimationNodeAnimation).animation) if ac.sm.has_node(cur) else cur
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	var length: float = lib.get_animation(anim_name).length if lib.has_animation(anim_name) else 0.0
	var sc: float = samples[-1][6]
	print("STANCE %-18s clip=%s len=%.2f s escala=%.2f -> pasos/s=%.2f (a escala 1: %.2f) | v=%.2f m/s | clip a escala 1 = %.2f m/s | deslizamiento apoyado=%+.2f m/s | escala sin patinar=%.2f" % [
		c, anim_name, length, sc, 2.0 * sc / maxf(length, 0.01), 2.0 / maxf(length, 0.01), samples[-1][7], nat / maxf(nn, 1),
		slip / maxf(nn, 1), float(samples[-1][7]) / maxf(nat / maxf(nn, 1), 0.01)])
