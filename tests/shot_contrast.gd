extends Node

## Capturas de legibilidad (necesita ventana, no headless): res://tests/shot_contrast.tscn -- <prefijo>
##  SHOT_MODE=dungeon (por defecto): goblin, bruto, mago, rata, babosa y un élite en la sala inicial →
##      <prefijo>_enemies.png. SHOT_RIM=0 quita el contorno y el brillo propio (para comparar con el antes).
##  SHOT_MODE=survival: el ciclo día → noche en varias fases → <prefijo>_t000.png, _t042.png...

var _out := "user://contrast"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var survival := OS.get_environment("SHOT_MODE") == "survival"
	GameData.game_mode = "survival" if survival else "dungeon"
	var scene := "res://scenes/core/main_procedural.tscn" if survival else Net.game_scene()
	_main = (load(scene) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	(_run_survival if survival else _run_dungeon).call_deferred()

func _run_dungeon() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node("DungeonEncounter")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: Node3D = _main.get_node("Player")
	var c := map.room_center(0)
	player.global_position = Vector3(c.x, 0.3, c.z)
	var kinds := ["goblin", "brute", "mage", "rat", "slug", "goblin"]
	var spawned: Array = []
	for i in kinds.size():
		var a := -0.9 + 1.8 * float(i) / float(kinds.size() - 1)
		var p := c + Vector3(sin(a), 0.0, -cos(a)) * (6.0 + 2.0 * (i % 2))
		spawned.append(enc._spawn_at(0, p, kinds[i]))
	DungeonElites.make(spawned[-1], "vampirico")
	await get_tree().create_timer(1.6).timeout          # que termine la materialización
	for g in spawned:
		if is_instance_valid(g):
			g.process_mode = Node.PROCESS_MODE_DISABLED
			g.look_at(Vector3(c.x, g.global_position.y, c.z + 4.0), Vector3.UP, true)
	if OS.get_environment("SHOT_RIM") == "0":
		for g in spawned:
			if is_instance_valid(g):
				g.set_rim(Color(0, 0, 0, 0))
		for m in DungeonGoblin._tex_mats.values():
			(m as BaseMaterial3D).emission_enabled = false
	var cam := Camera3D.new()
	cam.fov = 65.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 2.6, 4.5), c + Vector3(0, 0.6, -5.0))
	cam.current = true
	player.visible = false
	await get_tree().create_timer(0.5).timeout
	_save("_enemies")
	get_tree().quit(0)

func _run_survival() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(5.0).timeout
	var cycle := _main.get_node_or_null("DayNightCycle") as DayNightCycle
	if cycle == null:
		push_error("sin DayNightCycle")
		get_tree().quit(1)
		return
	cycle.set_process(false)
	for t in [0.0, 0.42, 0.7, 0.86, 1.0]:
		cycle.apply(t)
		await get_tree().create_timer(1.5).timeout     # el cielo rehace su radiancia por partes
		_save("_t%03d" % int(round(t * 100.0)))
	get_tree().quit(0)

func _save(suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out + suffix + ".png"
	img.save_png(path)
	print("captura guardada: ", ProjectSettings.globalize_path(path))
