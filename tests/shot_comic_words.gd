extends Node

## Captura de las onomatopeyas de cómic (necesita ventana): res://tests/shot_comic_words.tscn -- <archivo.png>
## Monta la mazmorra, pone tres goblins delante de la cámara y les da un golpe a cada uno (uno de
## ellos, remate) llamando a HitFeedback como lo hace el combate. Comprueba además el límite de ritmo.

var _out := "user://comic_words.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node("DungeonEncounter")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: Node3D = _main.get_node("Player")
	var c := map.room_center(0)
	player.global_position = Vector3(c.x, 0.3, c.z + 3.0)
	var spawned: Array = []
	for i in 3:
		spawned.append(enc._spawn_at(0, c + Vector3(-2.6 + 2.6 * i, 0.0, -2.0), "goblin"))
	await get_tree().create_timer(1.8).timeout
	for g in spawned:
		g.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 60.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 2.4, 4.6), c + Vector3(0, 1.0, -2.0))
	cam.current = true
	await get_tree().create_timer(0.3).timeout
	var words: ComicWords = null
	# SHOT_WEAPON=mace|fist: palabras de ese grupo (por defecto, espada)
	var weapon: int = {"mace": WeaponData.WeaponType.MACE, "fist": WeaponData.WeaponType.FISTS}.get(
		OS.get_environment("SHOT_WEAPON"), WeaponData.WeaponType.SWORD)
	for i in 3:
		HitFeedback.weapon_tag = weapon
		HitFeedback.on_enemy_hit(spawned[i], 38.0 if i == 1 else 12.0, Vector3(0, 0, -1), false)
		if words == null:
			words = HitFeedback._instance().get_node("ComicWords")
			# dos golpes en el mismo instante: el segundo no saca palabra (límite de ritmo)
			var again := words.pop(WeaponData.WeaponType.SWORD, Vector3.ZERO, Vector3.FORWARD, 0.5, false, false)
			print("CHECK límite de ritmo: ", "PASSED" if not again else "FAILED")
			print("CHECK arma sin palabras: ", "PASSED" if ComicWords.group_of(WeaponData.WeaponType.BOW) == "" else "FAILED")
		await get_tree().create_timer(0.2, true, false, true).timeout
	var shown := 0
	for s in words.get_children():
		if (s as Sprite3D).visible:
			shown += 1
	print("CHECK palabras en pantalla: ", shown, " ", "PASSED" if shown == 3 else "FAILED")
	get_viewport().get_texture().get_image().save_png(_out)
	print("captura guardada: ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)
