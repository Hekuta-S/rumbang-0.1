extends Node

## Renderiza las armas del yunque que no tienen icono (espadón, espada, arco) con fondo transparente:
##   res://tests/shot_weapon_icons.tscn -- <carpeta>
## Guarda <carpeta>/<nombre>_raw.png (512×512, arma en diagonal). Luego se compone sobre el marco
## vacío assets/ui/ingame_hub/armas/_marco.png (648×648): arma escalada a 560 px y pegada en (44, 44).

const SIZE := 512

var _dir := "user://"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0].trim_suffix("/") + "/"
	_run.call_deferred()

func _run() -> void:
	var jobs := {
		"espadon": func(): return GreatswordModels.build(GameData.greatsword_skin),
		"espada": func(): return SwordModels.build(GameData.sword_skin),
		"arco": func(): return BowModels.build(GameData.bow_skin),
	}
	var yaw := {"espadon": 18.0, "espada": 18.0, "arco": 90.0}   # el arco de frente, para que se vea la curva
	for n in jobs:
		await _render(String(n), (jobs[n] as Callable).call(), float(yaw[n]))
	get_tree().quit(0)

func _render(n: String, m: Node3D, yaw: float) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.78)
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color(0.55, 1.0, 0.75)
	rim.light_energy = 0.8
	vp.add_child(rim)
	var holder := Node3D.new()
	vp.add_child(holder)
	holder.add_child(m)
	_fit(m)
	holder.rotation.z = deg_to_rad(-45.0)       # en diagonal, como los iconos de dagas y maza
	holder.rotation.y = deg_to_rad(yaw)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.12
	cam.position = Vector3(0, 0, 4)
	vp.add_child(cam)
	for i in 6:
		await RenderingServer.frame_post_draw
	var path := _dir + n + "_raw.png"
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	vp.queue_free()

## Lado más largo en vertical, mide 1 y centrado en el origen.
func _fit(m: Node3D) -> void:
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).get_aabb()
		b = (m.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * b
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		return
	var axis := 1
	if aabb.size.x > aabb.size[axis]:
		axis = 0
	if aabb.size.z > aabb.size[axis]:
		axis = 2
	m.scale = Vector3.ONE / maxf(aabb.size[axis], 0.001)
	if axis == 0:
		m.rotation.z = PI / 2
	elif axis == 2:
		m.rotation.x = PI / 2
	m.position = -(m.basis * aabb.get_center())
