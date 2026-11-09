class_name CharacterLookApplier
extends Node

## Aplica una CharacterLook sobre una instancia del modelo base (riva-base.fbx: humano de MakeHuman sobre el
## esqueleto de Riva, ver tools/blender_riva_human.py) — jugador local, jugador remoto o vista previa del menú.
## Se cuelga del modelo como hijo "LookApplier" y se puede volver a llamar (la pantalla de personalización lo
## hace en cada cambio):
##  - Materiales (estilo PS3): piel con textura de detalle, normales y oclusión teñida con el tono elegido
##    (riva_skin.gdshader); ojos con el iris teñido (riva_eye); cejas, pestañas y pelo como tiras con alfa
##    (riva_hair); ropa interior en color plano.
##  - Peinado: el modelo trae una malla por peinado (Pelo_<id>); se muestra solo la elegida.
##  - Proporciones: altura y complexión escalan la raíz del modelo; la cabeza, un SkeletonModifier3D.
##  - Accesorios (gorros, calzado): .glb normalizados a la caja de su región (ver
##    tools/blender_riva_accessories.py) y colgados de un BoneAttachment3D del hueso correspondiente.

const TEX_DIR := "res://assets/textures/entities/riva/humano/"
const DETAIL_PATH := TEX_DIR + "piel.png"    ## miniatura / textura de referencia del personaje
const BODY_NODE := "RivaBase"
const HAIR_PREFIX := "Pelo_"
const SKIN_SHADER := preload("res://assets/shaders/riva_skin.gdshader")
const HAIR_SHADER := preload("res://assets/shaders/riva_hair.gdshader")
const EYE_SHADER := preload("res://assets/shaders/riva_eye.gdshader")
const ACC_DIR := "res://assets/models/riva/accesorios/"
const SHIN_FRACTION := 0.35   ## igual que en tools/blender_riva_accessories.py
## Cascos del equipo (assets/models/riva/cascos/<id>.glb, normalizados por tools/blender_riva_helmets.py) y su ajuste
## a la cabeza (resources/helmet_fit.json, de tools/blender_riva_helmet_fit.py).
const HELMET_DIR := "res://assets/models/riva/cascos/"
const HELMET_FIT_PATH := "res://resources/helmet_fit.json"
## Armaduras del pack embersstorm (assets/models/riva/armaduras/<set>_<pieza>.glb, caja unidad de
## tools/blender_riva_armor.py) y su ajuste a la zona del cuerpo (resources/armor_fit.json: factores y desplazamientos
## relativos a la caja de esa zona). Van rígidas sobre un hueso.
const ARMOR_DIR := "res://assets/models/riva/armaduras/"
const ARMOR_FIT_PATH := "res://resources/armor_fit.json"
const ARMOR_SETS := ["frio", "fuego", "natural", "sombra"]   ## orden estable (la red manda su posición + 1)
## Piezas del set de armadura que se ven según la pechera equipada: peto/espaldar en el torso, hombreras en el hombro y
## pieza del antebrazo. "fit" = clave en armor_fit.json, "bone" = hueso al que van rígidas, "tail" = hueso siguiente (el
## ajuste "t" va de la cabeza del hueso a la de "tail"). Las laterales usan el glb "izq" o "der" según de qué lado del
## torso esté la articulación (así no importa hacia dónde esté el lado izquierdo en la malla).
const ARMOR_PIECES := {
	"pechera": {"fit": "pechera", "bone": "mixamorig_Spine2", "slot": "pechera"},
	"hombrera_izq": {"fit": "hombrera", "bone": "mixamorig_LeftArm", "slot": "pechera"},
	"hombrera_der": {"fit": "hombrera", "bone": "mixamorig_RightArm", "slot": "pechera"},
	"brazo_izq": {"fit": "brazo", "bone": "mixamorig_LeftForeArm", "tail": "mixamorig_LeftHand", "slot": "pechera"},
	"brazo_der": {"fit": "brazo", "bone": "mixamorig_RightForeArm", "tail": "mixamorig_RightHand", "slot": "pechera"},
	# Piernas: van con los PANTALONES equipados (ranura "pantalones"), no con la pechera
	"muslo_izq": {"fit": "muslo", "bone": "mixamorig_LeftUpLeg", "tail": "mixamorig_LeftLeg", "slot": "pantalones"},
	"muslo_der": {"fit": "muslo", "bone": "mixamorig_RightUpLeg", "tail": "mixamorig_RightLeg", "slot": "pantalones"},
	"rodilla_izq": {"fit": "rodilla", "bone": "mixamorig_LeftLeg", "tail": "mixamorig_LeftFoot", "slot": "pantalones"},
	"rodilla_der": {"fit": "rodilla", "bone": "mixamorig_RightLeg", "tail": "mixamorig_RightFoot", "slot": "pantalones"},
	"espinilla_izq": {"fit": "espinilla", "bone": "mixamorig_LeftLeg", "tail": "mixamorig_LeftFoot", "slot": "pantalones"},
	"espinilla_der": {"fit": "espinilla", "bone": "mixamorig_RightLeg", "tail": "mixamorig_RightFoot", "slot": "pantalones"},
}
## Peinados sueltos (assets/models/riva/peinados/<id>.glb): se ajustan solos al tamaño de la cabeza y
## resources/hair_fit.json corrige cada uno: {scale, up, fwd, yaw, tilt, stretch}.
const HAIR_DIR := "res://assets/models/riva/peinados/"
const HAIR_FIT_PATH := "res://resources/hair_fit.json"
const HAIR_WIDTH := 1.3   ## ancho del peinado respecto al de la caja de la cabeza
const TORSO_BONES := ["mixamorig_Spine1", "mixamorig_Spine2"]

const HEAD_BONE := "mixamorig_Head"
const FOOT_BONES := {"L": ["mixamorig_LeftFoot", "mixamorig_LeftToeBase"], "R": ["mixamorig_RightFoot", "mixamorig_RightToeBase"]}
const LEG_BONES := {"L": "mixamorig_LeftLeg", "R": "mixamorig_RightLeg"}

## Material del modelo base -> [shader, ranura de color, texturas (albedo, normal, oclusión)]
const SURFACES := {
	"rb_Piel": ["skin", "skin", ["piel.png", "piel_n.png", "piel_ao.png", "piel_mask.png"]],
	"rb_Calzones": ["cloth", "underwear", []],
	"rb_Elastico": ["cloth", "waistband", []],
	"rb_Ojos": ["eye", "eyes", ["ojos.png"]],
	"rb_Cejas": ["hair", "hair", ["cejas.png"]],
	"rb_Pestanas": ["lash", "", ["pestanas.png"]],
}
## Material de los accesorios (nombre en el .glb) -> ranura de color, según la pieza
const HAT_MATS := {"acc_main": "hat", "acc_second": "hat2", "acc_sole": "hat2", "acc_metal": "hat2"}
const FOOT_MATS := {"acc_main": "shoes", "acc_second": "shoes_accent", "acc_sole": "sole", "acc_metal": "shoes_accent"}

## Cajas de región por malla (se calculan una vez por recurso Mesh)
static var _region_cache: Dictionary = {}

var model: Node3D
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var hair_meshes: Dictionary = {}     ## id de peinado -> MeshInstance3D
var look: CharacterLook
var _base_scale := Vector3.ONE
var _base_pos_y := 0.0
var _head_mod: LookHeadModifier
var _hat_id := ""
var _hat_hair := ""
var _foot_id := ""
var _hair_shown := ""          ## peinado suelto colgado ahora mismo
var _hair_nodes: Array[Node3D] = []
var _hat_nodes: Array[Node3D] = []
var _foot_nodes: Array[Node3D] = []
var _helmet_id := ""            ## casco pedido (de EquipmentDB.helmet_of); "" = ninguno
var _helmet_shown := ""         ## casco colgado ahora mismo
var _helmet_nodes: Array[Node3D] = []
var _armor: Dictionary = {}          ## pieza ("pechera") -> set pedido ("" = ninguno)
var _armor_shown: Dictionary = {}    ## pieza -> set colgado ahora mismo
var _armor_nodes: Dictionary = {}    ## pieza -> Array[Node3D]

static var _helmet_fit: Dictionary = {}
static var _hair_fit: Dictionary = {}
static var _armor_fit: Dictionary = {}

## Aplica `look` al modelo (crea el aplicador la primera vez). Devuelve el aplicador.
static func apply_to(p_model: Node3D, p_look: CharacterLook) -> CharacterLookApplier:
	if p_model == null:
		return null
	var ap := p_model.get_node_or_null("LookApplier") as CharacterLookApplier
	if ap == null:
		ap = CharacterLookApplier.new()
		ap.name = "LookApplier"
		ap._bind(p_model)
		p_model.add_child(ap)
	ap.apply(p_look)
	return ap

func _bind(p_model: Node3D) -> void:
	model = p_model
	_base_scale = model.scale
	_base_pos_y = model.position.y
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	for mi in _meshes(model):
		var n := String(mi.name)
		if n.begins_with(HAIR_PREFIX):
			hair_meshes[n.substr(HAIR_PREFIX.length())] = mi
		elif mesh_instance == null or n.begins_with(BODY_NODE):
			mesh_instance = mi

## La raíz del modelo se reajustó desde fuera (p. ej. _fit_model): toma esa escala como base.
func rebase() -> void:
	_base_scale = model.scale
	_base_pos_y = model.position.y
	if look:
		_apply_proportions()

func apply(p_look: CharacterLook) -> void:
	look = p_look if p_look else CharacterLook.new()
	_apply_material()
	_apply_proportions()
	_apply_accessories()

## Pone (o quita, con "") el casco del equipo. Sustituye al gorro y esconde el pelo si su ajuste lo pide.
static func set_helmet_on(p_model: Node3D, helmet_id: String) -> void:
	var ap := p_model.get_node_or_null("LookApplier") as CharacterLookApplier if p_model else null
	if ap:
		ap.set_helmet(helmet_id)

func set_helmet(helmet_id: String) -> void:
	if helmet_id == _helmet_id:
		return
	_helmet_id = helmet_id
	if look:   # antes de apply() solo se recuerda: apply() lo coloca
		_apply_material()
		_apply_accessories()

## Pone (o quita, con "") el set de armadura del pack ("sombra", "fuego", "frio" o "natural") que va con la pechera
## equipada: `piece` es la ranura ("pechera": peto, hombreras y antebrazos; "pantalones": muslos, rodillas y
## espinillas; ver ARMOR_PIECES) y se ven TODAS las piezas de esa ranura.
static func set_armor_on(p_model: Node3D, piece: String, set_id: String) -> void:
	var ap := p_model.get_node_or_null("LookApplier") as CharacterLookApplier if p_model else null
	if ap:
		ap.set_armor(piece, set_id)

func set_armor(piece: String, set_id: String) -> void:
	if String(_armor.get(piece, "")) == set_id:
		return
	_armor[piece] = set_id
	if look:
		_apply_accessories()

## Ajuste de las armaduras: {pieza: {region, sx, sd, sh, ox, od, oh}} (ver tools/blender_riva_armor.py).
static func armor_fit() -> Dictionary:
	if _armor_fit.is_empty():
		var txt := FileAccess.get_file_as_string(ARMOR_FIT_PATH)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_armor_fit = parsed if parsed is Dictionary else {}
		if _armor_fit.is_empty():
			push_warning("[CharacterLook] sin ajuste de armaduras: " + ARMOR_FIT_PATH)
	return _armor_fit

static func armor_net_index(set_id: String) -> int:
	return ARMOR_SETS.find(set_id) + 1

static func armor_from_net_index(i: int) -> String:
	return String(ARMOR_SETS[i - 1]) if i >= 1 and i <= ARMOR_SETS.size() else ""

## Set pedido para una pieza ("" si no hay, no es un set conocido o falta su ajuste).
func _armor_wanted(piece: String) -> String:
	var set_id := String(_armor.get(String(ARMOR_PIECES[piece]["slot"]), ""))
	if set_id != "" and ARMOR_SETS.has(set_id) and armor_fit().has(String(ARMOR_PIECES[piece]["fit"])):
		return set_id
	return ""

## Ajuste de todos los cascos: {id: {scale, stretch, up, fwd, tilt?, yaw?, hides_hair}} (ver tools/blender_riva_helmet_fit.py).
static func helmet_fit() -> Dictionary:
	if _helmet_fit.is_empty():
		var txt := FileAccess.get_file_as_string(HELMET_FIT_PATH)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_helmet_fit = parsed if parsed is Dictionary else {}
		if _helmet_fit.is_empty():
			push_warning("[CharacterLook] sin ajuste de cascos: " + HELMET_FIT_PATH)
	return _helmet_fit

## Cascos por orden estable (los de helmet_fit.json, ordenados): la red manda su posición + 1 (0 = sin casco).
static func helmet_ids() -> Array:
	var ids: Array = helmet_fit().keys()
	ids.sort()
	return ids

static func helmet_net_index(helmet_id: String) -> int:
	return helmet_ids().find(helmet_id) + 1

static func helmet_from_net_index(i: int) -> String:
	var ids := helmet_ids()
	return String(ids[i - 1]) if i >= 1 and i <= ids.size() else ""

func _helmet_active() -> bool:
	return _helmet_id != "" and helmet_fit().has(_helmet_id) and ResourceLoader.exists(HELMET_DIR + _helmet_id + ".glb")

func _helmet_hides_hair() -> bool:
	return _helmet_active() and bool(helmet_fit()[_helmet_id].get("hides_hair", true))

# ───────────────────────────── material ─────────────────────────────

func _apply_material() -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	mesh_instance.material_override = null
	for i in mesh_instance.mesh.get_surface_count():
		var src := mesh_instance.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		var info: Array = SURFACES.get(key, ["cloth", "skin", []])
		var m := mesh_instance.get_surface_override_material(i) as ShaderMaterial
		if m == null:
			m = _make_material(info[0], info[2])
			mesh_instance.set_surface_override_material(i, m)
		_tint(m, info[0], info[1])
	# Peinado: solo la malla elegida es visible
	for id in hair_meshes:
		var mi: MeshInstance3D = hair_meshes[id]
		mi.visible = id == look.hair_style and not _helmet_hides_hair()
		if not mi.visible or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m == null:
				m = _make_material("hair", ["pelo_%s.png" % id, "pelo_%s_n.png" % id])
				mi.set_surface_override_material(i, m)
			_tint(m, "hair", "hair")

static var _tex_cache: Dictionary = {}

static func _tex(file: String) -> Texture2D:
	var path := TEX_DIR + file
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]

static func _make_material(kind: String, textures: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	match kind:
		"skin", "cloth":
			m.shader = SKIN_SHADER
			m.set_shader_parameter("use_detail", kind == "skin")
			var names := ["albedo_tex", "normal_tex", "ao_tex", "mask_tex"]
			for k in textures.size():
				var t := _tex(textures[k])
				if t:
					m.set_shader_parameter(names[k], t)
		"eye":
			m.shader = EYE_SHADER
			if not textures.is_empty() and _tex(textures[0]):
				m.set_shader_parameter("eye_tex", _tex(textures[0]))
		"hair", "lash":
			m.shader = HAIR_SHADER
			if not textures.is_empty() and _tex(textures[0]):
				m.set_shader_parameter("albedo_tex", _tex(textures[0]))
			if textures.size() > 1 and _tex(textures[1]):
				m.set_shader_parameter("normal_tex", _tex(textures[1]))
				m.set_shader_parameter("use_normal", true)
			if kind == "lash":
				m.set_shader_parameter("alpha_cut", 0.25)
				m.set_shader_parameter("specular", 0.1)
	return m

func _tint(m: ShaderMaterial, kind: String, slot: String) -> void:
	match kind:
		"skin", "cloth":
			m.set_shader_parameter("tint", look.color(slot))
			m.set_shader_parameter("brow_tint", look.color("hair"))
		"eye":
			m.set_shader_parameter("iris_color", look.color(slot))
		"hair":
			m.set_shader_parameter("tint", look.color(slot))
		"lash":
			m.set_shader_parameter("tint", look.color("hair").darkened(0.6))

# ───────────────────────────── proporciones ─────────────────────────────

func _apply_proportions() -> void:
	model.scale = _base_scale * Vector3(look.build, look.height, look.build)
	model.position.y = _base_pos_y * look.height
	if skeleton == null:
		return
	if _head_mod == null:
		_head_mod = LookHeadModifier.new()
		_head_mod.name = "LookHeadModifier"
		skeleton.add_child(_head_mod)
	# La complexión ensancha todo el cuerpo: la cabeza se compensa para no quedar achatada
	_head_mod.head_scale = Vector3(look.head / look.build, look.head, look.head / look.build)

# ───────────────────────────── accesorios ─────────────────────────────

func _apply_accessories() -> void:
	if skeleton == null or mesh_instance == null:
		return
	var regions := region_boxes(mesh_instance, skeleton)
	if regions.is_empty():
		return
	var hair_wanted: String = look.hair_style if _loose_hair(look.hair_style) and not _helmet_hides_hair() else ""
	if hair_wanted != _hair_shown:
		_free_all(_hair_nodes)
		_hair_shown = hair_wanted
		if _hair_shown != "":
			_attach_hair(_hair_shown, regions["head"])
	var hat_wanted: String = "ninguno" if _helmet_active() else look.hat   # el casco sustituye al gorro
	if hat_wanted != _hat_id or look.hair_style != _hat_hair:
		_free_all(_hat_nodes)
		_hat_id = hat_wanted
		_hat_hair = look.hair_style
		if _hat_id != "ninguno":
			_attach(_hat_id, HEAD_BONE, _head_box(regions["head"]), false, _hat_nodes)
	var helmet_wanted := _helmet_id if _helmet_active() else ""
	if helmet_wanted != _helmet_shown:
		_free_all(_helmet_nodes)
		_helmet_shown = helmet_wanted
		if _helmet_shown != "":
			_attach_helmet(_helmet_shown, regions["head"])
	for piece in ARMOR_PIECES:
		var armor_wanted := _armor_wanted(piece)
		if armor_wanted != String(_armor_shown.get(piece, "")):
			if _armor_nodes.has(piece):
				var old: Array[Node3D] = _armor_nodes[piece]
				_free_all(old)
			_armor_shown[piece] = armor_wanted
			if armor_wanted != "":
				_attach_armor(piece, armor_wanted, regions)
	if look.footwear != _foot_id:
		_free_all(_foot_nodes)
		_foot_id = look.footwear
		if _foot_id != "descalzo":
			for side in ["L", "R"]:
				var mirror: bool = regions["mirror_" + side]
				_attach(_foot_id, FOOT_BONES[side][0], regions["foot_" + side], mirror, _foot_nodes)
				_attach(_foot_id + "_cana", LEG_BONES[side], regions["shin_" + side], mirror, _foot_nodes)
	for n in _hair_nodes:
		for mi in _meshes(n):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i) as StandardMaterial3D
				if m:
					m.albedo_color = look.color("hair")
	_color_nodes(_hat_nodes, HAT_MATS)
	_color_nodes(_foot_nodes, FOOT_MATS)

## Caja de la cabeza para el gorro: la de la cabeza con el peinado visible (la malla del pelo comparte el
## espacio de la del cuerpo).
func _head_box(head: AABB) -> AABB:
	var mi: MeshInstance3D = hair_meshes.get(look.hair_style)
	if mi == null or mi.mesh == null:
		return head
	var hb := mi.mesh.get_aabb()
	# Solo se ensancha hacia arriba y a los lados (una coleta no debe agrandar el gorro hacia atrás)
	var out := head
	out = out.expand(Vector3(hb.position.x, head.position.y, head.get_center().z))
	out = out.expand(Vector3(hb.end.x, hb.end.y, head.get_center().z))
	return out

static func hair_fit() -> Dictionary:
	if _hair_fit.is_empty():
		var txt := FileAccess.get_file_as_string(HAIR_FIT_PATH)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_hair_fit = parsed if parsed is Dictionary else {}
	return _hair_fit

## ¿Es un peinado suelto (modelo aparte) y no una malla del modelo base?
static func _loose_hair(id: String) -> bool:
	return not id.is_empty() and ResourceLoader.exists(HAIR_DIR + id + ".glb")

## Caja (en el espacio de `root`) de todas las mallas bajo `root`, con las transformaciones de sus nodos.
static func _tree_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Peinado suelto: escala uniforme para que su ancho sea HAIR_WIDTH x el de la cabeza, centrado en ella y con su
## tope sobre la coronilla. Ajustes opcionales en hair_fit.json (anchos de cabeza W): scale (factor extra),
## up, fwd, yaw/tilt/roll (grados; roll + = la cabeza del peinado cae a la izquierda de la pantalla), stretch (alto) y wide (ancho).
func _attach_hair(hair_id: String, box: AABB) -> void:
	var bind: Variant = _bind_pose(HEAD_BONE)
	if skeleton.find_bone(HEAD_BONE) < 0 or bind == null:
		return
	var fit: Dictionary = hair_fit().get(hair_id, {})
	var att := BoneAttachment3D.new()
	att.name = "Acc_hair_" + hair_id
	att.bone_name = HEAD_BONE
	skeleton.add_child(att)
	var inst := (load(HAIR_DIR + hair_id + ".glb") as PackedScene).instantiate() as Node3D
	att.add_child(inst)
	var hb := _tree_aabb(inst)
	var w := box.size.x
	var kf := float(fit.get("scale", 1.0)) * HAIR_WIDTH
	var kx := kf * w / maxf(hb.size.x, 0.001) * float(fit.get("wide", 1.0))
	var kz := kf * box.size.z / maxf(hb.size.z, 0.001)   # la cabeza es más honda que ancha
	var ky := sqrt(kx * kz) * float(fit.get("stretch", 1.0))
	var basis := Basis(Vector3.UP, -deg_to_rad(float(fit.get("yaw", 0.0)))) * Basis(Vector3(0, 0, 1), deg_to_rad(float(fit.get("roll", 0.0)))) * Basis(Vector3.RIGHT, deg_to_rad(float(fit.get("tilt", 0.0)))) 		* Basis.from_scale(Vector3(kx, ky, kz))
	var anchor := Vector3(hb.get_center().x, hb.end.y, hb.get_center().z)   # tope y centro del peinado
	var target := Vector3(box.get_center().x, box.end.y + float(fit.get("up", 0.1)) * w,
		box.get_center().z + float(fit.get("fwd", 0.0)) * w)
	inst.transform = (bind as Transform3D) * Transform3D(basis, target - basis * anchor)
	for mi in _meshes(inst):
		mi.set_meta("look_acc", true)
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			m.roughness = 0.7
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, m)
	_hair_nodes.append(att)

func _attach(acc_id: String, bone_name: String, box: AABB, mirror: bool, into: Array[Node3D]) -> void:
	var path := ACC_DIR + acc_id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[CharacterLook] falta el accesorio " + path)
		return
	var bone := skeleton.find_bone(bone_name)
	var bind: Variant = _bind_pose(bone_name)
	if bone < 0 or bind == null:
		return
	var att := BoneAttachment3D.new()
	att.name = "Acc_" + acc_id + ("_R" if bone_name.contains("Right") else "_L")
	att.bone_name = bone_name
	skeleton.add_child(att)
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	att.add_child(inst)
	# Coordenadas normalizadas del accesorio -> espacio de la malla (caja de la región) -> espacio del hueso
	var basis := Basis.from_scale(Vector3(box.size.x * (-1.0 if mirror else 1.0), box.size.y, box.size.z))
	var origin := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	inst.transform = (bind as Transform3D) * Transform3D(basis, origin)
	for mi in _meshes(inst):
		mi.set_meta("look_acc", true)
	into.append(att)

## Casco: a diferencia de los gorros, ESCALA UNIFORME (los cuernos no se estiran) y colocado con el ajuste de
## helmet_fit.json, expresado en anchos de la caja de la cabeza (W): escala k·W, fondo del casco a `up`·W sobre el
## fondo de la caja, `fwd`·W hacia la cara, inclinación `tilt` (+ = hacia delante) y giro `yaw` (+ = a la derecha
## del personaje). Cuelga del hueso de la cabeza, así que sigue el deslizador de cabeza.
func _attach_helmet(helmet_id: String, box: AABB) -> void:
	var fit: Dictionary = helmet_fit()[helmet_id]
	var bone_name := HEAD_BONE
	var bind: Variant = _bind_pose(bone_name)
	if skeleton.find_bone(bone_name) < 0 or bind == null:
		return
	var att := BoneAttachment3D.new()
	att.name = "Acc_helmet_" + helmet_id
	att.bone_name = bone_name
	skeleton.add_child(att)
	var inst := (load(HELMET_DIR + helmet_id + ".glb") as PackedScene).instantiate() as Node3D
	att.add_child(inst)
	var w := box.size.x
	var k := float(fit.get("scale", 1.0)) * w
	var basis := Basis(Vector3.UP, -deg_to_rad(float(fit.get("yaw", 0.0)))) \
		* Basis(Vector3.RIGHT, deg_to_rad(float(fit.get("tilt", 0.0)))) \
		* Basis.from_scale(Vector3(k, k * float(fit.get("stretch", 1.0)), k))
	var origin := Vector3(box.get_center().x, box.position.y + float(fit.get("up", 0.0)) * w,
		box.get_center().z + float(fit.get("fwd", 0.0)) * w)
	inst.transform = (bind as Transform3D) * Transform3D(basis, origin)
	for mi in _meshes(inst):
		mi.set_meta("look_acc", true)
	_helmet_nodes.append(att)

## Armadura: la pieza está en una caja unidad (x -0.5..0.5, y 0..1, z -0.5..0.5, frente +Z) y cuelga rígida de un hueso.
## Dos formas de ajuste en armor_fit.json:
##  - region "torso" (la pechera): se estira a la caja de esa región (sx/sh/sd = ancho/alto/fondo respecto a ella;
##    ox/oh/od = desplazamiento en anchos/altos/fondos de la caja, `oh` desde el fondo y `od` hacia delante).
##  - region "joint" (hombreras, antebrazos): tamaño y desplazamiento en ANCHOS DEL TORSO, partiendo de la articulación
##    del hueso (con "t" entre ese hueso y el siguiente); `ox` hacia fuera, `roll` = caída del borde exterior (grados).
##    La pieza ya viene enderezada de pose A a pose T (tools/blender_riva_armor.py).
func _attach_armor(piece: String, set_id: String, regions: Dictionary) -> void:
	var def: Dictionary = ARMOR_PIECES[piece]
	var fit: Dictionary = armor_fit()[def["fit"]]
	var torso: AABB = regions.get("torso", AABB())
	var bone_name: String = def["bone"]
	var bind: Variant = _bind_pose(bone_name)
	if torso.size == Vector3.ZERO or skeleton.find_bone(bone_name) < 0 or bind == null:
		return
	var file := piece
	var basis: Basis
	var origin: Vector3
	if String(fit.get("region", "torso")) == "torso":
		basis = Basis.from_scale(Vector3(torso.size.x * float(fit.get("sx", 1.0)), torso.size.y * float(fit.get("sh", 1.0)),
			torso.size.z * float(fit.get("sd", 1.0))))
		origin = Vector3(torso.get_center().x + float(fit.get("ox", 0.0)) * torso.size.x,
			torso.position.y + float(fit.get("oh", 0.0)) * torso.size.y,
			torso.get_center().z + float(fit.get("od", 0.0)) * torso.size.z)
	else:
		var w := torso.size.x
		var joint: Vector3 = (bind as Transform3D).affine_inverse().origin   # cabeza del hueso en el espacio de la malla
		var t := float(fit.get("t", 0.0))
		if t != 0.0 and def.has("tail"):
			var tail_bind: Variant = _bind_pose(String(def["tail"]))
			if tail_bind == null:
				return
			joint = joint.lerp((tail_bind as Transform3D).affine_inverse().origin, t)
		var out_sign := 1.0 if joint.x >= torso.get_center().x else -1.0   # hacia fuera del cuerpo
		file = String(def["fit"]) + ("_izq" if out_sign > 0.0 else "_der")   # el glb con su borde exterior hacia ese lado
		basis = Basis(Vector3(0, 0, 1), -out_sign * deg_to_rad(float(fit.get("roll", 0.0)))) \
			* Basis.from_scale(Vector3(w * float(fit.get("sx", 1.0)), w * float(fit.get("sh", 1.0)), w * float(fit.get("sd", 1.0))))
		origin = joint + Vector3(out_sign * float(fit.get("ox", 0.0)) * w, float(fit.get("oh", 0.0)) * w, float(fit.get("od", 0.0)) * w)
	var path := ARMOR_DIR + set_id + "_" + file + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[CharacterLook] falta la armadura " + path)
		return
	var att := BoneAttachment3D.new()
	att.name = "Acc_armor_%s_%s" % [piece, set_id]
	att.bone_name = bone_name
	skeleton.add_child(att)
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	att.add_child(inst)
	inst.transform = (bind as Transform3D) * Transform3D(basis, origin)
	for mi in _meshes(inst):
		mi.set_meta("look_acc", true)
	var list: Array[Node3D] = _armor_nodes.get(piece, [] as Array[Node3D])
	list.append(att)
	_armor_nodes[piece] = list

func _color_nodes(nodes: Array[Node3D], mat_slots: Dictionary) -> void:
	for n in nodes:
		for mi in _meshes(n):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				var key: String = src.resource_name if src else "acc_main"
				var m := mi.get_surface_override_material(i) as StandardMaterial3D
				if m == null:
					m = StandardMaterial3D.new()
					m.roughness = 0.85
					mi.set_surface_override_material(i, m)
				m.albedo_color = look.color(mat_slots.get(key, mat_slots["acc_main"]))

func _free_all(nodes: Array[Node3D]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	nodes.clear()

func _bind_pose(bone_name: String) -> Variant:
	var skin := mesh_instance.skin
	if skin == null:
		var b := skeleton.find_bone(bone_name)
		return skeleton.get_bone_global_rest(b).affine_inverse() if b >= 0 else null
	for i in skin.get_bind_count():
		if _bind_name(skin, i) == bone_name:
			return skin.get_bind_pose(i)
	return null

func _bind_name(skin: Skin, i: int) -> String:
	var n := String(skin.get_bind_name(i))
	if n == "" and skeleton:
		var b := skin.get_bind_bone(i)
		n = skeleton.get_bone_name(b) if b >= 0 and b < skeleton.get_bone_count() else ""
	return n

## Cajas (espacio de la malla, pose de enlace) de la cabeza, cada pie y cada espinilla, con la misma regla
## que el script de Blender: hueso dominante de cada vértice.
static func region_boxes(mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	var mesh := mi.mesh
	if mesh == null or mi.skin == null:
		return {}
	if _region_cache.has(mesh):
		return _region_cache[mesh]
	var skin := mi.skin
	var bind_names: Array[String] = []
	for i in skin.get_bind_count():
		var n := String(skin.get_bind_name(i))
		if n == "":
			var b := skin.get_bind_bone(i)
			n = skel.get_bone_name(b) if b >= 0 and b < skel.get_bone_count() else ""
		bind_names.append(n)
	var pts := {"head": PackedVector3Array(), "foot_L": PackedVector3Array(), "foot_R": PackedVector3Array(),
		"leg_L": PackedVector3Array(), "leg_R": PackedVector3Array(), "torso": PackedVector3Array()}
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		for v in verts.size():
			var best := -1
			var bw := -1.0
			for k in per:
				var w := weights[v * per + k]
				if w > bw:
					bw = w
					best = bones[v * per + k]
			var bn: String = bind_names[best] if best >= 0 and best < bind_names.size() else ""
			var key := ""
			if bn == HEAD_BONE:
				key = "head"
			elif bn in FOOT_BONES["L"]:
				key = "foot_L"
			elif bn in FOOT_BONES["R"]:
				key = "foot_R"
			elif bn == LEG_BONES["L"]:
				key = "leg_L"
			elif bn == LEG_BONES["R"]:
				key = "leg_R"
			elif bn in TORSO_BONES:
				key = "torso"
			if key != "":
				pts[key].append(verts[v])
	for k in pts:
		if pts[k].is_empty():
			push_warning("[CharacterLook] región vacía: " + k)
			_region_cache[mesh] = {}
			return {}
	var out := {"head": _aabb(pts["head"]), "torso": _aabb(pts["torso"])}
	var left_x := 0.0
	for side in ["L", "R"]:
		out["foot_" + side] = _aabb(pts["foot_" + side])
		var leg := _aabb(pts["leg_" + side])
		var cut := leg.position.y + SHIN_FRACTION * leg.size.y
		var shin := PackedVector3Array()
		for p in pts["leg_" + side]:
			if p.y <= cut:
				shin.append(p)
		out["shin_" + side] = _aabb(shin)
	# El modelo de calzado es del pie IZQUIERDO, que en Blender está en +X: el lado contrario se refleja
	left_x = (out["foot_L"] as AABB).get_center().x
	out["mirror_L"] = left_x < 0.0
	out["mirror_R"] = not out["mirror_L"]
	_region_cache[mesh] = out
	return out

static func _aabb(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box

## Malla del cuerpo de un modelo (en el personaje personalizable hay además una malla por peinado): la que se
## llama RivaBase o, si no, la primera que no es de pelo. Sirve para ajustar la altura del modelo.
static func body_mesh(root: Node) -> MeshInstance3D:
	var first: MeshInstance3D = null
	for mi in _meshes(root):
		var n := String(mi.name)
		if n.begins_with(BODY_NODE):
			return mi
		if first == null and not n.begins_with(HAIR_PREFIX):
			first = mi
	return first

static func _find(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for c in root.get_children():
		var r := _find(c, type_name)
		if r:
			return r
	return null

static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out
