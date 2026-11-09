extends Node

## Tira de fotogramas de la locomoción en la mazmorra (necesita ventana, no headless):
##   res://tests/shot_walk.tscn -- <prefijo> [arma,arma,...] [empuje]
## Para cada arma (maza, dagas, espalanza) el jugador anda en línea recta con el empuje de stick indicado
## (1 = a tope, lo normal con teclado) y se guarda <prefijo>_<arma>.png: 8 fotogramas de lado y 4 de tres
## cuartos, repartidos en un segundo. También imprime la velocidad y el estado de locomoción.
## Con "<arma>_golpe" (maza_golpe, dagas_golpe...) no anda: lanza el primer golpe del combo quieto y guarda 12
## fotogramas de lado repartidos en 1,8 s; con "<arma>_quieto", 12 fotogramas en reposo (guardia); con
## "<arma>_combo", 18 fotogramas en 5,4 s pulsando atacar sin parar (el combo entero encadenado); con
## "espadon_correr" / "espada_correr", el arma tras 3 s andando (ya corre); "espadon_golpe" / "espadon_combo" como el resto;
## con "maza_crater", el golpe al suelo (mace1) y después el mazazo con salto, desde arriba, para ver los cráteres.

class FixedMove extends MovementSource:
	var v := Vector2(0, -1)
	func get_movement_vector() -> Vector2:
		return v

var _prefix := "user://walk"
var _main: Node
const CELL := Vector2i(320, 400)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(3.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.health_comp.max_hp = 9999.0
	player.health_comp.hp = 9999.0
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var args := OS.get_cmdline_user_args()
	var names: Array = ["maza", "dagas", "espalanza"]
	if args.size() > 1:
		names = String(args[1]).split(",")
	var push := float(args[2]) if args.size() > 2 else 1.0
	var W := WeaponData.WeaponType
	var by_name := {"maza": W.MACE, "dagas": W.DAGGERS, "espalanza": W.SPEAR_LANCE, "espadon": W.GREATSWORD, "espada": W.SWORD}
	var cam := Camera3D.new()
	cam.fov = 35.0
	_main.add_child(cam)
	cam.current = true
	var light := OmniLight3D.new()
	light.omni_range = 12.0
	light.light_energy = 1.4
	_main.add_child(light)
	get_viewport().size = CELL
	var mover := FixedMove.new()
	mover.v = Vector2(0, -push)
	for full in names:
		var nm := String(full).get_slice("_", 0)
		var mode := String(full).get_slice("_", 1) if String(full).contains("_") else "andar"
		var w: int = by_name[nm]
		player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		if not player.weapon_slots.has(w):
			player.add_weapon(w)
		player.select_slot(player.weapon_slots.find(w))
		await get_tree().create_timer(0.6).timeout
		if mode == "andar" or mode == "correr":
			player.input_controller._direct_sources.append(mover)
			# "correr" (espadón): espera a que pase de andar a correr (GS_RUN_DELAY s sin combate)
			await get_tree().create_timer(1.0 if mode == "andar" else 3.0).timeout   # entra en el ciclo
		elif mode == "golpe":
			player.resources.energy = PlayerResources.ENERGY_MAX
			player.combat_controller.attack_cooldown = 0.0
			player.attack()
		var shots := 18 if mode == "combo" else 12
		if mode == "crater":
			player.resources.energy = PlayerResources.ENERGY_MAX
			player.combat_controller.attack_cooldown = 0.0
			player.animation_controller._combo_index = 1   # mace1: la diagonal que acaba en el suelo
			player.animation_controller._combo_timer = 1.0
			player.attack()
		if mode == "combo":
			player.resources.energy = PlayerResources.ENERGY_MAX
			player.combat_controller.attack_cooldown = 0.0
			player.attack()
		var sheet := Image.create(CELL.x * 6, CELL.y * (shots / 6), false, Image.FORMAT_RGBA8)
		var t0 := Time.get_ticks_msec()
		for i in shots:
			if mode == "crater" and i == 6:
				player.resources.energy = PlayerResources.ENERGY_MAX
				player.combat_controller.attack_cooldown = 0.0
				player.combat_controller.mace_slam()
			if mode == "combo":
				player.resources.energy = PlayerResources.ENERGY_MAX
				player.combat_controller.buffer_attack()
				var cur := String(player.animation_controller._current_action_name)
				print("  t=%.1f s %s" % [i * 0.3, cur])
			var p := player.global_position
			var fwd: Vector3 = -player.mesh.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			if mode == "crater":
				cam.global_position = p + fwd * 4.5 + right * 2.5 + Vector3(0, 3.2, 0)
				cam.look_at(p + fwd * 1.4)
			elif mode != "andar" and mode != "correr":
				cam.global_position = p + fwd * 1.2 + right * 3.6 + Vector3(0, 1.1, 0)
			elif i < 8:
				cam.global_position = p + right * 3.6 + Vector3(0, 1.0, 0)
			else:
				cam.global_position = p + fwd * 2.6 + right * 2.2 + Vector3(0, 1.3, 0)
			if mode != "crater":
				cam.look_at(p + Vector3(0, 0.9, 0))
			light.global_position = p + right * 2.0 + Vector3(0, 2.5, 0)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 6) * CELL.x, (i / 6) * CELL.y))
			if i == 0 and (mode == "andar" or mode == "correr"):
				print("ANDAR %s: %.2f m/s, estado %s" % [nm, Vector2(player.velocity.x, player.velocity.z).length(),
					player.animation_controller.playback.get_current_node()])
			var step := 1.0 / 12.0
			if mode == "golpe":
				step = 1.8 / 12.0
			elif mode == "combo":
				step = 0.3
			elif mode == "crater":
				step = 0.25
			await get_tree().create_timer(step).timeout
		print("  (%d ms para 12 fotogramas)" % (Time.get_ticks_msec() - t0))
		player.input_controller._direct_sources.erase(mover)
		var path := "%s_%s.png" % [_prefix, full]
		sheet.save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
