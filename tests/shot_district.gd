extends Node

## Capturas del Barrio del Desagüe (necesita ventana): res://tests/shot_district.tscn -- <prefijo>
## Monta la partida de Supervivencia, para las oleadas y guarda vistas del barrio con una cámara propia:
## <prefijo>_canal.png (orilla y canal principal), _puente.png, _tuberia.png (boca en el acantilado),
## _alto.png (vista general) y _jugador.png (cámara del juego con el jugador en el agua).

var _prefix := "user://district"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "survival"
	_main = (load("res://scenes/core/main_procedural.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	for n in get_tree().root.find_children("*", "", true, false):
		if n is WaveManager:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var map: ProceduralMap = _main.get_node("ProceduralMap")
	var d := map.district
	if d == null:
		push_error("sin barrio")
		get_tree().quit(1)
		return
	var mu: Vector2 = d.local_range(d.canals[0])[0]
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 400.0
	_main.add_child(cam)
	cam.current = true
	# Orilla de dentro mirando a lo largo del canal
	var bv := 0.0
	for br in map.get_bridges():
		if br.get("canal", false):
			bv = d.to_local(br["a"]).y
			break
	var eye := d.to_world(mu.x - 5.0, bv - 22.0)
	var look := d.to_world((mu.x + mu.y) * 0.5, bv + 4.0)
	await _shot(cam, Vector3(eye.x, d.street_y + 3.2, eye.y), Vector3(look.x, d.floor_y, look.y), "_canal")
	# Puente de cerca
	eye = d.to_world(mu.x - 9.0, bv + 7.0)
	look = d.to_world((mu.x + mu.y) * 0.5, bv)
	await _shot(cam, Vector3(eye.x, d.street_y + 2.2, eye.y), Vector3(look.x, d.street_y, look.y), "_puente")
	# Boca de tubería en el acantilado, desde el desagüe
	if not d.pipes.is_empty():
		var pp: Vector3 = d.pipes[0]["pos"]
		var out: Vector3 = d.pipes[0]["dir"]
		var e3 := pp - out * 16.0 + Vector3(0.0, 4.0, 0.0)
		var side := Vector3(out.z, 0.0, -out.x) * 5.0
		await _shot(cam, e3 + side, pp, "_tuberia")
	# Vista alta de todo el barrio
	var c := d.to_world(108.0, 0.0)
	var hi := d.to_world(60.0, -40.0)
	await _shot(cam, Vector3(hi.x, d.street_y + 55.0, hi.y), Vector3(c.x, d.street_y, c.y), "_alto")
	# Historia 009. Compuerta de un desagüe: cerrada (seco) y rota (ola)
	var gate := {}
	for bk in d.breakables:
		if bk["kind"] == "gate":
			gate = bk
			break
	if not gate.is_empty():
		var ci: int = gate["canal"]
		var rg: Array = d.local_range(d.canals[ci])
		var vm := ((rg[1] as Vector2).x + (rg[1] as Vector2).y) * 0.5
		var ge := d.to_world((rg[0] as Vector2).x + 9.0, vm + 7.0)
		var gl := d.to_world((rg[0] as Vector2).x, vm)
		await _shot(cam, Vector3(ge.x, d.street_y + 3.5, ge.y), Vector3(gl.x, d.floor_y + 1.0, gl.y), "_compuerta")
		(gate["node"] as SewerBreakable).take_damage(5000.0, Vector3.FORWARD)
		await get_tree().create_timer(0.7).timeout
		_save("_ola")
	# Muro de ladrillo de través
	for bk in d.breakables:
		if bk["kind"] == "wall":
			var a: Vector3 = bk["a"]
			var b: Vector3 = bk["b"]
			var m := (a + b) * 0.5
			var along := (b - a).normalized()
			var side := Vector3(-along.z, 0.0, along.x)
			await _shot(cam, m + side * 9.0 + along * 4.0 + Vector3(0.0, 3.0, 0.0), m + Vector3(0.0, 1.2, 0.0), "_muro")
			break
	# Árboles dibujados: de cerca, uno talado, cráteres y tinta
	var trees: TreeField = map.trees
	var marks := _main.get_node_or_null("MapMarks") as MapMarks
	var pl := _main.get_node_or_null("Player") as Node3D
	if trees and pl:
		var best := -1
		var bd := INF
		for i in trees.count():
			var dd := trees.tree_position(i).distance_to(pl.global_position)
			if dd < bd and dd > 18.0:
				bd = dd
				best = i
		var tp := trees.tree_position(best)
		var dir := (pl.global_position - tp)
		dir.y = 0.0
		dir = dir.normalized()
		await _shot(cam, tp + dir * 14.0 + Vector3(0.0, 3.5, 0.0), tp + Vector3(0.0, 2.2, 0.0), "_arboles")
		trees.ensure_bodies_near(tp, 1.0)
		trees.body_of(best).take_damage(1000.0, Vector3(dir.z, 0.0, -dir.x))
		if marks:
			marks.add(tp + dir * 4.0 + Vector3(2.0, 0, 0), MapMarks.Kind.CRATER, 3.0)
			for k in 5:
				marks.add(tp + dir * 6.0 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), MapMarks.Kind.INK, 1.5)
		await get_tree().create_timer(0.35).timeout
		_save("_talando")
		await get_tree().create_timer(1.2).timeout
		_save("_talado")
	# Cámara del juego: el jugador dentro del agua
	cam.current = false
	var player := _main.get_node_or_null("Player") as Node3D
	if player:
		var wp := d.to_world((mu.x + mu.y) * 0.5, bv - 10.0)
		player.global_position = Vector3(wp.x, d.floor_y + 0.2, wp.y)
		await get_tree().create_timer(1.5).timeout
		_save("_jugador")
	get_tree().quit()

func _shot(cam: Camera3D, eye: Vector3, target: Vector3, suffix: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	_save(suffix)

func _save(suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_prefix + suffix + ".png")
	print("guardado ", _prefix + suffix + ".png")
