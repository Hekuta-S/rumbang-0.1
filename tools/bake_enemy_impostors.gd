extends SceneTree

## Hornea los IMPOSTORES de los enemigos (los sprites 2D de móvil, ver EnemyVisuals): el modelo 3D visto desde
## ANGLES ángulos y en todos los fotogramas de idle (IDLE_SPRITES) y de caminar (los horneados en el VAT).
## Paso 1 de 2. Por cada celda renderiza a RENDER px tres pases:
##   - color: el modelo iluminado (ambiente + luz direccional + borde de luz), como hasta ahora
##   - normales de cara (dFdx/dFdy de la posición: el VAT no anima las normales) → tinta en las aristas
##   - profundidad (dos canales) → tinta donde una parte tapa a otra (brazo delante del cuerpo...)
## y escribe tiras crudas en assets/vat/raw/ (.gdignore): <clave>_<pase>_<ángulo>.png + <clave>_raw.json.
## Paso 2: tools/make_enemy_impostors.py entinta, reduce, recorta y monta <clave>_impostor.png/.json.
## Se apoya en lo horneado por tools/bake_enemy_vat.gd (hay que ejecutar ese primero).
##
## Necesita render (no vale --headless). Uso, desde la carpeta del proyecto:
##   godot --path . -s tools/bake_enemy_impostors.gd [clave ...]
##   python tools/make_enemy_impostors.py
##   godot --headless --path . --import

const OUT := "res://assets/vat/"
const RAW := "res://assets/vat/raw/"
const SHADER: Shader = preload("res://assets/shaders/enemy_vat.gdshader")
const KEYS := ["magoblin", "normal", "bruto", "zombie"]
const TEXTURES := {
	"magoblin": "res://assets/textures/enemigos/textura_mago_goblin.png",
	"normal": "res://assets/textures/enemigos/texture_normal_goblin.png",
	"bruto": "res://assets/textures/enemigos/textura_goblin_bruto.png",
	"zombie": "res://assets/textures/enemigos/textura_zombie_goblin.png",
}
const ANGLES := 8                 ## vistas alrededor del enemigo
const RENDER := 512               ## px del render (make_enemy_impostors.py lo reduce a la mitad)
const IDLE_SPRITES := 8           ## fotogramas de idle guardados (de los horneados)
const WALK_SPRITES_MAX := 24      ## máximo de fotogramas de caminar guardados (normalmente todos)
## Elevación de la cámara de juego (grados sobre el horizonte; el brazo de cámara del jugador está a 20°).
const ELEVATION_DEG := 20.0
const CAM_DIST := 20.0
const DEPTH_NEAR := 17.0          ## m: la profundidad se guarda en [DEPTH_NEAR, DEPTH_NEAR + DEPTH_RANGE]
const DEPTH_RANGE := 6.0
const PASSES := ["color", "normal", "depth"]

var _vp: SubViewport
var _cam: Camera3D
var _mmi: MultiMeshInstance3D
var _mats: Array[ShaderMaterial] = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RAW))
	var gi := FileAccess.open(RAW + ".gdignore", FileAccess.WRITE)
	gi.close()
	_main()

func _main() -> void:
	await process_frame
	var only := OS.get_cmdline_user_args()
	for key: String in KEYS:
		if only.is_empty() or only.has(key):
			await _bake(key)
	print("IMPOSTOR_BAKE_DONE")
	quit()

## Shader del VAT con otro fragment() (normales o profundidad), sin luz.
func _variant(fragment: String) -> Shader:
	var code := SHADER.code
	code = code.replace("render_mode cull_disabled;", "render_mode unshaded, cull_disabled;")
	code = code.substr(0, code.find("void fragment()")) + fragment
	var s := Shader.new()
	s.code = code
	return s

func _build(key: String, meta: Dictionary) -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RENDER, RENDER)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.97, 0.92)
	_vp.add_child(light)
	light.look_at_from_position(Vector3(-2.0, 4.0, 3.0), Vector3.ZERO)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 60.0
	_vp.add_child(_cam)
	var vmin: Array = meta["vmin"]
	var vsize: Array = meta["vsize"]
	var normal_sh := _variant("void fragment() {\n\tvec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));\n\tn *= n.z < 0.0 ? -1.0 : 1.0;\n\tALBEDO = n * 0.5 + 0.5;\n}\n")
	var depth_sh := _variant("void fragment() {\n\tfloat d = clamp((-VERTEX.z - %s) / %s, 0.0, 0.9999) * 32.0;\n\tALBEDO = vec3(floor(d) / 32.0, fract(d), 0.0);\n}\n" % [str(DEPTH_NEAR), str(DEPTH_RANGE)])
	_mats.clear()
	for sh: Shader in [SHADER, normal_sh, depth_sh]:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("albedo_tex", load(TEXTURES[key]))
		mat.set_shader_parameter("vat_idle", load(OUT + key + "_idle.res"))
		mat.set_shader_parameter("vat_walk", load(OUT + key + "_walk.res"))
		mat.set_shader_parameter("tex_w", int(meta["tex_w"]))
		mat.set_shader_parameter("rows", int(meta["rows"]))
		mat.set_shader_parameter("pos_min", Vector3(vmin[0], vmin[1], vmin[2]))
		mat.set_shader_parameter("pos_size", Vector3(vsize[0], vsize[1], vsize[2]))
		mat.set_shader_parameter("idle_frames", int(meta["idle_frames"]))
		mat.set_shader_parameter("idle_fps", float(meta["idle_fps"]))
		mat.set_shader_parameter("walk_frames", int(meta["walk_frames"]))
		mat.set_shader_parameter("walk_fps", float(meta["walk_fps"]))
		_mats.append(mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = load(OUT + key + "_mesh.res")
	mm.instance_count = 1
	mm.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_vp.add_child(_mmi)

func _bake(key: String) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + key + "_meta.json"))
	var walk_n := mini(int(meta["walk_frames"]), WALK_SPRITES_MAX)
	var cols := IDLE_SPRITES + walk_n
	var vmin: Array = meta["vmin"]
	var vsize: Array = meta["vsize"]
	var radius := Vector2(maxf(absf(vmin[0]), absf(vmin[0] + vsize[0])), maxf(absf(vmin[2]), absf(vmin[2] + vsize[2]))).length()
	var e := deg_to_rad(ELEVATION_DEG)
	var height: float = vsize[1]
	var yc: float = float(vmin[1]) + height * 0.5
	# Encuadre holgado: el recorte ajustado lo hace make_enemy_impostors.py con los píxeles de todas las celdas
	var span := maxf(height * cos(e) + 2.0 * radius * sin(e), 2.0 * radius) * 1.1
	_build(key, meta)
	_cam.size = span
	var up := Vector3(0.0, cos(e), -sin(e))
	var target := Vector3(0.0, yc, 0.0)
	_cam.look_at_from_position(target + Vector3(0.0, sin(e), cos(e)) * CAM_DIST, target, up)
	print("Horneando impostor: ", key, " celdas=", ANGLES * cols, " span=", snappedf(span, 0.01))
	for p in PASSES.size():
		_mmi.material_override = _mats[p]
		_vp.msaa_3d = Viewport.MSAA_4X if p == 0 else Viewport.MSAA_DISABLED   # normales y profundidad sin promediar
		for i in 20:
			await process_frame          # los primeros frames del viewport salen a medio cargar
		for row in ANGLES:
			var strip := Image.create(cols * RENDER, RENDER, false, Image.FORMAT_RGBA8)
			for col in cols:
				_pose(meta, row, col, walk_n)
				await process_frame
				await process_frame
				var img := _vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				strip.blit_rect(img, Rect2i(0, 0, RENDER, RENDER), Vector2i(col * RENDER, 0))
			strip.save_png(ProjectSettings.globalize_path(RAW + "%s_%s_%d.png" % [key, PASSES[p], row]))
	var info := {
		"key": key, "angles": ANGLES, "render": RENDER, "cols": cols,
		"idle_sprites": IDLE_SPRITES, "walk_sprites": walk_n,
		"idle_fps": float(meta["idle_fps"]) * float(IDLE_SPRITES) / float(meta["idle_frames"]),
		"walk_fps": float(meta["walk_fps"]) * float(walk_n) / float(meta["walk_frames"]),
		"span": span, "center_y": yc, "elevation_deg": ELEVATION_DEG, "depth_range": DEPTH_RANGE,
	}
	var f := FileAccess.open(RAW + key + "_raw.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	_vp.queue_free()
	_vp = null
	await process_frame

## Fotograma de una celda: fila = ángulo, columna = idle (IDLE_SPRITES) y luego caminar.
func _pose(meta: Dictionary, row: int, col: int, walk_n: int) -> void:
	var theta := float(row) * TAU / float(ANGLES)
	var walking := col >= IDLE_SPRITES
	var t := 0.0
	if walking:
		var f := float(col - IDLE_SPRITES) * float(meta["walk_frames"]) / float(walk_n)
		t = (f + 0.01) / float(meta["walk_fps"])
	else:
		var f := float(col) * float(meta["idle_frames"]) / float(IDLE_SPRITES)
		t = (f + 0.01) / float(meta["idle_fps"])
	var mm := _mmi.multimesh
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, theta), Vector3.ZERO))
	mm.set_instance_custom_data(0, Color(t, 1.0 if walking else 0.0, 0.0, 0.0))
