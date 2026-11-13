extends Node

## Editor visual de ROPA: coloca camisas, pantalones, zapatos… (assets/models/riva/ropa/*.glb) sobre el cuerpo de
## Riva, que se muestra en pose T con los brazos ajustables. Abrir tools/clothing_editor.tscn con F6 (ventana normal,
## no headless). Guardar escribe resources/clothing_fit.json (formato y uso en ClothingFit).
##
## Vista (como un editor 3D): clic derecho + arrastrar = orbitar · botón central (o Mayús + clic derecho) = desplazar ·
## rueda = zoom · F = centrar en la prenda · 1 / 3 / 7 = frente / lado / arriba.
## Gizmo sobre la prenda seleccionada: W = mover, E = rotar, R = escalar (ejes: flechas / anillos / cubos; el centro
## mueve en el plano de la pantalla o escala por igual). X = ejes locales / globales. Ctrl (o la casilla Imán) = saltos
## de 2 cm, 5° y 0,05. Clic en una prenda = seleccionarla. Ctrl+Z / Ctrl+Y = deshacer / rehacer. Ctrl+S = guardar.

const MODEL_PATH := "res://assets/models/riva/riva-base.fbx"
const STATE_PATH := "res://resources/clothing_editor_state.json"
const SIDEBAR_W := 360.0
const UI_MARGIN := 12.0
const GIZMO_K := 0.11        ## tamaño del gizmo = distancia a la cámara × GIZMO_K (así mide siempre lo mismo en pantalla)
const PICK_PX := 12.0
const SNAP_MOVE := 0.02
const SNAP_ROT := 5.0
const SNAP_SCALE := 0.05
const ARM_MIN := -90.0
const ARM_MAX := 90.0
const LEG_MIN := -30.0
const LEG_MAX := 90.0

const MODE_MOVE := 0
const MODE_ROTATE := 1
const MODE_SCALE := 2
const MODE_NAMES := ["Mover  (W)", "Rotar  (E)", "Escalar  (R)"]

const C_ACCENT := Color(0.95, 0.55, 0.22)
const C_PANEL := Color(0.075, 0.08, 0.1, 0.94)
const C_FIELD := Color(0.13, 0.14, 0.17)
const C_BTN := Color(0.17, 0.18, 0.22)
const C_BTN_HOVER := Color(0.23, 0.245, 0.3)
const C_TEXT_DIM := Color(1, 1, 1, 0.55)
const C_OK := Color(0.45, 0.85, 0.5)
const C_WARN := Color(1.0, 0.75, 0.3)
const C_ERR := Color(1.0, 0.4, 0.38)
const AXIS_COLORS := [Color(0.95, 0.3, 0.3), Color(0.45, 0.85, 0.3), Color(0.3, 0.55, 1.0)]
const C_CENTER := Color(0.92, 0.92, 0.95)

## Huesos que se ofrecen para colgar una prenda (sin dedos).
const SKIP_BONES := ["Thumb", "Index", "Middle", "Ring", "Pinky", "_End", "HeadTop"]

class Item:
	var id := ""
	var root: Node3D
	var extent := Vector3.ONE
	var box: MeshInstance3D
	var bone := ClothingFit.DEFAULT_BONE
	var slot := ClothingFit.SLOT_SHIRT   ## ranura en el juego: camiseta o pantalón
	var pos := Vector3(0, 1.2, 0)
	var rot := Basis.IDENTITY
	var scl := Vector3.ONE * 0.6
	var shown := false
	var touched := false
	var arms: Dictionary = {}   ## pose de brazos de esta prenda (vacío = no tiene una propia)
	var model: Node3D           ## la malla rígida de la prenda (hija de root)
	var skin: Array[MeshInstance3D] = []   ## malla pegada al cuerpo (vista previa), vacío si no hay

	func state() -> Dictionary:
		return {"id": id, "bone": bone, "pos": pos, "rot": rot, "scl": scl}

	func restore(s: Dictionary) -> void:
		bone = s["bone"]
		pos = s["pos"]
		rot = s["rot"]
		scl = s["scl"]

var _cam: Camera3D
var _yaw := 0.0
var _pitch := 8.0
var _dist := 3.4
var _target := Vector3(0, 1.05, 0)
var _focus_slot := ClothingFit.SLOT_SHIRT   ## ranura a la que apunta la cámara ahora
var _orbiting := false
var _panning := false

var _model: Node3D
var _skel: Skeleton3D
var _ms := 1.0                ## metros por unidad del esqueleto
var _world: Node3D            ## cuelga las prendas
var _fits: Dictionary = {}    ## id -> entrada del JSON
var _items: Dictionary = {}   ## id -> Item
var _ids: Array[String] = []
var _sel := ""
var _arm := {"Left": 0.0, "Right": 0.0}
var _leg_rest: Dictionary = {}              ## pierna -> [dirección del muslo, de la pierna] en reposo (0° = piernas rectas)
var _arm_dir: Dictionary = {}              ## lado -> [dirección del brazo, dirección del antebrazo]
var _arm_handles: Dictionary = {}          ## "Left_0" (codo), "Left_1" (mano)… -> MeshInstance3D
var _arm_hover := ""
var _arm_drag := ""
var _arm_drag_plane := Vector3.ZERO
var _arms_check: CheckButton
var _skin_check: CheckButton

# Gizmo
var _gizmo: Node3D
var _gz: Array[Node3D] = []              ## un nodo por modo
var _gmats: Array = []                   ## por modo: [mat X, mat Y, mat Z, mat centro]
var _mode := MODE_MOVE
var _local := true
var _hover := -1
var _drag_h := -1
var _drag_mode := 0
var _d_axes: Array[Vector3] = []
var _d_origin := Vector3.ZERO
var _d_gs := 1.0
var _d_basis := Basis.IDENTITY
var _d_pos := Vector3.ZERO
var _d_scl := Vector3.ONE
var _d_t0 := 0.0
var _d_hit0 := Vector3.ZERO
var _d_u := Vector3.RIGHT
var _d_v := Vector3.UP
var _d_prev := 0.0
var _d_total := 0.0
var _d_mouse0 := Vector2.ZERO
var _d_dist0 := 1.0

# Deshacer
var _undo: Array = []
var _redo: Array = []
var _last_spin_push := 0

# UI
var _syncing := false
var _dirty := false
var _theme: Theme
var _sidebar: PanelContainer
var _ui_layer: CanvasLayer
var _list_box: VBoxContainer
var _vis_checks: Dictionary = {}
var _name_buttons: Dictionary = {}
var _mode_buttons: Array[Button] = []
var _space_select: OptionButton
var _snap_check: CheckButton
var _bone_select: OptionButton
var _slot_select: OptionButton
var _bone_names: Array[String] = []
var _pos_spins: Array[SpinBox] = []
var _rot_spins: Array[SpinBox] = []
var _scl_spins: Array[SpinBox] = []
var _uniform_check: CheckButton
var _arm_spins: Dictionary = {}
var _arm_sync: CheckButton
var _leg_sync: CheckButton
var _sidebar_btn: Button
var _body_check: CheckButton
var _status: Label
var _status_dot: Panel
var _subtitle: Label

func _ready() -> void:
	get_window().title = "Rumbang · Editor de ropa"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fits = ClothingFit.load_all()
	_ids = ClothingFit.garment_ids()
	_build_world()
	if not _build_character():
		get_tree().quit(1)
		return
	_build_gizmo()
	_init_legs()
	_build_arm_handles()
	_build_ui()
	_set_arms(0.0, 0.0)
	var state := _load_state()
	_restore_arms(state)
	var first := String(state.get("selected", ""))
	if not _ids.has(first):
		first = _ids[0] if not _ids.is_empty() else ""
	for id in state.get("shown", []):
		if _ids.has(String(id)):
			show_garment(String(id), true)
	if first != "":
		select_garment(first)
	else:
		_set_status("No hay prendas en %s" % ClothingFit.DIR, C_WARN)
	if state.has("cam"):
		var c: Array = state["cam"]
		if c.size() >= 6:
			set_view(float(c[0]), float(c[1]), float(c[2]), Vector3(float(c[3]), float(c[4]), float(c[5])))
	_set_mode(MODE_MOVE)
	print("[ClothingEditor] Listo · prendas=", _ids, " · ms=", _ms)

# ══════════════════════════════════════════════════════════════════════════════
# Escena: luces, suelo, personaje
# ══════════════════════════════════════════════════════════════════════════════

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.56, 0.62)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.85, 1.0)
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 100.0
	add_child(_cam)
	_cam.current = true
	_world = Node3D.new()
	_world.name = "Prendas"
	add_child(_world)

func _build_grid(y: float) -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in range(-10, 11):
		var c := Color(1, 1, 1, 0.16 if i % 2 == 0 else 0.07)
		var x := i * 0.5
		if i == 0:
			continue   # los ejes van aparte
		verts.append_array([Vector3(x, y, -5), Vector3(x, y, 5), Vector3(-5, y, x), Vector3(5, y, x)])
		for _k in 4:
			cols.append(c)
	verts.append_array([Vector3(-5, y, 0), Vector3(5, y, 0), Vector3(0, y, -5), Vector3(0, y, 5)])
	cols.append_array([Color(AXIS_COLORS[0], 0.6), Color(AXIS_COLORS[0], 0.6), Color(AXIS_COLORS[2], 0.6), Color(AXIS_COLORS[2], 0.6)])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.name = "Rejilla"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

func _build_character() -> bool:
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_error("No se pudo cargar " + MODEL_PATH)
		return false
	_model = scene.instantiate() as Node3D
	add_child(_model)
	var ap := _model.find_child("AnimationPlayer", true, false)
	if ap:
		ap.queue_free()   # pose estática: la dirige este editor
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var body := CharacterLookApplier.body_mesh(_model)
	var aabb := body.mesh.get_aabb()
	_ms = ClothingFit.BODY_HEIGHT / maxf(aabb.size.y, 0.0001)
	_model.scale = Vector3.ONE * _ms   # el origen del esqueleto se queda en el del mundo: ver ClothingFit
	_build_grid(aabb.position.y * _ms)
	var look := CharacterLook.load_saved()
	look.hat = "ninguno"
	look.footwear = "descalzo"
	look.height = 1.0
	look.build = 1.0
	look.head = 1.0
	look.shirt = CharacterLook.SHIRT_NONE   # la ropa guardada del jugador no cuenta: aquí solo la que se prueba
	look.pants = CharacterLook.PANTS_NONE
	CharacterLookApplier.apply_to(_model, look)
	_strip_underwear(body)
	return true

## El personaje del editor va siempre desnudo: se hacen invisibles los calzones y su elástico (superficies del cuerpo).
func _strip_underwear(body: MeshInstance3D) -> void:
	var hidden := StandardMaterial3D.new()
	hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden.albedo_color = Color(1, 1, 1, 0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in body.mesh.get_surface_count():
		var mat := body.mesh.surface_get_material(i)
		var n := mat.resource_name if mat else ""
		if n == "rb_Calzones" or n == "rb_Elastico":
			body.set_surface_override_material(i, hidden)

# ══════════════════════════════════════════════════════════════════════════════
# Pose T y brazos
# ══════════════════════════════════════════════════════════════════════════════

## Dirección en que apunta cada tramo del brazo (0 = brazo, 1 = antebrazo), en el espacio del esqueleto. Pose T: horizontal.
func _set_arm_angle(side: String, degrees: float) -> void:
	if side.ends_with("Leg"):
		# Pierna: 0° = reposo; positivo la abre hacia fuera (gira sobre el eje Z del cuerpo)
		var rest: Array = _leg_rest.get(side, [Vector3.DOWN, Vector3.DOWN])
		var ang := deg_to_rad(degrees) * (1.0 if side == "LeftLeg" else -1.0)
		_arm_dir[side] = [Basis(Vector3.BACK, ang) * (rest[0] as Vector3), Basis(Vector3.BACK, ang) * (rest[1] as Vector3)]
		return
	var a := deg_to_rad(degrees)
	var sx := 1.0 if side == "Left" else -1.0   # el lado izquierdo está en +X
	var dir := Vector3(sx * cos(a), sin(a), 0.0)
	_arm_dir[side] = [dir, dir]

## Pone la pose: cada tramo del brazo apunta a `_arm_dir` (se arrastran las asas de codo y mano, o los deslizadores).
func _apply_pose() -> void:
	if _skel == null:
		return
	_skel.reset_bone_poses()
	for side in ClothingFit.LIMBS:
		if not _arm_dir.has(side):
			continue
		var dirs: Array = _arm_dir[side]
		var chain := ClothingFit.limb_chain(side)
		for k in chain.size():
			var b := _skel.find_bone(chain[k][0])
			var c := _skel.find_bone(chain[k][1])
			if b < 0 or c < 0:
				continue
			var head := _skel.get_bone_global_pose(b).origin
			var d := (_skel.get_bone_global_pose(c).origin - head).normalized()
			var t: Vector3 = (dirs[k] as Vector3).normalized()
			# La pose de un hueso es su transformación LOCAL completa (en reposo = su "rest"): se gira su base global
			var p := _skel.get_bone_parent(b)
			var parent_g := _skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
			var rest := _skel.get_bone_rest(b).basis.orthonormalized()
			var delta := Basis(Quaternion(d, t))
			_skel.set_bone_pose_rotation(b, (parent_g.inverse() * delta * parent_g * rest).get_rotation_quaternion())

## Movimiento rígido (en el mundo) que ha sufrido el hueso respecto a su reposo.
func _pose_delta(bone: String) -> Transform3D:
	var b := _skel.find_bone(bone) if _skel else -1
	if b < 0:
		return Transform3D.IDENTITY
	var sg := _skel.global_transform
	var d := sg * _skel.get_bone_global_pose(b) * _skel.get_bone_global_rest(b).affine_inverse() * sg.affine_inverse()
	return Transform3D(d.basis.orthonormalized(), d.origin)

# ══════════════════════════════════════════════════════════════════════════════
# Prendas
# ══════════════════════════════════════════════════════════════════════════════

func _ensure_item(id: String) -> Item:
	if _items.has(id):
		return _items[id]
	var n := ClothingFit.normalized(id)
	if n.is_empty():
		_set_status("No se pudo cargar la prenda " + id, C_ERR)
		return null
	var it := Item.new()
	it.id = id
	it.root = n["node"]
	it.extent = n["extent"]
	it.model = it.root.get_child(0) as Node3D
	_world.add_child(it.root)
	if _fits.has(id):
		var e := ClothingFit.parse_entry(_fits[id])
		it.bone = e["bone"]
		it.pos = e["pos"]
		it.rot = e["rot"]
		it.scl = e["scale"]
		it.arms = e["arms"]
		it.slot = ClothingFit.slot_of(id, _fits[id])
	else:
		it.slot = ClothingFit.slot_of(id)
		_default_fit(it)
	it.box = _make_box(it.extent)
	it.root.add_child(it.box)
	_items[id] = it
	return it

## Primer ajuste de una prenda sin guardar: la endereza si viene tumbada o de lado y la pone en el pecho.
func _default_fit(it: Item) -> void:
	var e := it.extent
	it.rot = Basis.IDENTITY
	if it.slot == ClothingFit.SLOT_SHOES:
		_shoe_default(it, e)
		return
	if it.slot == ClothingFit.SLOT_PANTS:
		# Pantalón: de la cadera hacia abajo (~0,9 m de alto), colgado del hueso de la cadera. Su lado largo va en Y.
		if e.x > e.y and e.x >= e.z:
			it.rot = Basis(Vector3.BACK, PI / 2.0)
			e = Vector3(e.y, e.x, e.z)
		elif e.z > e.y and e.z > e.x:
			it.rot = Basis(Vector3.RIGHT, PI / 2.0)
			e = Vector3(e.x, e.z, e.y)
		it.bone = ClothingFit.PANTS_BONE
		it.pos = Vector3(0, 0.82, 0.0)
		it.scl = Vector3.ONE * (0.9 / maxf(e.y, 0.01))
		return
	if e.y <= e.x and e.y <= e.z:
		it.rot = Basis(Vector3.RIGHT, PI / 2.0)
		e = Vector3(e.x, e.z, e.y)
	elif e.x < e.y and e.x < e.z:
		it.rot = Basis(Vector3.UP, PI / 2.0)
		e = Vector3(e.z, e.y, e.x)
	it.bone = ClothingFit.DEFAULT_BONE
	it.pos = Vector3(0, 1.2, 0.045)   # el pecho sobresale del eje del esqueleto
	var s := 0.66 / maxf(e.x, 0.01)
	it.scl = Vector3.ONE * s
	var thin := it.extent.min_axis_index()   # eje local del grosor: se engrosa para tapar el torso
	it.scl[thin] = s * 1.6

## Primer ajuste de un zapato. Si su pareja ya está colocada, este es su espejo; si no, el pie correspondiente
## (el original al izquierdo, el gemelo al derecho) con el lado largo hacia delante y ~29 cm de largo.
func _shoe_default(it: Item, e: Vector3) -> void:
	var other_id := ClothingFit.twin_id(it.id)
	var other: Item = _items.get(other_id)
	if other != null and other.touched:
		_mirror_from(it, other)
		return
	if _fits.has(other_id):
		var oe := ClothingFit.parse_entry(_fits[other_id])
		var tmp := Item.new()
		tmp.bone = oe["bone"]
		tmp.pos = oe["pos"]
		tmp.rot = oe["rot"]
		tmp.scl = oe["scale"]
		_mirror_from(it, tmp)
		return
	var long_axis := e.max_axis_index()
	it.rot = Basis.IDENTITY
	var length := e[long_axis]
	if long_axis == 0:
		it.rot = Basis(Vector3.UP, PI / 2.0)
	elif long_axis == 1:
		it.rot = Basis(Vector3.RIGHT, PI / 2.0)
	it.bone = "mixamorig_RightFoot" if ClothingFit.is_twin(it.id) else "mixamorig_LeftFoot"
	it.scl = Vector3.ONE * (0.29 / maxf(length, 0.01))
	var foot := _skel.find_bone(it.bone)
	var base := _skel.global_transform * _skel.get_bone_global_rest(foot).origin if foot >= 0 else Vector3(0.09 * (-1.0 if ClothingFit.is_twin(it.id) else 1.0), 0.07, 0.0)
	it.pos = base + Vector3(0.0, -0.02, 0.06)

## Copia el ajuste de `src` reflejado en X (el otro pie): hueso del lado contrario, posición y rotación espejadas.
func _mirror_from(it: Item, src: Item) -> void:
	var m := Basis.from_scale(Vector3(-1, 1, 1))
	it.bone = src.bone.replace("Left", "TMP").replace("Right", "Left").replace("TMP", "Right")
	it.pos = Vector3(-src.pos.x, src.pos.y, src.pos.z)
	it.rot = (m * src.rot * m).orthonormalized()
	it.scl = src.scl

## Botón "Espejar": este zapato queda como reflejo de su pareja.
func _on_mirror_pair() -> void:
	var it := _selected()
	if it == null or it.slot != ClothingFit.SLOT_SHOES:
		return
	var other: Item = _ensure_item(ClothingFit.twin_id(it.id))
	if other == null:
		return
	_push_undo()
	_leave_skin()
	_mirror_from(it, other)
	it.touched = true
	_apply_item(it)
	_show_fields()
	_mark_dirty()

func _make_box(ext: Vector3) -> MeshInstance3D:
	var h := ext * 0.5
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var verts := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if not (i & bit):
				verts.append(c[i])
				verts.append(c[i | bit])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = C_ACCENT
	var mi := MeshInstance3D.new()
	mi.name = "Caja"
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	return mi

func _apply_item(it: Item) -> void:
	var dw := _pose_delta(it.bone)
	it.root.visible = it.shown
	it.model.visible = it.skin.is_empty()   # con la vista pegada se ve la malla con pesos, no la rígida
	it.root.global_transform = Transform3D((dw.basis * it.rot) * Basis.from_scale(it.scl), dw * it.pos)

## Fija la transformación de `it` desde una pose en el mundo (la inversa de _apply_item).
func _set_from_world(it: Item, pos_w: Vector3, rot_w: Basis, scl: Vector3) -> void:
	var inv := _pose_delta(it.bone).affine_inverse()
	it.pos = inv * pos_w
	it.rot = (inv.basis * rot_w).orthonormalized()
	it.scl = scl
	it.touched = true
	_leave_skin()
	_apply_item(it)

## Vista pegada al cuerpo (como en el juego): la prenda con pesos de hueso del cuerpo, que sigue a los brazos.
## Tarda unos segundos la primera vez con cada ajuste; cualquier cambio de la prenda la quita (se vuelve a marcar).
func _drop_skin(it: Item) -> void:
	for mi in it.skin:
		if is_instance_valid(mi):
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	it.skin.clear()

func _sync_skin(it: Item) -> void:
	_drop_skin(it)
	if not it.shown or _skin_check == null or not _skin_check.button_pressed:
		return
	var body := CharacterLookApplier.body_mesh(_model)
	for mi in ClothingFit.build_skinned(it.id, ClothingFit.entry_to_json(it.bone, it.pos, it.rot, it.scl, it.arms, it.slot), body, _ms):
		_skel.add_child(mi)
		it.skin.append(mi)

## Quita la vista pegada de todas las prendas (al editar una): vuelve la malla rígida con el gizmo.
func _leave_skin() -> void:
	var any := false
	for id in _items:
		var it: Item = _items[id]
		if not it.skin.is_empty():
			any = true
			_drop_skin(it)
	if any and _skin_check:
		_skin_check.set_pressed_no_signal(false)

func _on_skin_toggled(on: bool) -> void:
	_set_status("Pegando las prendas al cuerpo…" if on else "Vista rígida", C_WARN)
	await get_tree().process_frame
	for id in _items:
		_sync_skin(_items[id])
	_set_status("Vista pegada al cuerpo: mueve los brazos para ver cómo sigue la prenda" if on else "Vista rígida", C_OK)

func select_garment(id: String) -> void:
	var it := _ensure_item(id)
	if it == null:
		return
	if _sel != "" and _items.has(_sel):
		(_items[_sel] as Item).box.visible = false
	_sel = id
	# La rueda acerca hacia donde se trabaja: camisa al torso/cuerpo, pantalón a las piernas, zapato a los pies
	if it.slot != _focus_slot:
		_focus_slot = it.slot
		_target = Vector3(0.0, {ClothingFit.SLOT_PANTS: 0.55, ClothingFit.SLOT_SHOES: 0.1}.get(it.slot, 1.05), 0.0)
	it.shown = true
	it.box.visible = true
	_sync_skin(it)
	_apply_item(it)
	if _vis_checks.has(id):
		(_vis_checks[id] as CheckBox).set_pressed_no_signal(true)
	_refresh_list()
	_show_fields()
	if not it.arms.is_empty():
		_load_arms(it.arms)   # cada prenda recupera la pose de brazos con la que se ajustó
	_set_status("Editando %s" % _pretty(id), C_WARN if _dirty else C_OK)

func show_garment(id: String, shown: bool) -> void:
	var it := _ensure_item(id)
	if it == null:
		return
	it.shown = shown
	_sync_skin(it)
	_apply_item(it)
	if _vis_checks.has(id):
		(_vis_checks[id] as CheckBox).set_pressed_no_signal(shown)
	if not shown and id == _sel:
		it.box.visible = false

func _pretty(id: String) -> String:
	return ClothingFit.pretty(id)

func _selected() -> Item:
	return _items.get(_sel) as Item

# ══════════════════════════════════════════════════════════════════════════════
# Gizmo
# ══════════════════════════════════════════════════════════════════════════════

func _gmat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.render_priority = 100
	return m

func _gadd(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _build_gizmo() -> void:
	_gizmo = Node3D.new()
	_gizmo.name = "Gizmo"
	add_child(_gizmo)
	for m in 3:
		var holder := Node3D.new()
		_gizmo.add_child(holder)
		_gz.append(holder)
		_gmats.append([])
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in 3:
		var a: Vector3 = axes[i]
		var to_axis := Basis(Quaternion(Vector3.UP, a))
		# — Mover: flecha —
		var mv := _gmat(AXIS_COLORS[i])
		(_gmats[MODE_MOVE] as Array).append(mv)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.022
		shaft.bottom_radius = 0.022
		shaft.height = 0.78
		shaft.radial_segments = 8
		_gadd(_gz[MODE_MOVE], shaft, mv, Transform3D(to_axis, a * 0.39))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.22
		cone.radial_segments = 12
		_gadd(_gz[MODE_MOVE], cone, mv, Transform3D(to_axis, a * 0.89))
		# — Rotar: anillo —
		var rt := _gmat(AXIS_COLORS[i])
		(_gmats[MODE_ROTATE] as Array).append(rt)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.965
		ring.outer_radius = 1.0
		ring.rings = 64
		ring.ring_segments = 8
		_gadd(_gz[MODE_ROTATE], ring, rt, Transform3D(to_axis, Vector3.ZERO))
		# — Escalar: palo con cubo —
		var sc := _gmat(AXIS_COLORS[i])
		(_gmats[MODE_SCALE] as Array).append(sc)
		var sshaft := CylinderMesh.new()
		sshaft.top_radius = 0.022
		sshaft.bottom_radius = 0.022
		sshaft.height = 0.85
		sshaft.radial_segments = 8
		_gadd(_gz[MODE_SCALE], sshaft, sc, Transform3D(to_axis, a * 0.425))
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.13
		_gadd(_gz[MODE_SCALE], cube, sc, Transform3D(Basis.IDENTITY, a * 0.92))
	# Centros
	var c_move := _gmat(Color(C_CENTER, 0.9))
	(_gmats[MODE_MOVE] as Array).append(c_move)
	var ball := SphereMesh.new()
	ball.radius = 0.075
	ball.height = 0.15
	_gadd(_gz[MODE_MOVE], ball, c_move, Transform3D.IDENTITY)
	var c_scale := _gmat(Color(C_CENTER, 0.9))
	(_gmats[MODE_SCALE] as Array).append(c_scale)
	var cbox := BoxMesh.new()
	cbox.size = Vector3.ONE * 0.16
	_gadd(_gz[MODE_SCALE], cbox, c_scale, Transform3D.IDENTITY)

func _set_mode(m: int) -> void:
	_mode = m
	for i in 3:
		_gz[i].visible = i == m
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == m)
	_refresh_gizmo_colors()

func _refresh_gizmo_colors() -> void:
	for m in 3:
		var mats: Array = _gmats[m]
		for i in mats.size():
			var base: Color = AXIS_COLORS[i] if i < 3 else C_CENTER
			var hot := i == _hover or (_drag_h == i and _drag_mode == m)
			(mats[i] as StandardMaterial3D).albedo_color = Color(base.lightened(0.55), 1.0) if hot else Color(base, 0.9)

func _gizmo_size() -> float:
	var it := _selected()
	if it == null:
		return 1.0
	return _cam.global_position.distance_to(it.root.global_position) * GIZMO_K

## Base del gizmo: ejes de la prenda (modo local, o escalar) o del mundo.
func _gizmo_basis(it: Item) -> Basis:
	if _local or _mode == MODE_SCALE:
		return it.root.global_transform.basis.orthonormalized()
	return Basis.IDENTITY

func _update_gizmo() -> void:
	var it := _selected()
	if it == null or not it.shown:
		_gizmo.visible = false
		return
	_gizmo.visible = true
	var gs := _gizmo_size()
	if _drag_h >= 0:
		gs = _d_gs
	_gizmo.global_transform = Transform3D(_gizmo_basis(it) * Basis.from_scale(Vector3.ONE * gs), it.root.global_position)

func _axes() -> Array[Vector3]:
	var b := _gizmo.global_transform.basis
	return [b.x.normalized(), b.y.normalized(), b.z.normalized()]

func _screen(p: Vector3) -> Variant:
	if _cam.is_position_behind(p):
		return null
	return _cam.unproject_position(p)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Asa del gizmo bajo el ratón: 0-2 = eje X/Y/Z, 3 = centro, -1 = ninguna.
func _pick_handle(mp: Vector2) -> int:
	var it := _selected()
	if it == null or not it.shown:
		return -1
	var o := it.root.global_position
	var gs := _gizmo_size()
	var axes := _axes()
	var best := -1
	var best_d := PICK_PX
	if _mode != MODE_ROTATE:
		var so: Variant = _screen(o)
		if so != null and mp.distance_to(so) < PICK_PX:
			return 3
		for i in 3:
			var se: Variant = _screen(o + axes[i] * gs)
			if so == null or se == null:
				continue
			var d := _seg_dist(mp, so, se)
			if d < best_d:
				best_d = d
				best = i
	else:
		var to_cam := (_cam.global_position - o).normalized()
		for i in 3:
			var u := axes[(i + 1) % 3]
			var v := axes[(i + 2) % 3]
			var prev: Variant = null
			for k in 49:
				var t := TAU * float(k) / 48.0
				var dir := u * cos(t) + v * sin(t)
				var p := o + dir * gs
				var sp: Variant = _screen(p) if dir.dot(to_cam) > -0.12 else null   # solo la mitad que mira a la cámara
				if sp != null and prev != null:
					var d := _seg_dist(mp, prev, sp)
					if d < best_d:
						best_d = d
						best = i
				prev = sp
	return best

func _ray(mp: Vector2) -> Array:
	return [_cam.project_ray_origin(mp), _cam.project_ray_normal(mp)]

## Parámetro t del punto de la recta o + t·a más cercano al rayo del ratón.
func _axis_t(o: Vector3, a: Vector3, mp: Vector2) -> float:
	var r := _ray(mp)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var w0 := o - ro
	var b := a.dot(rd)
	var c := a.dot(w0)
	var e := rd.dot(w0)
	var den := 1.0 - b * b
	if absf(den) < 0.0001:
		return NAN
	return (b * e - c) / den

func _ray_plane(o: Vector3, n: Vector3, mp: Vector2) -> Variant:
	var r := _ray(mp)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var den := n.dot(rd)
	if absf(den) < 0.0001:
		return null
	return ro + rd * (n.dot(o - ro) / den)

func _ring_angle(o: Vector3, mp: Vector2) -> float:
	var hit: Variant = _ray_plane(o, _d_axes[_drag_h], mp)
	if hit == null:
		return NAN
	var vec: Vector3 = (hit as Vector3) - o
	return atan2(vec.dot(_d_v), vec.dot(_d_u))

func _snap_on() -> bool:
	return _snap_check.button_pressed != Input.is_key_pressed(KEY_CTRL)

func _begin_drag(h: int, mp: Vector2) -> void:
	var it := _selected()
	_push_undo()
	_drag_h = h
	_drag_mode = _mode
	_d_axes = _axes()
	_d_origin = it.root.global_position
	_d_gs = _gizmo_size()
	_d_basis = it.root.global_transform.basis.orthonormalized()
	_d_pos = _d_origin
	_d_scl = it.scl
	_d_mouse0 = mp
	match _mode:
		MODE_MOVE:
			if h < 3:
				_d_t0 = _axis_t(_d_origin, _d_axes[h], mp)
			else:
				var hit: Variant = _ray_plane(_d_origin, -_cam.global_transform.basis.z, mp)
				_d_hit0 = hit if hit != null else _d_origin
		MODE_ROTATE:
			var n := _d_axes[h]
			_d_u = n.cross(Vector3.UP)
			if _d_u.length() < 0.2:
				_d_u = n.cross(Vector3.RIGHT)
			_d_u = _d_u.normalized()
			_d_v = n.cross(_d_u)
			_d_prev = _ring_angle(_d_origin, mp)
			_d_total = 0.0
		MODE_SCALE:
			if h < 3:
				_d_t0 = _axis_t(_d_origin, _d_axes[h], mp)
			else:
				var so: Variant = _screen(_d_origin)
				_d_dist0 = maxf(mp.distance_to(so) if so != null else 1.0, 24.0)
	_refresh_gizmo_colors()

func _update_drag(mp: Vector2) -> void:
	var it := _selected()
	if it == null:
		return
	var snap := _snap_on()
	var pos_w := _d_pos
	var rot_w := _d_basis
	var scl := _d_scl
	match _drag_mode:
		MODE_MOVE:
			if _drag_h < 3:
				var t := _axis_t(_d_origin, _d_axes[_drag_h], mp)
				if is_nan(t) or is_nan(_d_t0):
					return
				var delta := t - _d_t0
				if snap:
					delta = snappedf(delta, SNAP_MOVE)
				pos_w = _d_pos + _d_axes[_drag_h] * delta
			else:
				var hit: Variant = _ray_plane(_d_origin, -_cam.global_transform.basis.z, mp)
				if hit == null:
					return
				pos_w = _d_pos + ((hit as Vector3) - _d_hit0)
				if snap:
					pos_w = pos_w.snapped(Vector3.ONE * SNAP_MOVE)
		MODE_ROTATE:
			var ang := _ring_angle(_d_origin, mp)
			if is_nan(ang) or is_nan(_d_prev):
				return
			if absf(_d_axes[_drag_h].dot(_cam.global_transform.basis.z)) < 0.12:
				return   # el anillo se ve de canto: el ángulo sería inestable
			_d_total += wrapf(ang - _d_prev, -PI, PI)
			_d_prev = ang
			var delta := _d_total
			if snap:
				delta = snappedf(delta, deg_to_rad(SNAP_ROT))
			rot_w = Basis(_d_axes[_drag_h], delta) * _d_basis
		MODE_SCALE:
			var ratio := 1.0
			if _drag_h < 3:
				var t := _axis_t(_d_origin, _d_axes[_drag_h], mp)
				if is_nan(t) or is_nan(_d_t0):
					return
				ratio = 1.0 + (t - _d_t0) / _d_gs
			else:
				var so: Variant = _screen(_d_origin)
				if so == null:
					return
				ratio = mp.distance_to(so) / _d_dist0
			ratio = maxf(ratio, 0.02)
			if _drag_h < 3:
				scl[_drag_h] = _d_scl[_drag_h] * ratio
			else:
				scl = _d_scl * ratio
			if snap:
				scl = Vector3(snappedf(scl.x, SNAP_SCALE), snappedf(scl.y, SNAP_SCALE), snappedf(scl.z, SNAP_SCALE))
			scl = scl.max(Vector3.ONE * 0.01)
	_set_from_world(it, pos_w, rot_w, scl)
	_mark_dirty()
	_show_fields()

func _end_drag() -> void:
	_drag_h = -1
	_refresh_gizmo_colors()

func _cancel_drag() -> void:
	if _drag_h < 0:
		return
	_drag_h = -1
	if not _undo.is_empty():
		_restore(_undo.pop_back())
	_refresh_gizmo_colors()

## Prenda bajo el ratón (la más cercana a la cámara), "" si no hay.
func _pick_garment(mp: Vector2) -> String:
	var r := _ray(mp)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var best := ""
	var best_d := INF
	for id in _items:
		var it: Item = _items[id]
		if not it.shown:
			continue
		var inv := it.root.global_transform.affine_inverse()
		var local_o := inv * ro
		var local_d := inv.basis * rd
		var hit: Variant = AABB(-it.extent * 0.5, it.extent).intersects_ray(local_o, local_d)
		if hit != null:
			var d := ro.distance_to(it.root.global_transform * (hit as Vector3))
			if d < best_d:
				best_d = d
				best = id
	return best

# ══════════════════════════════════════════════════════════════════════════════
# Cámara e input
# ══════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cam == null:
		return
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _dist
	_cam.global_position = _target + offset
	_cam.look_at(_target, Vector3.UP)
	for id in _items:
		_apply_item(_items[id])
	_update_gizmo()
	if _drag_h < 0 and _arm_drag == "" and not _orbiting and not _panning:
		var h := -1
		var ah := ""
		if get_viewport().gui_get_hovered_control() == null:
			var mp := get_viewport().get_mouse_position()
			if _gizmo.visible:
				h = _pick_handle(mp)
			if h < 0:
				ah = _pick_arm_handle(mp)
		if h != _hover:
			_hover = h
			_refresh_gizmo_colors()
		_arm_hover = ah
	_update_arm_handles()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					get_viewport().gui_release_focus()
					var h := _pick_handle(mb.position)
					var ah := _pick_arm_handle(mb.position) if h < 0 else ""
					if h >= 0:
						_begin_drag(h, mb.position)
					elif ah != "":
						_begin_arm_drag(ah)
					else:
						var id := _pick_garment(mb.position)
						if id != "":
							select_garment(id)
				else:
					_arm_drag = ""
					if _drag_h >= 0:
						_end_drag()
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = clampf(_dist * 0.9, 0.3, 15.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist * 1.1, 0.3, 15.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_h >= 0:
			_update_drag(mm.position)
		elif _arm_drag != "":
			_update_arm_drag(mm.position)
		elif _orbiting:
			_yaw -= mm.relative.x * 0.4
			_pitch = clampf(_pitch + mm.relative.y * 0.3, -85.0, 85.0)
		elif _panning:
			var b := _cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0016
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		var handled := true
		if key.ctrl_pressed and key.keycode == KEY_S:
			_on_save()
		elif key.ctrl_pressed and key.keycode == KEY_Z and not key.shift_pressed:
			_do_undo()
		elif key.ctrl_pressed and (key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed)):
			_do_redo()
		elif key.keycode == KEY_TAB:
			set_sidebar_open(not _sidebar.visible)
		elif key.keycode == KEY_W:
			_set_mode(MODE_MOVE)
		elif key.keycode == KEY_E:
			_set_mode(MODE_ROTATE)
		elif key.keycode == KEY_R:
			_set_mode(MODE_SCALE)
		elif key.keycode == KEY_X:
			_space_select.select(1 if _local else 0)
			_on_space_selected(_space_select.selected)
		elif key.keycode == KEY_F:
			_focus_selected()
		elif key.keycode == KEY_1:
			set_view(0.0, 8.0)
		elif key.keycode == KEY_3:
			set_view(90.0, 8.0)
		elif key.keycode == KEY_7:
			set_view(0.0, 80.0)
		elif key.keycode == KEY_ESCAPE:
			_cancel_drag()
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()

func set_view(yaw: float, pitch: float, dist: float = -1.0, target: Variant = null) -> void:
	_yaw = yaw
	_pitch = pitch
	if dist > 0.0:
		_dist = dist
	if target is Vector3:
		_target = target

func _focus_selected() -> void:
	var it := _selected()
	if it != null:
		_target = it.root.global_position
		_dist = clampf(maxf(it.extent.length() * it.scl.x * 2.2, 1.2), 0.6, 6.0)

# ══════════════════════════════════════════════════════════════════════════════
# Deshacer
# ══════════════════════════════════════════════════════════════════════════════

func _push_undo() -> void:
	var it := _selected()
	if it == null:
		return
	_undo.append(it.state())
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()

func _restore(s: Dictionary) -> void:
	var it := _ensure_item(String(s["id"]))
	if it == null:
		return
	_leave_skin()
	it.restore(s)
	it.touched = true
	if _sel != it.id:
		select_garment(it.id)
	_apply_item(it)
	_show_fields()
	_mark_dirty()

func _do_undo() -> void:
	if _undo.is_empty():
		return
	var s: Dictionary = _undo.pop_back()
	var cur := _items.get(String(s["id"])) as Item
	if cur:
		_redo.append(cur.state())
	_restore(s)

func _do_redo() -> void:
	if _redo.is_empty():
		return
	var s: Dictionary = _redo.pop_back()
	var cur := _items.get(String(s["id"])) as Item
	if cur:
		_undo.append(cur.state())
	_restore(s)

# ══════════════════════════════════════════════════════════════════════════════
# Tema y UI
# ══════════════════════════════════════════════════════════════════════════════

func _box(bg: Color, radius := 6, border := Color(0, 0, 0, 0), margin := 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12
	var panel := _box(C_PANEL, 10, Color(1, 1, 1, 0.07), 14.0)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := _box(C_BTN, 6, Color(1, 1, 1, 0.06))
	var hover := _box(C_BTN_HOVER, 6, Color(1, 1, 1, 0.1))
	var pressed := _box(C_ACCENT.darkened(0.25), 6)
	var focus := _box(Color(0, 0, 0, 0), 6, Color(C_ACCENT, 0.7))
	focus.draw_center = false
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
	var field := _box(C_FIELD, 5, Color(1, 1, 1, 0.06), 6.0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _box(C_FIELD, 5, Color(C_ACCENT, 0.8), 6.0))
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(1, 1, 1, 0.1)
	rail.set_corner_radius_all(2)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	var rail_fill := rail.duplicate() as StyleBoxFlat
	rail_fill.bg_color = Color(C_ACCENT, 0.75)
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", rail_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", rail_fill)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	return t

func _build_ui() -> void:
	_theme = _make_theme()
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "ClothingEditorUI"
	_ui_layer.layer = 100
	add_child(_ui_layer)
	var root := Control.new()
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(root)

	_sidebar = PanelContainer.new()
	_sidebar.anchor_bottom = 1.0
	_sidebar.offset_left = UI_MARGIN
	_sidebar.offset_top = UI_MARGIN
	_sidebar.offset_right = UI_MARGIN + SIDEBAR_W
	_sidebar.offset_bottom = -UI_MARGIN
	root.add_child(_sidebar)
	# Botón fijo para minimizar / mostrar la barra (también con la tecla Tab)
	_sidebar_btn = Button.new()
	_sidebar_btn.focus_mode = Control.FOCUS_NONE
	_sidebar_btn.offset_left = UI_MARGIN
	_sidebar_btn.offset_top = UI_MARGIN
	_sidebar_btn.pressed.connect(func() -> void: set_sidebar_open(not _sidebar.visible))
	root.add_child(_sidebar_btn)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Editor de ropa"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	box.add_child(title_row)
	set_sidebar_open(true)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color", C_ACCENT)
	box.add_child(_subtitle)

	# — Prendas —
	box.add_child(_section("PRENDAS"))
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 3)
	box.add_child(_list_box)
	for id in _ids:
		var row := HBoxContainer.new()
		var cb := CheckBox.new()
		cb.tooltip_text = "Mostrar / ocultar"
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void: show_garment(id, on))
		row.add_child(cb)
		var b := Button.new()
		b.text = _pretty(id)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: select_garment(id))
		row.add_child(b)
		_list_box.add_child(row)
		_vis_checks[id] = cb
		_name_buttons[id] = b

	# — Herramienta —
	box.add_child(_section("HERRAMIENTA"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	for m in 3:
		var b := Button.new()
		b.text = MODE_NAMES[m]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_mode.bind(m))
		modes.add_child(b)
		_mode_buttons.append(b)
	box.add_child(modes)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	opts.add_child(_dim_label("Ejes"))
	_space_select = OptionButton.new()
	_space_select.add_item("Locales", 0)
	_space_select.add_item("Globales", 1)
	_space_select.focus_mode = Control.FOCUS_NONE
	_space_select.item_selected.connect(_on_space_selected)
	opts.add_child(_space_select)
	_snap_check = CheckButton.new()
	_snap_check.text = "Imán"
	_snap_check.tooltip_text = "Saltos de 2 cm, 5° y 0,05. Mantén Ctrl para invertirlo."
	_snap_check.focus_mode = Control.FOCUS_NONE
	opts.add_child(_snap_check)
	box.add_child(opts)

	# — Tipo de prenda (qué selector del juego la ofrece) —
	box.add_child(_section("TIPO DE PRENDA"))
	_slot_select = OptionButton.new()
	_slot_select.focus_mode = Control.FOCUS_NONE
	_slot_select.add_item("Camiseta")
	_slot_select.add_item("Pantalón")
	_slot_select.add_item("Zapato")
	_slot_select.item_selected.connect(_on_slot_selected)
	box.add_child(_slot_select)

	# — Hueso —
	box.add_child(_section("SE MUEVE CON"))
	_bone_select = OptionButton.new()
	_bone_select.focus_mode = Control.FOCUS_NONE
	for i in _skel.get_bone_count():
		var n := _skel.get_bone_name(i)
		var skip := false
		for s in SKIP_BONES:
			if n.contains(s):
				skip = true
		if skip:
			continue
		_bone_names.append(n)
		_bone_select.add_item(n.trim_prefix("mixamorig_"))
	_bone_select.item_selected.connect(_on_bone_selected)
	box.add_child(_bone_select)

	# — Transformación —
	box.add_child(_section("POSICIÓN  (m)"))
	for i in 3:
		_axis_row(box, i, -3.0, 3.0, 0.005, " m", _pos_spins, _on_pos_changed)
	box.add_child(_section("ROTACIÓN  (°)"))
	for i in 3:
		_axis_row(box, i, -180.0, 180.0, 1.0, "°", _rot_spins, _on_rot_changed)
	box.add_child(_section("TAMAÑO  (m)"))
	for i in 3:
		_axis_row(box, i, 0.01, 4.0, 0.005, " m", _scl_spins, _on_scl_changed)
	_uniform_check = CheckButton.new()
	_uniform_check.text = "Tamaño uniforme"
	_uniform_check.button_pressed = true
	_uniform_check.focus_mode = Control.FOCUS_NONE
	box.add_child(_uniform_check)

	var turns := HFlowContainer.new()
	turns.add_theme_constant_override("h_separation", 6)
	turns.add_theme_constant_override("v_separation", 6)
	turns.add_child(_button("Girar 90° X", "Gira la prenda 90° sobre su eje X", _turn.bind(Vector3.RIGHT, 90.0)))
	turns.add_child(_button("Girar 90° Y", "Gira la prenda 90° sobre su eje Y", _turn.bind(Vector3.UP, 90.0)))
	turns.add_child(_button("Girar 90° Z", "Gira la prenda 90° sobre su eje Z", _turn.bind(Vector3.BACK, 90.0)))
	turns.add_child(_button("Dar la vuelta", "Gira 180° sobre el eje vertical (delante ↔ detrás)", _turn.bind(Vector3.UP, 180.0)))
	turns.add_child(_button("Espejar pareja", "Zapatos: este pie queda como reflejo del otro (hueso, posición y giro)", _on_mirror_pair))
	turns.add_child(_button("Reencajar", "Vuelve al ajuste automático inicial (sin guardar)", _on_refit))
	box.add_child(turns)

	# — Pose —
	box.add_child(_section("POSE DEL PERSONAJE  (T)"))
	for side in ["Left", "Right"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := _dim_label("Brazo izq." if side == "Left" else "Brazo der.")
		lab.custom_minimum_size.x = 70
		row.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = ARM_MIN
		slider.max_value = ARM_MAX
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		row.add_child(slider)
		var spin := SpinBox.new()
		spin.min_value = ARM_MIN
		spin.max_value = ARM_MAX
		spin.step = 1.0
		spin.suffix = "°"
		spin.custom_minimum_size.x = 96
		spin.share(slider)
		spin.value_changed.connect(_on_arm_changed.bind(side))
		row.add_child(spin)
		box.add_child(row)
		_arm_spins[side] = spin
	_arms_check = CheckButton.new()
	_arms_check.text = "Asas de articulaciones (arrastrar)"
	_arms_check.tooltip_text = "Esferas amarilla (codo), naranja (mano), verde (rodilla) y azul (pie): arrástralas para colocar el miembro donde quieras"
	_arms_check.button_pressed = true
	_arms_check.focus_mode = Control.FOCUS_NONE
	box.add_child(_arms_check)
	_arm_sync = CheckButton.new()
	_arm_sync.text = "Mover los dos brazos a la vez"
	_arm_sync.button_pressed = true
	_arm_sync.focus_mode = Control.FOCUS_NONE
	box.add_child(_arm_sync)
	var pose_row := HBoxContainer.new()
	pose_row.add_theme_constant_override("separation", 6)
	pose_row.add_child(_button("Pose T", "Brazos en horizontal", _set_arms.bind(0.0, 0.0)))
	pose_row.add_child(_button("Brazos abajo", "Brazos caídos a los lados", _set_arms.bind(-80.0, -80.0)))
	pose_row.add_child(_button("Brazos arriba", "Brazos en alto", _set_arms.bind(80.0, 80.0)))
	box.add_child(pose_row)
	for side in ["LeftLeg", "RightLeg"]:
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		var llab := _dim_label("Pierna izq." if side == "LeftLeg" else "Pierna der.")
		llab.custom_minimum_size.x = 70
		lrow.add_child(llab)
		var lslider := HSlider.new()
		lslider.min_value = LEG_MIN
		lslider.max_value = LEG_MAX
		lslider.step = 1.0
		lslider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lslider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lslider.focus_mode = Control.FOCUS_NONE
		lrow.add_child(lslider)
		var lspin := SpinBox.new()
		lspin.min_value = LEG_MIN
		lspin.max_value = LEG_MAX
		lspin.step = 1.0
		lspin.suffix = "°"
		lspin.custom_minimum_size.x = 96
		lspin.share(lslider)
		lspin.value_changed.connect(_on_arm_changed.bind(side))
		lrow.add_child(lspin)
		box.add_child(lrow)
		_arm_spins[side] = lspin
	_leg_sync = CheckButton.new()
	_leg_sync.text = "Mover las dos piernas a la vez"
	_leg_sync.button_pressed = true
	_leg_sync.focus_mode = Control.FOCUS_NONE
	box.add_child(_leg_sync)
	var leg_row := HBoxContainer.new()
	leg_row.add_theme_constant_override("separation", 6)
	leg_row.add_child(_button("Piernas rectas", "Piernas juntas y rectas (reposo)", _set_legs.bind(0.0, 0.0)))
	leg_row.add_child(_button("Piernas abiertas", "Las dos piernas abiertas 30° hacia fuera", _set_legs.bind(30.0, 30.0)))
	box.add_child(leg_row)
	box.add_child(_dim_label("Asas verde (rodilla) y azul (pie): arrástralas para doblar o abrir cada pierna."))
	_body_check = CheckButton.new()
	_body_check.text = "Mostrar cuerpo"
	_body_check.button_pressed = true
	_body_check.focus_mode = Control.FOCUS_NONE
	_body_check.toggled.connect(func(on: bool) -> void: _model.visible = on)
	box.add_child(_body_check)
	_skin_check = CheckButton.new()
	_skin_check.text = "Pegar la prenda al cuerpo (vista previa)"
	_skin_check.tooltip_text = "Así se ve en el juego: la prenda sigue los brazos y el torso. Al editarla vuelve la vista rígida."
	_skin_check.focus_mode = Control.FOCUS_NONE
	_skin_check.toggled.connect(_on_skin_toggled)
	box.add_child(_skin_check)

	# — Vista —
	box.add_child(_section("VISTA"))
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	for v in [["Frente", 0.0, 8.0], ["Lado", 90.0, 8.0], ["Espalda", 180.0, 8.0], ["Arriba", 0.0, 80.0]]:
		var b := _button(v[0], "", set_view.bind(v[1], v[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		views.add_child(b)
	box.add_child(views)
	box.add_child(_button("Centrar en la prenda  (F)", "Enfoca la prenda seleccionada", _focus_selected))

	# — Acciones —
	box.add_child(HSeparator.new())
	var save := Button.new()
	save.text = "Guardar   (Ctrl+S)"
	save.tooltip_text = "Escribe " + ClothingFit.PATH
	save.add_theme_stylebox_override("normal", _box(C_ACCENT.darkened(0.1), 6))
	save.add_theme_stylebox_override("hover", _box(C_ACCENT, 6))
	save.add_theme_stylebox_override("pressed", _box(C_ACCENT.darkened(0.3), 6))
	save.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	save.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.02))
	save.custom_minimum_size.y = 34
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_on_save)
	box.add_child(save)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	for b in [_button("Deshacer", "Ctrl+Z", _do_undo), _button("Rehacer", "Ctrl+Y", _do_redo),
			_button("Recargar", "Descarta los cambios y relee el JSON", _on_reload),
			_button("Cerrar", "Salir del editor", func() -> void:
				_save_state()
				get_tree().quit(0))]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(b)
	box.add_child(acts)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	_status_dot = Panel.new()
	_status_dot.custom_minimum_size = Vector2(9, 9)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(_status_dot)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_status)
	box.add_child(srow)

	var hint := Label.new()
	hint.text = "Vista: clic derecho = orbitar · botón central = desplazar · rueda = zoom\n" \
		+ "Gizmo: W mover · E rotar · R escalar · X ejes · Ctrl = imán · clic en la prenda = elegir\n" \
		+ "Brazos: arrastra la esfera amarilla (codo) o naranja (mano); con \"los dos brazos\" el otro lado se refleja\n" \
		+ "F centrar · 1/3/7 vistas · Ctrl+Z / Ctrl+Y deshacer / rehacer"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	box.add_child(hint)

func _section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", C_ACCENT)
	v.add_child(label)
	v.add_child(HSeparator.new())
	return v

func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", C_TEXT_DIM)
	return label

func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _axis_row(parent: VBoxContainer, axis: int, min_v: float, max_v: float, step: float, suffix: String,
		spins: Array[SpinBox], cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = ["X", "Y", "Z"][axis]
	label.custom_minimum_size.x = 14
	label.add_theme_color_override("font_color", AXIS_COLORS[axis])
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.suffix = suffix
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(cb.bind(axis))
	row.add_child(spin)
	parent.add_child(row)
	spins.append(spin)

func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(5)
	_status_dot.add_theme_stylebox_override("panel", sb)
	_subtitle.text = _pretty(_sel) if _sel != "" else "—"

func _mark_dirty() -> void:
	_dirty = true
	_set_status("Sin guardar", C_WARN)

func _refresh_list() -> void:
	for id in _name_buttons:
		(_name_buttons[id] as Button).set_pressed_no_signal(id == _sel)

## Vuelca la prenda seleccionada en los campos numéricos.
func _show_fields() -> void:
	var it := _selected()
	if it == null or _pos_spins.is_empty():
		return
	_syncing = true
	var deg := it.rot.get_euler() * (180.0 / PI)
	for i in 3:
		_pos_spins[i].value = it.pos[i]
		_rot_spins[i].value = deg[i]
		_scl_spins[i].value = it.scl[i]
	var idx := _bone_names.find(it.bone)
	if idx >= 0:
		_bone_select.select(idx)
	_slot_select.select(ClothingFit.SLOTS.find(it.slot))
	_syncing = false

# ══════════════════════════════════════════════════════════════════════════════
# Callbacks de la UI
# ══════════════════════════════════════════════════════════════════════════════

func _spin_edit_begin() -> Item:
	var it := _selected()
	if it == null:
		return null
	var now := Time.get_ticks_msec()
	if now - _last_spin_push > 800:
		_push_undo()
	_last_spin_push = now
	it.touched = true
	_leave_skin()
	return it

func _on_pos_changed(_v: float, _axis: int) -> void:
	if _syncing:
		return
	var it := _spin_edit_begin()
	if it == null:
		return
	it.pos = Vector3(_pos_spins[0].value, _pos_spins[1].value, _pos_spins[2].value)
	_apply_item(it)
	_mark_dirty()

func _on_rot_changed(_v: float, _axis: int) -> void:
	if _syncing:
		return
	var it := _spin_edit_begin()
	if it == null:
		return
	it.rot = Basis.from_euler(Vector3(_rot_spins[0].value, _rot_spins[1].value, _rot_spins[2].value) * (PI / 180.0))
	_apply_item(it)
	_mark_dirty()

func _on_scl_changed(v: float, axis: int) -> void:
	if _syncing:
		return
	var it := _spin_edit_begin()
	if it == null:
		return
	if _uniform_check.button_pressed:
		var old := maxf(it.scl[axis], 0.0001)
		it.scl *= v / old
		_syncing = true
		for i in 3:
			_scl_spins[i].value = it.scl[i]
		_syncing = false
	else:
		it.scl = Vector3(_scl_spins[0].value, _scl_spins[1].value, _scl_spins[2].value)
	_apply_item(it)
	_mark_dirty()

func _on_space_selected(index: int) -> void:
	_local = index == 0
	_space_select.select(index)

## Cambia la prenda de camiseta a pantalón (o al revés): solo decide en qué selector del juego aparece.
func _on_slot_selected(index: int) -> void:
	if _syncing:
		return
	var it := _selected()
	if it == null or index < 0 or index >= ClothingFit.SLOTS.size():
		return
	_push_undo()
	it.slot = ClothingFit.SLOTS[index]
	it.touched = true
	_mark_dirty()

func _on_bone_selected(index: int) -> void:
	if _syncing:
		return
	var it := _selected()
	if it == null or index < 0 or index >= _bone_names.size():
		return
	_push_undo()
	# El mismo sitio en el mundo: se recalcula el ajuste respecto al hueso nuevo
	var rel := _pose_delta(_bone_names[index]).affine_inverse() * _pose_delta(it.bone)
	it.pos = rel * it.pos
	it.rot = (rel.basis * it.rot).orthonormalized()
	it.bone = _bone_names[index]
	it.touched = true
	_apply_item(it)
	_mark_dirty()

func _turn(axis: Vector3, degrees: float) -> void:
	var it := _selected()
	if it == null:
		return
	_push_undo()
	_leave_skin()
	it.rot = (it.rot * Basis(axis, deg_to_rad(degrees))).orthonormalized()
	it.touched = true
	_apply_item(it)
	_show_fields()
	_mark_dirty()

func _on_refit() -> void:
	var it := _selected()
	if it == null:
		return
	_push_undo()
	_leave_skin()
	_default_fit(it)
	it.touched = true
	_apply_item(it)
	_show_fields()
	_mark_dirty()

func _on_arm_changed(value: float, side: String) -> void:
	if _syncing:
		return
	_arm[side] = value
	_set_arm_angle(side, value)
	if _sync_on(side):
		var other := _mirror(side)
		_arm[other] = value
		_set_arm_angle(other, value)
		_syncing = true
		(_arm_spins[other] as SpinBox).value = value
		_syncing = false
	_apply_pose()
	_capture_arms()

func _set_arms(left: float, right: float) -> void:
	_arm["Left"] = left
	_arm["Right"] = right
	_set_arm_angle("Left", left)
	_set_arm_angle("Right", right)
	_syncing = true
	if not _arm_spins.is_empty():
		(_arm_spins["Left"] as SpinBox).value = left
		(_arm_spins["Right"] as SpinBox).value = right
	_syncing = false
	_apply_pose()
	_capture_arms()

func _set_legs(left: float, right: float) -> void:
	_arm["LeftLeg"] = left
	_arm["RightLeg"] = right
	_set_arm_angle("LeftLeg", left)
	_set_arm_angle("RightLeg", right)
	_syncing = true
	if _arm_spins.has("LeftLeg"):
		(_arm_spins["LeftLeg"] as SpinBox).value = left
		(_arm_spins["RightLeg"] as SpinBox).value = right
	_syncing = false
	_apply_pose()
	_capture_arms()

## Direcciones de las piernas en reposo (se leen del esqueleto sin posar).
func _init_legs() -> void:
	_skel.reset_bone_poses()
	for side in ["LeftLeg", "RightLeg"]:
		var dirs: Array = []
		for pair in ClothingFit.limb_chain(side):
			var b := _skel.find_bone(pair[0])
			var c := _skel.find_bone(pair[1])
			dirs.append((_skel.get_bone_global_pose(c).origin - _skel.get_bone_global_pose(b).origin).normalized() if b >= 0 and c >= 0 else Vector3.DOWN)
		_leg_rest[side] = dirs
		_arm_dir[side] = dirs.duplicate()
		_arm[side] = 0.0

## API para pruebas / capturas.
func set_legs(left: float, right: float) -> void:
	_set_legs(left, right)

# ══════════════════════════════════════════════════════════════════════════════
# Asas de los brazos: arrastra el codo y la mano a donde quieras
# ══════════════════════════════════════════════════════════════════════════════

func _build_arm_handles() -> void:
	for side in ClothingFit.LIMBS:
		for k in 2:
			var mi := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 1.0
			mi.mesh = ball
			mi.material_override = _gmat(_handle_color(side, k))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_arm_handles["%s_%d" % [side, k]] = mi

## Color de un asa: brazos amarillo/naranja (codo/mano), piernas verde/azul (rodilla/pie).
func _handle_color(limb: String, k: int) -> Color:
	if limb.ends_with("Leg"):
		return Color(0.45, 0.95, 0.5, 0.9) if k == 0 else Color(0.35, 0.7, 1.0, 0.9)
	return Color(1.0, 0.85, 0.3, 0.9) if k == 0 else Color(1.0, 0.55, 0.2, 0.9)

## Lado opuesto de un miembro ("Left" <-> "Right", "LeftLeg" <-> "RightLeg").
func _mirror(limb: String) -> String:
	if limb.begins_with("Left"):
		return "Right" + limb.trim_prefix("Left")
	return "Left" + limb.trim_prefix("Right")

func _sync_on(limb: String) -> bool:
	return (_leg_sync if limb.ends_with("Leg") else _arm_sync).button_pressed

## Posición en el mundo del extremo del tramo k (codo o mano) y de su articulación (hombro o codo).
func _arm_points(side: String, k: int) -> Array[Vector3]:
	var chain: Array = ClothingFit.limb_chain(side)[k]
	var end_b := _skel.find_bone(chain[1])
	var joint_b := _skel.find_bone(chain[0])
	var sg := _skel.global_transform
	return [sg * _skel.get_bone_global_pose(end_b).origin, sg * _skel.get_bone_global_pose(joint_b).origin]

func _update_arm_handles() -> void:
	for key in _arm_handles:
		var mi: MeshInstance3D = _arm_handles[key]
		mi.visible = _arms_check.button_pressed and _model.visible
		if not mi.visible:
			continue
		var parts := String(key).split("_")
		var p := _arm_points(parts[0], int(parts[1]))[0]
		mi.global_position = p
		var hot: bool = key == _arm_hover or (_arm_drag != "" and key == _arm_drag)
		mi.scale = Vector3.ONE * _cam.global_position.distance_to(p) * (0.036 if hot else 0.028)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 0.8, 1.0) if hot else _handle_color(parts[0], int(parts[1]))

## Asa de brazo bajo el ratón ("Left_0"…), "" si no hay.
func _pick_arm_handle(mp: Vector2) -> String:
	if not _arms_check.button_pressed or not _model.visible:
		return ""
	var best := ""
	var best_d := PICK_PX + 4.0
	for key in _arm_handles:
		var parts := String(key).split("_")
		var sp: Variant = _screen(_arm_points(parts[0], int(parts[1]))[0])
		if sp != null and mp.distance_to(sp) < best_d:
			best_d = mp.distance_to(sp)
			best = key
	return best

func _begin_arm_drag(key: String) -> void:
	_arm_drag = key
	_arm_drag_plane = _arm_points(key.split("_")[0], int(key.split("_")[1]))[0]

func _update_arm_drag(mp: Vector2) -> void:
	var parts := _arm_drag.split("_")
	var side := String(parts[0])
	var k := int(parts[1])
	var hit: Variant = _ray_plane(_arm_drag_plane, -_cam.global_transform.basis.z, mp)
	if hit == null:
		return
	var joint := _arm_points(side, k)[1]
	var dir := ((hit as Vector3) - joint).normalized()
	if dir.length() < 0.5:
		return
	(_arm_dir[side] as Array)[k] = dir
	if _sync_on(side):
		(_arm_dir[_mirror(side)] as Array)[k] = Vector3(-dir.x, dir.y, dir.z)
	_apply_pose()
	_capture_arms()

## API para scripts de prueba / capturas.
func set_arms(left: float, right: float) -> void:
	_set_arms(left, right)

func set_mode(m: int) -> void:
	_set_mode(m)

## API para pruebas: activa/desactiva la vista pegada.
func set_skin_preview(on: bool) -> void:
	_skin_check.button_pressed = on

## Minimiza la barra de herramientas (queda solo un botón) o la vuelve a mostrar.
func set_sidebar_open(open: bool) -> void:
	_sidebar.visible = open
	_sidebar_btn.text = "◀ Ocultar  (Tab)" if open else "▶ Herramientas  (Tab)"
	_sidebar_btn.offset_left = UI_MARGIN + SIDEBAR_W - 150.0 - 8.0 if open else UI_MARGIN
	_sidebar_btn.offset_right = _sidebar_btn.offset_left + 150.0
	_sidebar_btn.offset_bottom = _sidebar_btn.offset_top + 30.0
	_sidebar_btn.size = Vector2(150, 30)
	_sidebar_btn.position = Vector2(_sidebar_btn.offset_left, _sidebar_btn.offset_top)

func hide_ui() -> void:
	_ui_layer.visible = false

# ══════════════════════════════════════════════════════════════════════════════
# Guardar / recargar
# ══════════════════════════════════════════════════════════════════════════════

## Estado de la sesión (pose de los brazos, prendas visibles, selección y cámara): se guarda aparte del ajuste de las
## prendas y se recupera al abrir el editor.
func _load_state() -> Dictionary:
	var txt := FileAccess.get_file_as_string(STATE_PATH)
	var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
	return parsed if parsed is Dictionary else {}

func _save_state() -> void:
	var arms := _arms_dict()
	var shown: Array = []
	for id in _items:
		if (_items[id] as Item).shown:
			shown.append(id)
	shown.sort()
	var state := {
		"arms": arms, "shown": shown, "selected": _sel,
		"cam": [_yaw, _pitch, _dist, _target.x, _target.y, _target.z],
	}
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, "\t") + "\n")
		f.close()

func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]

## Pose de brazos actual como diccionario guardable.
func _arms_dict() -> Dictionary:
	var arms := {}
	for side in ClothingFit.LIMBS:
		var dirs: Array = _arm_dir[side]
		if side.ends_with("Leg"):
			var rest: Array = _leg_rest[side]
			if is_zero_approx(float(_arm[side])) and (dirs[0] as Vector3).is_equal_approx(rest[0]) and (dirs[1] as Vector3).is_equal_approx(rest[1]):
				continue   # pierna en reposo: no se guarda (así el pegado de las prendas viejas no cambia)
		arms[side] = {"angle": _arm[side], "dirs": [_v3(dirs[0]), _v3(dirs[1])]}
	return arms

## Anota la pose de brazos actual en la prenda seleccionada (se llama cuando el usuario mueve los brazos).
func _capture_arms() -> void:
	var it := _selected()
	if it == null:
		return
	it.arms = _arms_dict()
	it.touched = true
	_mark_dirty()

func _restore_arms(state: Dictionary) -> void:
	_load_arms(state.get("arms", {}))

func _load_arms(arms: Dictionary) -> void:
	for side in ClothingFit.LIMBS:
		var a: Dictionary = arms.get(side, {})
		var dirs: Array = a.get("dirs", [])
		if dirs.size() >= 2:
			_arm_dir[side] = [ClothingFit.vec(dirs[0], Vector3.RIGHT), ClothingFit.vec(dirs[1], Vector3.RIGHT)]
			_arm[side] = float(a.get("angle", 0.0))
		elif side.ends_with("Leg"):
			_arm_dir[side] = (_leg_rest[side] as Array).duplicate()   # sin pose de piernas guardada = reposo
			_arm[side] = 0.0
		else:
			_arm[side] = float(a.get("angle", 0.0))
	_syncing = true
	for side in ClothingFit.LIMBS:
		if _arm_spins.has(side):
			(_arm_spins[side] as SpinBox).value = _arm[side]
	_syncing = false
	_apply_pose()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _skel != null:
		_save_state()

func _on_save() -> void:
	_save_state()
	var all := ClothingFit.load_all()
	for id in _items:
		var it: Item = _items[id]
		if it.touched or all.has(id):
			all[id] = ClothingFit.entry_to_json(it.bone, it.pos, it.rot, it.scl, it.arms, it.slot)
	var err := ClothingFit.save_all(all)
	if err != OK:
		_set_status("ERROR al escribir %s: %s" % [ClothingFit.PATH, error_string(err)], C_ERR)
		push_error(_status.text)
		return
	_fits = all
	_dirty = false
	_set_status("Guardado · " + ClothingFit.PATH, C_OK)

func _on_reload() -> void:
	_fits = ClothingFit.load_all()
	for id in _items:
		var it: Item = _items[id]
		it.touched = false
		if _fits.has(id):
			var e := ClothingFit.parse_entry(_fits[id])
			it.bone = e["bone"]
			it.pos = e["pos"]
			it.rot = e["rot"]
			it.scl = e["scale"]
			it.arms = e["arms"]
		else:
			_default_fit(it)
		_apply_item(it)
	_leave_skin()
	var cur := _selected()
	if cur != null and not cur.arms.is_empty():
		_load_arms(cur.arms)
	_undo.clear()
	_redo.clear()
	_dirty = false
	_show_fields()
	_set_status("Recargado desde el JSON", C_OK)
