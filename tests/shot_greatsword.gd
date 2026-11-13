extends Node

## Capturas del espadón (necesita ventana, no headless): res://tests/shot_greatsword.tscn -- <prefijo> [modo]
## Una fila por modelo de espadón (GreatswordModels), 6 fotogramas por fila, guardada en <prefijo>_<modo>.png:
##   guardia   reposo de lado, reposo de frente y 4 fotogramas del primer tajo
##   combo     gs1 -> gs2 -> gs3 encadenados (6 fotogramas repartidos)
##   corrida   andando, ya corriendo y el ataque con carrerilla
## Con el modo "roll:<grados>" gira el espadón esos grados sobre su eje (para afinar el agarre).

class FixedMove extends MovementSource:
	var v := Vector2(0, -1)
	func get_movement_vector() -> Vector2:
		return v

const CELL := Vector2i(320, 400)
var _prefix := "user://gs"
var _main: Node

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
	var mode := "guardia"
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		mode = args[1]
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.health_comp.max_hp = 9999.0
	player.health_comp.hp = 9999.0
	var W := WeaponData.WeaponType.GREATSWORD
	player.add_weapon(W)
	player.select_slot(player.weapon_slots.find(W))
	var cam := Camera3D.new()
	cam.fov = 35.0
	_main.add_child(cam)
	cam.current = true
	var light := OmniLight3D.new()
	light.omni_range = 12.0
	light.light_energy = 2.0
	_main.add_child(light)
	get_viewport().size = CELL
	var vis = player.weapon_visuals
	var ac: PlayerAnimationController = player.animation_controller
	var mover := FixedMove.new()
	var shots := 6
	var sheet := Image.create(CELL.x * shots, CELL.y * GreatswordModels.count(), false, Image.FORMAT_RGBA8)
	for skin in GreatswordModels.count():
		player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.mesh.rotation.y = 0.0
		vis.set_greatsword_skin(skin)
		if mode.begins_with("roll:"):
			vis._gs_holder.transform = Transform3D(PlayerWeaponVisuals.gs_grip_basis(PlayerWeaponVisuals.GS_BLADE_DIR) \
				* Basis(Vector3.UP, deg_to_rad(float(mode.get_slice(":", 1)))), PlayerWeaponVisuals.GS_GRIP_OFFSET)
		await get_tree().create_timer(0.8).timeout
		player.resources.energy = PlayerResources.ENERGY_MAX
		player.combat_controller.attack_cooldown = 0.0
		if mode == "corrida":
			mover.v = Vector2(0, -1)
			player.input_controller._direct_sources.append(mover)
		for i in shots:
			var wait := 0.15
			match mode:
				"combo":
					player.resources.energy = PlayerResources.ENERGY_MAX
					player.combat_controller.buffer_attack()
					wait = 0.5
				"corrida":
					if i == 3:
						player.resources.energy = PlayerResources.ENERGY_MAX
						player.combat_controller.attack_cooldown = 0.0
						player.attack()
					wait = 0.7 if i < 3 else 0.3
				_:
					if i == 2:
						player.attack()
					wait = 0.25 if i >= 2 else 0.1
			var p := player.global_position
			var fwd: Vector3 = -player.mesh.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			if mode == "guardia" and i == 1:
				cam.global_position = p + fwd * 3.2 + right * 0.6 + Vector3(0, 1.3, 0)
			else:
				cam.global_position = p + fwd * 1.4 + right * 3.2 + Vector3(0, 1.2, 0)
			cam.look_at(p + Vector3(0, 1.0, 0))
			light.global_position = p + right * 2.0 + fwd * 1.5 + Vector3(0, 2.5, 0)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, skin * CELL.y))
			await get_tree().create_timer(wait).timeout
		player.input_controller._direct_sources.erase(mover)
		print("  skin ", skin, " ", GreatswordModels.skin_name(skin), " acción final: ", ac._current_action_name)
	var path := "%s_%s.png" % [_prefix, mode.replace(":", "_")]
	sheet.save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
