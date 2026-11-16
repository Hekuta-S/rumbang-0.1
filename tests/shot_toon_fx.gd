extends Node

## Captura de las nubes de polvo y humo dibujadas (necesita ventana):
##   res://tests/shot_toon_fx.tscn -- <archivo.png>
## En la sala inicial de la mazmorra lanza a la vez: polvo de aterrizaje (FootDustVFX.land), polvo de un prop
## roto (DestructibleProp), una estela de humo (SmokeTrailZone) si existe su escena, y un golpe de puños
## (nube de HitFeedback). Comprueba que cada emisor usa la textura de ToonFX.

var _out := "user://toon_fx.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	print("CHECK ", label, ": ", "PASSED" if ok else "FAILED")

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node("DungeonEncounter")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: Node3D = _main.get_node("Player")
	var c := map.room_center(0)
	player.global_position = Vector3(c.x + 6.0, 0.3, c.z + 6.0)
	var goblin = enc._spawn_at(0, c + Vector3(2.4, 0.0, -1.5), "goblin")
	await get_tree().create_timer(1.8).timeout
	goblin.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 55.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 2.2, 5.2), c + Vector3(0, 0.7, -1.0))
	cam.current = true
	await get_tree().create_timer(0.3).timeout

	_check("textura de nubes cargada", ToonFX.puff_texture() != null)
	# 1. Aterrizaje fuerte
	FootDustVFX.land(_main, c + Vector3(-2.6, 0.02, -0.5), 1.0)
	_check("polvo de pasos con nubes dibujadas", FootDustVFX._cloud_mat.albedo_texture == ToonFX.puff_texture())
	# 2. Prop roto: el barril más cercano
	var best: DestructibleProp = null
	for d in map.destructibles:
		if is_instance_valid(d) and (best == null or d.global_position.distance_to(c) < best.global_position.distance_to(c)):
			best = d
	if best:
		best.global_position = c + Vector3(0.0, 0.0, -1.2)
		best.take_damage(9999.0, Vector3(0, 0, -1))
	# 3. Golpe de puños: nube de impacto
	HitFeedback.weapon_tag = WeaponData.WeaponType.FISTS
	HitFeedback.on_enemy_hit(goblin, 30.0, Vector3(0, 0, -1), false)
	var puffs: Array = HitFeedback._instance()._particles.get("puff", [])
	_check("nube de impacto con textura dibujada", not puffs.is_empty()
		and ((puffs[0] as CPUParticles3D).mesh as PrimitiveMesh).material.albedo_texture == ToonFX.puff_texture())
	await get_tree().create_timer(0.28, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(_out)
	print("captura guardada: ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)
