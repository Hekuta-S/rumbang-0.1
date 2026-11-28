extends SceneTree

## Hornea las criaturas de las cloacas (babosa, babosa roja, rata, rata gorda) como SPRITES de tinta para
## Supervivencia: un atlas por criatura con 8 ángulos (filas) y, por columnas, idle, caminar y dos poses
## (anticipación y golpe) por cada ataque. El juego los dibuja como un Sprite3D que mira a la cámara
## (scripts/entities/creature_sprite.gd): en vez de un esqueleto con ~3000 triángulos, 2 triángulos.
##
## Cada celda se renderiza a RENDER px (el doble de CELL) en tres pases: color, normales de cara y profundidad
## (tiras crudas en assets/creatures/raw/, .gdignore). tools/make_enemy_impostors.py les pone la tinta cartoon
## (aristas, solapes y contorno), las reduce, las recorta a la silueta y monta el atlas.
##
## Necesita render (no vale --headless). Uso, desde la carpeta del proyecto:
##   godot --path . -s tools/bake_creature_sprites.gd [clave ...]
##   python tools/make_enemy_impostors.py creatures
##   godot --headless --path . --import
## Escribe res://assets/creatures/<clave>_sprites.json aquí y <clave>_sprites.png en el paso de Python.

const OUT := "res://assets/creatures/"
const DIR := "res://assets/models/entities/enemigos/sewers/"
const CELL := 144                  ## px por celda en el atlas (antes de recortar)
const RENDER := CELL * 2           ## px del render
const RAW := "res://assets/creatures/raw/"
const PASSES := ["color", "normal", "depth"]
const CAM_DIST := 20.0
const DEPTH_NEAR := 17.0          ## m: la profundidad se guarda en [DEPTH_NEAR, DEPTH_NEAR + DEPTH_RANGE]
const DEPTH_RANGE := 6.0
const ANGLES := 8
const ELEVATION_DEG := 20.0
const IDLE_N := 8
const WALK_N := 16
const POSE_N := 3                 ## fotogramas por pose de ataque (anticipación y golpe)
const SELF_LIT := 0.32             ## = DungeonGoblin.SELF_LIT
## clave -> {height: m (la misma que model_height de la clase), idle, walk, attacks: {nombre: [anticipación, golpe]}}
const CREATURES := {
	"slug": {"height": 0.95, "idle": "babosa/slug_idle.fbx", "walk": "babosa/slug_walk.fbx",
		"attacks": {"slam": ["babosa/slug_slam_windup.fbx", "babosa/slug_slam.fbx"],
			"spit": ["babosa/slug_spit_windup.fbx", "babosa/slug_spit.fbx"]}},
	"bloater": {"height": 0.85, "idle": "babosa_roja/bloater_idle.fbx", "walk": "babosa/slug_walk.fbx",
		"attacks": {"burst": ["babosa_roja/bloater_inflate.fbx", "babosa_roja/bloater_burst.fbx"]}},
	"rat": {"height": 0.5, "idle": "rata/rat_idle.fbx", "walk": "rata/rat_walk.fbx",
		"attacks": {"bite": ["rata/rat_bite_windup.fbx", "rata/rat_bite.fbx"],
			"pounce": ["rata/rat_pounce_windup.fbx", "rata/rat_pounce.fbx"]}},
	"rat_big": {"height": 0.85, "idle": "rata/rat_big_idle.fbx", "walk": "rata/rat_walk.fbx",
		"attacks": {"bite": ["rata/rat_bite_windup.fbx", "rata/rat_bite.fbx"],
			"pounce": ["rata/rat_pounce_windup.fbx", "rata/rat_pounce.fbx"]}},
}

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _elev := deg_to_rad(ELEVATION_DEG)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RAW))
	var gi := FileAccess.open(RAW + ".gdignore", FileAccess.WRITE)
	gi.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_main()

func _main() -> void:
	await process_frame
	var only := OS.get_cmdline_user_args()
	for key: String in CREATURES:
		if only.is_empty() or only.has(key):
			await _bake(key, CREATURES[key])
	print("CREATURE_BAKE_DONE")
	quit()

# ───────────────────────────── Escena de render ─────────────────────────────

func _build_scene(cfg: Dictionary) -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RENDER, RENDER)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.74)
	env.ambient_light_energy = 1.0
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
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_load_model(cfg)

## Mismo montaje que DungeonGoblin._build_model: FBX de reposo + clips de otros FBX en su esqueleto.
func _load_model(cfg: Dictionary) -> void:
	_model = (load(DIR + String(cfg["idle"])) as PackedScene).instantiate() as Node3D
	_pivot.add_child(_model)
	var meshes: Array = _model.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		_lift(m as MeshInstance3D)
	# Ajuste de tamaño idéntico a DungeonGoblin._fit_model (escala a model_height, de cara a -Z)
	var first: MeshInstance3D = meshes[0]
	var xf := Transform3D.IDENTITY
	var n: Node = first
	while n != null and n != _model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var aabb := xf * first.mesh.get_aabb()
	var s := float(cfg["height"]) / maxf(aabb.size.y, 0.0001)
	_model.scale = Vector3.ONE * s
	_model.rotation.y = PI
	_model.position.y = -aabb.position.y * s
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := _anim.get_animation_library("")
	var first_name: String = lib.get_animation_list()[0]
	var idle := lib.get_animation(first_name)
	lib.remove_animation(first_name)
	idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle", idle)
	var skel := _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skel_path := _anim.get_node(_anim.root_node).get_path_to(skel)
	var clips: Dictionary = {"walk": String(cfg["walk"])}
	for atk: String in cfg["attacks"]:
		clips[atk + "_w"] = String(cfg["attacks"][atk][0])
		clips[atk + "_a"] = String(cfg["attacks"][atk][1])
	for clip: String in clips:
		var scene := load(DIR + String(clips[clip])) as PackedScene
		var inst := scene.instantiate()
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		inst.free()
		for i in a.get_track_count():
			var bone := a.track_get_path(i).get_concatenated_subnames()
			if bone != "":
				a.track_set_path(i, NodePath(str(skel_path) + ":" + bone))
		a.loop_mode = Animation.LOOP_NONE
		lib.add_animation(clip, a)

## Igual que DungeonGoblin._lift_fbx_materials (no se llama de allí: ese script necesita los autoloads del juego).
func _lift(m: MeshInstance3D) -> void:
	if m.mesh == null:
		return
	for s in m.mesh.get_surface_count():
		var src := m.get_active_material(s) as BaseMaterial3D
		if src == null or src.emission_enabled:
			continue
		var mat := src.duplicate() as BaseMaterial3D
		mat.emission_enabled = true
		mat.emission = src.albedo_color
		mat.emission_texture = src.albedo_texture
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		mat.emission_energy_multiplier = SELF_LIT
		m.set_surface_override_material(s, mat)

# ───────────────────────────── Horneado ─────────────────────────────

## Lista de celdas por columna: [clip, tiempo normalizado 0..1].
func _columns(cfg: Dictionary) -> Array:
	var cols: Array = []
	for i in IDLE_N:
		cols.append(["idle", float(i) / float(IDLE_N)])
	for i in WALK_N:
		cols.append(["walk", float(i) / float(WALK_N)])
	for atk: String in cfg["attacks"]:
		for i in POSE_N:
			cols.append([atk + "_w", lerpf(0.45, 0.98, float(i) / float(POSE_N - 1))])
		for i in POSE_N:
			cols.append([atk + "_a", lerpf(0.2, 0.75, float(i) / float(POSE_N - 1))])
	return cols

func _bake(key: String, cfg: Dictionary) -> void:
	_build_scene(cfg)
	var height := float(cfg["height"])
	var cols := _columns(cfg)
	var yc_base := height * 0.5
	# Pase 0: encuadre holgado para medir lo que ocupan todas las poses
	var span := height * 4.5          # holgado: la cola de la rata se salía del encuadre
	var shift := 0.0
	var imgs := await _render_all(cols, span, yc_base, shift)
	var used := Rect2i()
	for img: Image in imgs:
		var r := img.get_used_rect()
		if r.size.x > 0:
			used = r if used.size.x == 0 else used.merge(r)
	var c := float(RENDER)
	var hx := maxf(absf(float(used.position.x) - c * 0.5), absf(float(used.end.x) - c * 0.5)) / c * span
	var cy := (float(used.position.y) + float(used.end.y)) * 0.5
	var dy := (c * 0.5 - cy) / c * span
	var ext_v := float(used.size.y) / c * span
	var new_span := maxf(2.0 * hx, ext_v) * 1.16   # margen para el contorno de tinta
	# Pase 1: encuadre ajustado; color, normales y profundidad (la tinta la pone make_enemy_impostors.py)
	for p in PASSES.size():
		_set_pass(p)
		await _render_strips(key, PASSES[p], cols, new_span, yc_base, dy)
	_set_pass(0)
	var lens := _clip_lengths(cfg)
	var info := {
		"key": key, "angles": ANGLES, "cell": CELL, "render": RENDER, "depth_range": DEPTH_RANGE, "cols": cols.size(), "height": height,
		"span": new_span, "center_y": yc_base + cos(_elev) * dy,
		"idle": [0, IDLE_N], "walk": [IDLE_N, WALK_N],
		"idle_fps": float(IDLE_N) / maxf(float(lens["idle"]), 0.1),
		"walk_fps": float(WALK_N) / maxf(float(lens["walk"]), 0.1),
		"attacks": {},
	}
	var col := IDLE_N + WALK_N
	for atk: String in cfg["attacks"]:
		info["attacks"][atk] = {"windup": col, "attack": col + POSE_N, "n": POSE_N}
		col += POSE_N * 2
	var f := FileAccess.open(OUT + key + "_sprites.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	print("Horneada ", key, ": ", cols.size(), " columnas, span=", snappedf(new_span, 0.01))
	_vp.queue_free()
	await process_frame

func _clip_lengths(cfg: Dictionary) -> Dictionary:
	return {"idle": _anim.get_animation("idle").length, "walk": _anim.get_animation("walk").length}

## Material de un pase en todas las mallas: 0 color (los suyos), 1 normales de cara, 2 profundidad.
func _set_pass(p: int) -> void:
	var mat: Material = null
	if p > 0:
		var sh := Shader.new()
		if p == 1:
			sh.code = "shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	n *= n.z < 0.0 ? -1.0 : 1.0;
	ALBEDO = n * 0.5 + 0.5;
}
"
		else:
			sh.code = "shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	float d = clamp((-VERTEX.z - %s) / %s, 0.0, 0.9999) * 32.0;
	ALBEDO = vec3(floor(d) / 32.0, fract(d), 0.0);
}
" % [str(DEPTH_NEAR), str(DEPTH_RANGE)]
		var sm := ShaderMaterial.new()
		sm.shader = sh
		mat = sm
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	_vp.msaa_3d = Viewport.MSAA_4X if p == 0 else Viewport.MSAA_DISABLED   # normales y profundidad sin promediar

## Pase 1: renderiza todas las celdas y guarda una tira por ángulo en RAW (<clave>_<pase>_<ángulo>.png).
func _render_strips(key: String, pass_name: String, cols: Array, span: float, yc_base: float, shift: float) -> void:
	_cam.size = span
	var up := Vector3(0.0, cos(_elev), -sin(_elev))
	var target := Vector3(0.0, yc_base, 0.0) + up * shift
	_cam.look_at_from_position(target + Vector3(0.0, sin(_elev), cos(_elev)) * CAM_DIST, target)
	for i in 12:
		await process_frame
	for row in ANGLES:
		_pivot.rotation.y = float(row) * TAU / float(ANGLES)
		var strip := Image.create(cols.size() * RENDER, RENDER, false, Image.FORMAT_RGBA8)
		for col in cols.size():
			var clip: String = cols[col][0]
			var a := _anim.get_animation(clip)
			_anim.play(clip)
			_anim.pause()
			_anim.seek(a.length * float(cols[col][1]), true)
			await process_frame
			await process_frame
			var img := _vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, Rect2i(0, 0, RENDER, RENDER), Vector2i(col * RENDER, 0))
		strip.save_png(ProjectSettings.globalize_path(RAW + "%s_%s_%d.png" % [key, pass_name, row]))

## Renderiza todas las celdas (filas = ángulos, columnas = poses) con el encuadre dado.
func _render_all(cols: Array, span: float, yc_base: float, shift: float) -> Array:
	_cam.size = span
	var up := Vector3(0.0, cos(_elev), -sin(_elev))
	var target := Vector3(0.0, yc_base, 0.0) + up * shift
	_cam.look_at_from_position(target + Vector3(0.0, sin(_elev), cos(_elev)) * 20.0, target)
	for i in 12:
		await process_frame          # los primeros frames del viewport salen a medio cargar
	var out: Array = []
	for row in ANGLES:
		_pivot.rotation.y = float(row) * TAU / float(ANGLES)
		for col in cols.size():
			var clip: String = cols[col][0]
			var a := _anim.get_animation(clip)
			_anim.play(clip)
			_anim.pause()
			_anim.seek(a.length * float(cols[col][1]), true)
			await process_frame
			await process_frame
			var img := _vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			out.append(img)
	return out
