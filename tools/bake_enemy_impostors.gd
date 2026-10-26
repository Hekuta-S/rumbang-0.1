extends SceneTree

## Hornea los IMPOSTORES de los enemigos: un atlas de imágenes (sprites) del modelo 3D visto desde varios
## ángulos y en varios fotogramas de animación. El juego los dibuja como un cuadrado que mira a la cámara
## y elige la celda según el ángulo, así cada enemigo cuesta 2 triángulos en vez de ~4500.
## Se apoya en lo ya horneado por tools/bake_enemy_vat.gd (hay que ejecutar ese primero).
##
## Por cada modelo genera en res://assets/vat/:
##   <clave>_impostor.png    atlas: una fila por ángulo, columnas = fotogramas de idle y luego de caminar
##   <clave>_impostor.json   rejilla, fps y tamaño del cuadrado en el mundo (ver EnemyVisuals)
##
## Necesita render (no vale --headless). Uso, desde la carpeta del proyecto:
##   godot --path . -s tools/bake_enemy_impostors.gd

const OUT := "res://assets/vat/"
const SHADER: Shader = preload("res://assets/shaders/enemy_vat.gdshader")
const KEYS := ["magoblin", "normal", "bruto", "zombie"]
const TEXTURES := {
	"magoblin": "res://assets/textures/enemigos/textura_mago_goblin.png",
	"normal": "res://assets/textures/enemigos/texture_normal_goblin.png",
	"bruto": "res://assets/textures/enemigos/textura_goblin_bruto.png",
	"zombie": "res://assets/textures/enemigos/textura_zombie_goblin.png",
}
const ANGLES := 8                 ## vistas alrededor del enemigo
const CELL := 128                 ## píxeles por celda
const IDLE_SPRITES := 6           ## fotogramas de idle guardados (de los horneados)
const WALK_SPRITES_MAX := 16      ## máximo de fotogramas de caminar guardados
## Elevación de la cámara de juego (grados sobre el horizonte; el brazo de cámara del jugador está a 20°).
const ELEVATION_DEG := 20.0

var _key_i := 0
var _cell_i := 0
var _phase := 0
var _vp: SubViewport
var _mmi: MultiMeshInstance3D
var _atlas: Image
var _meta: Dictionary = {}
var _info: Dictionary = {}
var _cols := 0
var _walk_n := 0
var _cam: Camera3D
var _pass := 0                    ## 0 = encuadre holgado (mide), 1 = encuadre ajustado (definitivo)
var _warm := 0
var _used := Rect2i()
var _elev := 0.0
var _yc_base := 0.0
var _shift := 0.0                 ## desplazamiento vertical del centro de la imagen (m en pantalla)
const WARM_FRAMES := 20

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _process(_delta: float) -> bool:
	if _key_i >= KEYS.size():
		print("IMPOSTOR_BAKE_DONE")
		quit()
		return false
	if _vp == null:
		_begin_model(KEYS[_key_i])
		return false
	if _warm > 0:
		_warm -= 1          # los primeros frames del viewport salen a medio cargar
		return false
	var total := ANGLES * _cols
	match _phase:
		0:
			_pose(_cell_i)
			_phase = 1
		1:
			_phase = 2          # un frame para que se dibuje
		2:
			_capture(_cell_i)
			_cell_i += 1
			_phase = 0
			if _cell_i >= total:
				if _pass == 0:
					_refine()
				else:
					_finish_model(KEYS[_key_i])
					_key_i += 1
	return false

func _begin_model(key: String) -> void:
	_meta = JSON.parse_string(FileAccess.get_file_as_string(OUT + key + "_meta.json"))
	_walk_n = mini(int(_meta["walk_frames"]), WALK_SPRITES_MAX)
	_cols = IDLE_SPRITES + _walk_n
	var vmin: Array = _meta["vmin"]
	var vsize: Array = _meta["vsize"]
	var rx := maxf(absf(vmin[0]), absf(vmin[0] + vsize[0]))
	var rz := maxf(absf(vmin[2]), absf(vmin[2] + vsize[2]))
	var radius := Vector2(rx, rz).length()
	var e := deg_to_rad(ELEVATION_DEG)
	var height: float = vsize[1]
	var yc: float = float(vmin[1]) + height * 0.5
	var span := maxf(height * cos(e) + 2.0 * radius * sin(e), 2.0 * radius) * 1.08
	_info = {"span": span, "yc": yc, "quad_h": span / cos(e)}
	_elev = e
	_yc_base = yc
	_shift = 0.0
	_pass = 0
	_used = Rect2i()

	_atlas = Image.create(_cols * CELL, ANGLES * CELL, false, Image.FORMAT_RGBA8)
	_atlas.fill(Color(0, 0, 0, 0))

	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL, CELL)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.97, 0.92)
	_vp.add_child(light)
	light.look_at_from_position(Vector3(-2.0, 4.0, 3.0), Vector3.ZERO)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.near = 0.05
	cam.far = 60.0
	_vp.add_child(cam)
	_cam = cam
	_place_camera()

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", load(TEXTURES[key]))
	mat.set_shader_parameter("vat_idle", load(OUT + key + "_idle.res"))
	mat.set_shader_parameter("vat_walk", load(OUT + key + "_walk.res"))
	mat.set_shader_parameter("tex_w", int(_meta["tex_w"]))
	mat.set_shader_parameter("rows", int(_meta["rows"]))
	mat.set_shader_parameter("pos_min", Vector3(vmin[0], vmin[1], vmin[2]))
	mat.set_shader_parameter("pos_size", Vector3(vsize[0], vsize[1], vsize[2]))
	mat.set_shader_parameter("idle_frames", int(_meta["idle_frames"]))
	mat.set_shader_parameter("idle_fps", float(_meta["idle_fps"]))
	mat.set_shader_parameter("walk_frames", int(_meta["walk_frames"]))
	mat.set_shader_parameter("walk_fps", float(_meta["walk_fps"]))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = load(OUT + key + "_mesh.res")
	mm.instance_count = 1
	mm.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = mat
	_vp.add_child(_mmi)
	_cell_i = 0
	_phase = 0
	_warm = WARM_FRAMES
	print("Horneando impostor: ", key, " celdas=", ANGLES * _cols, " span=", snappedf(span, 0.01))

func _place_camera() -> void:
	var up := Vector3(0.0, cos(_elev), -sin(_elev))
	var target := Vector3(0.0, _yc_base, 0.0) + up * _shift
	_cam.size = _info["span"]
	_cam.look_at_from_position(target + Vector3(0.0, sin(_elev), cos(_elev)) * 20.0, target)

## Con el rectángulo que ocupan TODOS los sprites del primer pase, centra y ajusta el encuadre
## (más píxeles por modelo) y repite el horneado.
func _refine() -> void:
	var span: float = _info["span"]
	var c := float(CELL)
	var hx := maxf(absf(float(_used.position.x) - c * 0.5), absf(float(_used.end.x) - c * 0.5)) / c * span
	var cy := (float(_used.position.y) + float(_used.end.y)) * 0.5
	var dy := (c * 0.5 - cy) / c * span
	var ext_v := float(_used.size.y) / c * span
	var new_span := maxf(2.0 * hx, ext_v) * 1.06
	_shift = dy
	_info["span"] = new_span
	_info["quad_h"] = new_span / cos(_elev)
	_info["yc"] = _yc_base + dy / cos(_elev)
	_place_camera()
	_atlas.fill(Color(0, 0, 0, 0))
	_pass = 1
	_cell_i = 0
	_phase = 0
	_warm = WARM_FRAMES
	print("  encuadre ajustado: span=", snappedf(new_span, 0.01), " centro_y=", snappedf(float(_info["yc"]), 0.01))

func _cell_rc(i: int) -> Vector2i:
	return Vector2i(i % _cols, i / _cols)      # (columna = fotograma, fila = ángulo)

func _pose(i: int) -> void:
	var rc := _cell_rc(i)
	var theta := float(rc.y) * TAU / float(ANGLES)
	var walking := rc.x >= IDLE_SPRITES
	var t := 0.0
	if walking:
		var f := float(rc.x - IDLE_SPRITES) * float(_meta["walk_frames"]) / float(_walk_n)
		t = (f + 0.01) / float(_meta["walk_fps"])
	else:
		var f := float(rc.x) * float(_meta["idle_frames"]) / float(IDLE_SPRITES)
		t = (f + 0.01) / float(_meta["idle_fps"])
	var mm := _mmi.multimesh
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, theta), Vector3.ZERO))
	mm.set_instance_custom_data(0, Color(t, 1.0 if walking else 0.0, 0.0, 0.0))

func _capture(i: int) -> void:
	var rc := _cell_rc(i)
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if _pass == 0:
		var r := img.get_used_rect()
		if r.size.x > 0:
			_used = r if _used.size.x == 0 else _used.merge(r)
	_atlas.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(rc.x * CELL, rc.y * CELL))

func _finish_model(key: String) -> void:
	_atlas.save_png(ProjectSettings.globalize_path(OUT + key + "_impostor.png"))
	var info := {
		"angles": ANGLES,
		"cell": CELL,
		"cols": _cols,
		"idle_sprites": IDLE_SPRITES,
		"walk_sprites": _walk_n,
		"idle_fps": float(_meta["idle_fps"]) * float(IDLE_SPRITES) / float(_meta["idle_frames"]),
		"walk_fps": float(_meta["walk_fps"]) * float(_walk_n) / float(_meta["walk_frames"]),
		"quad_w": _info["span"],
		"quad_h": _info["quad_h"],
		"center_y": _info["yc"],
		"elevation_deg": ELEVATION_DEG,
	}
	var f := FileAccess.open(OUT + key + "_impostor.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	_vp.queue_free()
	_vp = null
	_mmi = null
	print("  guardado ", key, "_impostor.png")
