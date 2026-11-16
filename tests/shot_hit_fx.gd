extends Node

## Captura de los golpes en estilo cómic (necesita ventana): res://tests/shot_hit_fx.tscn -- <archivo.png>
## Tres goblins en la sala inicial reciben un golpe de espada cada uno (daño normal, fuerte y crítico) por su
## take_damage: salen la estrella de impacto entintada, la onomatopeya y el número de daño con la letra de
## cómic. Comprueba que el número usa la fuente de cómic y que la estrella es un sprite (no el destello).

var _out := "user://hit_fx.png"
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
	var gs: Array = []
	for i in 3:
		var g = enc._spawn_at(0, c + Vector3(-2.4 + 2.4 * i, 0.0, -1.5), "goblin")
		gs.append(g)
	await get_tree().create_timer(1.8).timeout
	for g in gs:
		g.max_hp = 9999.0
		g.hp = 9999.0
		g.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 55.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 2.6, 5.0), c + Vector3(0, 1.2, -1.5))
	cam.current = true
	await get_tree().create_timer(0.3).timeout
	var amounts := [8.0, 24.0, 45.0]
	Engine.time_scale = 0.15            # cámara lenta: que se vea todo a la vez en la captura
	for i in 3:
		HitFeedback.weapon_tag = WeaponData.WeaponType.SWORD
		(gs[i] as Node).process_mode = Node.PROCESS_MODE_INHERIT
		gs[i].take_damage(amounts[i], Vector3(0, 0, -1))
		(gs[i] as Node).process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().create_timer(0.05, true, false, true).timeout
	var hf := HitFeedback._instance()
	var stars := 0
	for s in hf._stars:
		stars += 1 if s.visible else 0
	_check("estrellas de impacto dibujadas (%d visibles)" % stars, hf._stars.size() > 0 and hf._flashes.is_empty())
	var comic := 0
	for n in get_tree().root.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.visible and l.font == FloatingDamage_font():
			comic += 1
	_check("números de daño con letra de cómic (%d)" % comic, comic > 0)
	# Estrellas con los colores de varias armas, para verlas en la captura (duran 0.12 s de tiempo real)
	var cols := [HitFeedback.PROFILES[WeaponData.WeaponType.SWORD]["color"], HitFeedback.PROFILES[WeaponData.WeaponType.MACE]["color"],
		HitFeedback.PROFILES[WeaponData.WeaponType.KATANA]["color"]]
	for i in 3:
		hf._flash(c + Vector3(-1.6 + 1.6 * i, 1.0, -0.6), cols[i], 1.3)
	await get_tree().create_timer(0.07, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(_out)
	Engine.time_scale = 1.0
	print("captura guardada: ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)

func FloatingDamage_font() -> Font:
	return (load("res://scripts/objects/floating_damage.gd") as GDScript).comic_font()
