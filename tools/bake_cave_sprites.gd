extends SceneTree

## Hornea las rocas y los adornos de las Cavernas como dibujos 2D (DungeonMap._build_cave_sprites).
## Paso 1 de 2: renderiza cada pieza desde ANGLES ángulos alrededor del eje vertical, en pases sin luz:
##   - color (su material sin iluminar)
##   - normales en espacio de vista (para el sombreado cel y la tinta interior)
##   - brillo (solo hojas con glow: manchas de los hongos)
## y escribe tiras crudas en assets/textures/toon/props/cave_raw/ (.gdignore) más <hoja>_meta.json.
## Paso 2: tools/make_cave_sprites.py (numpy) sombrea, entinta, reduce y monta <hoja>.png/.json.
##
## Los .glb de origen de las piezas que ya solo se ven como dibujo están FUERA del juego, en
## blender_sources/cave_sprite_sources/ (se cargan aquí con GLTFDocument); el resto sale de assets/models/mapa/.
##
## Necesita render (no vale --headless). Uso, desde la carpeta del proyecto:
##   godot --path . -s tools/bake_cave_sprites.gd
##   python tools/make_cave_sprites.py
##   godot --headless --path . --import

const RAW := "res://assets/textures/toon/props/cave_raw/"
const PROP_DIR := "res://assets/models/mapa/"
const SOURCE_DIR := "res://blender_sources/cave_sprite_sources/"
const TEX_DIR := "res://assets/textures/dungeon/"
const ROCK_TEX := "cave_toon"                  ## = DungeonMap.ROCK_TEX
const MUSH_TEX_DIR := "res://assets/textures/mushrooms/"
const CELL := 512                              ## se reduce a la mitad en make_cave_sprites.py
const ANGLES := 8
const ELEV_FLOOR := 18.0                       ## grados: la cámara del juego mira algo desde arriba
const ELEV_CEIL := -14.0                       ## estalactitas: se ven desde abajo
const ELEV_WALL := 6.0                         ## antorchas de pared: a la altura de los ojos
## hoja -> {tipo: [archivo, material]}; el orden es la fila del atlas.
## material: "pack" (roca de las paredes), "toon" (textura cartoon horneada), "toon_noflame" (ídem sin las superficies emisivas: la llama la pone fire_flame en el juego),
## "mush" (hongos, con pase de brillo), "glb" (los materiales del propio .glb)
const SHEETS := {
	"cave_rocks": {
		"stalactite_a": ["cave_stalactite_a", "pack"], "stalactite_b": ["cave_stalactite_b", "pack"],
		"stalactite_c": ["cave_stalactite_c", "pack"], "stalagmite_d": ["cave_stalagmite_d", "pack"],
		"cave_pillar": ["cave_pillar", "pack"], "cave_rock_01": ["cave_rock_01", "pack"],
		"cave_rock_04": ["cave_rock_04", "pack"], "cave_cliff_a": ["cave_cliff_a", "pack"],
		"cave_cliff_b": ["cave_cliff_b", "pack"], "cave_cliff_c": ["cave_cliff_c", "pack"],
		"cave_cliff_d": ["cave_cliff_d", "pack"], "rock_a": ["rock_a", "toon"],
	},
	"cave_decor": {
		"mush_big": ["mushroom_big", "mush"], "mush_small": ["mushroom_small", "mush"],
		"mush_cups": ["mushroom_cups", "mush"], "torch_wall": ["torch_wall", "glb"],
		"brazier_pillar": ["brazier_pillar", "glb"], "brazier": ["brazier", "toon_noflame"],
	},
}

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _mi: MeshInstance3D
var _mats: Dictionary = {}
var _normal_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _black_mat: StandardMaterial3D
var _hide_mat: ShaderMaterial

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RAW))
	var gi := FileAccess.open(RAW + ".gdignore", FileAccess.WRITE)
	gi.close()
	_main()

func _main() -> void:
	_build_scene()
	await process_frame
	var only := OS.get_cmdline_user_args()
	for sheet: String in SHEETS:
		if not only.is_empty() and not only.has(sheet):
			continue
		var kinds: Dictionary = SHEETS[sheet]
		var glow := false
		for kind: String in kinds:
			glow = glow or String(kinds[kind][1]) in ["mush", "glb"]
		var meta := {"cell": CELL, "angles": ANGLES, "glow": glow, "kinds": []}
		for kind: String in kinds:
			var info := await _bake(kind, String(kinds[kind][0]), String(kinds[kind][1]), glow)
			if not info.is_empty():
				(meta["kinds"] as Array).append(info)
		var f := FileAccess.open(RAW + sheet + "_meta.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(meta, "\t"))
		f.close()
	print("CAVE_BAKE_DONE")
	quit()

func _build_scene() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL, CELL)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED        # sin bordes a medias: las normales no se pueden promediar
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_mi = MeshInstance3D.new()
	_pivot.add_child(_mi)
	var ns := Shader.new()
	ns.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { ALBEDO = (FRONT_FACING ? NORMAL : -NORMAL) * 0.5 + 0.5; }\n"
	_normal_mat = ShaderMaterial.new()
	_normal_mat.shader = ns
	var gs := Shader.new()
	gs.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform sampler2D glow_tex : hint_default_black;\nvoid fragment() { ALBEDO = vec3(texture(glow_tex, UV).r); }\n"
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = gs
	_glow_mat.set_shader_parameter("glow_tex", load(MUSH_TEX_DIR + "mushroom_glow.png"))
	_black_mat = StandardMaterial3D.new()
	_black_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_black_mat.albedo_color = Color.BLACK
	_black_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hs := Shader.new()
	hs.code = "shader_type spatial;
render_mode unshaded;
void fragment() { discard; }
"
	_hide_mat = ShaderMaterial.new()
	_hide_mat.shader = hs

## El shader de un material, sin luz (para leer solo el color).
func _unshaded(src: Shader) -> Shader:
	var s := Shader.new()
	var code := src.code
	if code.contains("render_mode "):
		code = code.replace("render_mode ", "render_mode unshaded, cull_disabled, ")
	else:
		code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode unshaded, cull_disabled;")
	s.code = code
	return s

func _shader_material(mode: String, file: String) -> Material:
	var key := mode + "|" + file if mode.begins_with("toon") else mode
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	match mode:
		"pack":
			# = DungeonMap.pack_rock_material, con tinte neutro (el del nivel lo pone el shader del dibujo)
			mat.shader = _unshaded(load("res://assets/shaders/cave_rock.gdshader"))
			mat.set_shader_parameter("albedo_tex", load(TEX_DIR + ROCK_TEX + "_albedo.png"))
			mat.set_shader_parameter("normal_tex", load(TEX_DIR + ROCK_TEX + "_normal.png"))
			mat.set_shader_parameter("tile_m", 6.0)
			mat.set_shader_parameter("tint_gain", 1.6)
			mat.set_shader_parameter("top_light_h", 1000.0)
			mat.set_shader_parameter("use_vertex_color", false)
			mat.set_shader_parameter("base_dark_h", 0.3)
			mat.set_shader_parameter("use_normal_map", false)
		"mush":
			# = DungeonMap.mushroom_material, quieto (sin balanceo: lo pone el shader del dibujo)
			mat.shader = _unshaded(load("res://assets/shaders/mushroom_glow.gdshader"))
			mat.set_shader_parameter("albedo_tex", load(MUSH_TEX_DIR + "mushroom_albedo.png"))
			mat.set_shader_parameter("use_normal_map", false)
			mat.set_shader_parameter("sway_amount", 0.0)
		_:
			# = ProceduralMap.toon_prop_material
			mat.shader = _unshaded(load("res://assets/shaders/prop_toon.gdshader"))
			mat.set_shader_parameter("toon_tex", load("res://assets/textures/toon/props/" + file + ".png"))
			# sin color de vértice COLOR.a vale 1 y hide_emissive lo borraría todo: la llama se quita por superficie
			mat.set_shader_parameter("hide_emissive", false)
	_mats[key] = mat
	return mat

## Carga el .glb: de la carpeta de fuentes (fuera del juego) o de assets/models/mapa/.
func _scene_root(file: String) -> Node:
	var src := ProjectSettings.globalize_path(SOURCE_DIR + file + ".glb")
	if FileAccess.file_exists(src):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(src, state) == OK:
			return doc.generate_scene(state)
	var path := PROP_DIR + file + ".glb"
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	return null

## Malla y transformada del primer MeshInstance3D del .glb (= DungeonMap._load_textured).
func _load(file: String) -> Array:
	var root_n := _scene_root(file)
	if root_n == null:
		return []
	var found: MeshInstance3D = null
	for n in root_n.find_children("*", "MeshInstance3D", true, false):
		found = n
		break
	if found == null:
		root_n.free()
		return []
	var xf := Transform3D.IDENTITY
	var n: Node = found
	while n and n != root_n:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var mesh := found.mesh
	root_n.free()
	return [mesh, xf]

## Materiales por superficie para un pase: 0 color, 1 normales, 2 brillo.
func _set_pass(mesh: Mesh, mode: String, file: String, pass_i: int) -> void:
	_mi.material_override = null
	for s in mesh.get_surface_count():
		_mi.set_surface_override_material(s, null)
	if mode == "toon_noflame":
		# superficie a superficie: las emisivas (llama) no se dibujan en ningún pase
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			var hide := src != null and src.emission_enabled
			var m: Material = _hide_mat if hide else ([_shader_material(mode, file), _normal_mat, _black_mat][pass_i] as Material)
			_mi.set_surface_override_material(s, m)
		return
	if pass_i == 1:
		_mi.material_override = _normal_mat
		return
	if mode == "glb":
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			var m: BaseMaterial3D
			if src == null:
				m = StandardMaterial3D.new()
			else:
				m = src.duplicate() as BaseMaterial3D
			if pass_i == 2:
				# solo las partes emisivas (brasas, metal al rojo) brillan
				var lit := src != null and src.emission_enabled
				m = StandardMaterial3D.new()
				m.albedo_color = Color.WHITE if lit else Color.BLACK
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mi.set_surface_override_material(s, m)
		return
	if pass_i == 2:
		_mi.material_override = _glow_mat if mode == "mush" else _black_mat
		return
	_mi.material_override = _shader_material(mode, file)

func _bake(kind: String, file: String, mode: String, glow: bool) -> Dictionary:
	var got := _load(file)
	if got.is_empty():
		push_warning("Sin malla: " + file)
		return {}
	var mesh: Mesh = got[0]
	var xf: Transform3D = got[1]
	_mi.mesh = mesh
	_mi.transform = xf
	var elev_deg := ELEV_FLOOR
	if kind.begins_with("stalactite"):
		elev_deg = ELEV_CEIL
	elif kind == "torch_wall":
		elev_deg = ELEV_WALL
	var elev := deg_to_rad(elev_deg)
	var fwd := Vector3(0.0, -sin(elev), -cos(elev))          # la cámara mira hacia -Z desde +Z
	var up := Vector3(0.0, cos(elev), -sin(elev))
	var right := Vector3.RIGHT
	# Encuadre común a todos los ángulos (el origen cae en el mismo píxel en todos)
	var aabb := xf * mesh.get_aabb()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in ANGLES:
		var rb := Basis(Vector3.UP, float(row) * TAU / float(ANGLES))
		for k in 8:
			var p := rb * aabb.get_endpoint(k)
			var s := Vector2(p.dot(right), p.dot(up))
			lo = lo.min(s)
			hi = hi.max(s)
	var center := (lo + hi) * 0.5
	var span := maxf(hi.x - lo.x, hi.y - lo.y) * 1.08
	var target := right * center.x + up * center.y
	_cam.size = span
	_cam.look_at_from_position(target - fwd * 60.0, target, up)
	var names := ["color", "normal", "glow"]
	for pass_i in (3 if glow else 2):
		_set_pass(mesh, mode, file, pass_i)
		for i in 6:
			await process_frame                  # el viewport tarda unos frames en tener el material listo
		var strip := Image.create(CELL * ANGLES, CELL, false, Image.FORMAT_RGBA8)
		for row in ANGLES:
			_pivot.rotation.y = float(row) * TAU / float(ANGLES)
			await process_frame
			await process_frame
			var img := _vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(row * CELL, 0))
		strip.save_png(ProjectSettings.globalize_path(RAW + kind + "_" + names[pass_i] + ".png"))
	# Píxel del origen del modelo (pie / base de la estalactita / pared de la antorcha) en la celda, normalizado
	var u0 := 0.5 + (0.0 - center.x) / span
	var v0 := 0.5 - (0.0 - center.y) / span
	print("Horneada ", kind, ": span=", snappedf(span, 0.01), " origen=", Vector2(u0, v0))
	return {"kind": kind, "span": span, "u0": u0, "v0": v0, "elev": elev_deg}
