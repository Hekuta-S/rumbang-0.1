class_name ClothingFit
extends RefCounted

## Ajuste de la ropa (camisas, pantalones, zapatos…) sobre el cuerpo de Riva. Lo escribe tools/clothing_editor.tscn
## en resources/clothing_fit.json y lo puede leer el juego para colgar cada prenda de su hueso.
##
## Cada prenda (assets/models/riva/ropa/<id>.glb) se "normaliza" al cargarla (ver normalized()): centrada en el origen y
## con su lado mayor midiendo 1. Su ajuste es esa pieza normalizada colocada en el cuerpo:
##   {"bone": "mixamorig_Spine2", "pos": [x, y, z], "rot": [x°, y°, z°], "scale": [x, y, z]}
## Posición y escala están en METROS para un personaje de BODY_HEIGHT m (altura 1.0) y en el espacio del esqueleto en
## reposo (origen en los pies, Y arriba, el pecho mira a +Z). Rotación: ángulos de Euler (orden YXZ de Godot) en grados.
## Para colgarla en el juego, con ms = metros por unidad del esqueleto (BODY_HEIGHT / altura de la malla del cuerpo):
##   inst.transform = skin.get_bind_pose(hueso) * ClothingFit.skeleton_transform(entry, ms)

const DIR := "res://assets/models/riva/ropa/"
const PATH := "res://resources/clothing_fit.json"
const BODY_HEIGHT := 1.7
const DEFAULT_BONE := "mixamorig_Spine2"

## Ids de las prendas que hay en DIR (nombre del .glb sin extensión), ordenados.
static func garment_ids() -> Array[String]:
	var out: Array[String] = []
	for f in ResourceLoader.list_directory(DIR):
		var file := String(f)
		if file.ends_with(".glb"):
			out.append(file.get_basename())
	out.sort()
	# Cada zapato trae un solo pie: se añade su gemelo espejado para colocar el otro
	var all := load_all()
	var with_twins: Array[String] = []
	for id in out:
		with_twins.append(id)
		if slot_of(id, all.get(id, {})) == SLOT_SHOES:
			with_twins.append(id + TWIN)
	return with_twins

static var _cache: Dictionary = {}
static var _cache_loaded := false

## Ajustes guardados (con caché): es lo que usa el juego. El editor usa load_all() para ver siempre lo último.
static func fits() -> Dictionary:
	if not _cache_loaded:
		_cache = load_all()
		_cache_loaded = true
	return _cache

static func reload_fits() -> void:
	_cache_loaded = false

const SLOT_SHIRT := "shirt"
const SLOT_PANTS := "pants"
const SLOT_SHOES := "shoes"
const SLOTS := [SLOT_SHIRT, SLOT_PANTS, SLOT_SHOES]
## Un .glb de zapato trae UN solo pie. El editor lo clona: "<id>" es el original y "<id>__der" su gemelo espejado,
## cada uno con su propio ajuste (así se colocan los dos pies por separado).
const TWIN := "__der"
const SHOE_WORDS := ["zapato", "shoe", "converse", "bota", "sneaker", "tenis"]
const PANTS_BONE := "mixamorig_Hips"
const PANTS_WORDS := ["pantalon", "pants", "jean", "short", "falda", "trouser"]

## Ranura de una prenda: la que dice su ajuste ("slot") o, si no la trae, la que sugiere el nombre del .glb
## (pantalon_*, jeans_*, short_*… = pantalones; lo demás = camiseta).
static func slot_of(id: String, entry: Dictionary = {}) -> String:
	var s := String(entry.get("slot", ""))
	if SLOTS.has(s):
		return s
	id = base_id(id).to_lower()
	for w in SHOE_WORDS:
		if id.contains(w):
			return SLOT_SHOES
	for w in PANTS_WORDS:
		if id.contains(w):
			return SLOT_PANTS
	return SLOT_SHIRT

static func is_twin(id: String) -> bool:
	return id.ends_with(TWIN)

## Id del .glb de una prenda (el gemelo comparte el del original).
static func base_id(id: String) -> String:
	return id.trim_suffix(TWIN)

## El otro pie del par: "<id>" <-> "<id>__der".
static func twin_id(id: String) -> String:
	return base_id(id) if is_twin(id) else id + TWIN

## Prendas con ajuste guardado y modelo disponible: son las que se pueden elegir en el juego.
## `slot` ("shirt"/"pants") filtra por ranura; vacío = todas.
static func fitted_ids(slot: String = "") -> Array[String]:
	var out: Array[String] = []
	var all := fits()
	for id in all:
		if ResourceLoader.exists(DIR + String(id) + ".glb") \
				and (slot == "" or slot_of(String(id), all[id]) == slot):
			out.append(String(id))
	out.sort()
	return out

static func pretty(id: String) -> String:
	var n := base_id(id).replace("_", " ").capitalize()
	return n + " (pie der.)" if is_twin(id) else n

## Lee todos los ajustes guardados: id -> entrada (diccionario vacío si no hay archivo).
static func load_all() -> Dictionary:
	var txt := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
	return parsed if parsed is Dictionary else {}

static func save_all(all: Dictionary) -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var keys := all.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = all[k]
	file.store_string(JSON.stringify(ordered, "\t") + "\n")
	file.close()
	return OK

static func vec(v: Variant, fallback: Vector3) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback

## Entrada del JSON -> {"bone", "pos" (m), "rot" (Basis), "scale" (m)}.
static func parse_entry(e: Dictionary) -> Dictionary:
	var deg := vec(e.get("rot"), Vector3.ZERO)
	return {
		"bone": String(e.get("bone", DEFAULT_BONE)),
		"pos": vec(e.get("pos"), Vector3(0, 1.2, 0)),
		"rot": Basis.from_euler(deg * (PI / 180.0)),
		"scale": vec(e.get("scale"), Vector3.ONE * 0.6),
		"arms": e.get("arms", {}) if e.get("arms", {}) is Dictionary else {},
	}

## `arms` (opcional): la pose de brazos con la que se ajustó la prenda, {"Left"/"Right": {"angle", "dirs": [[x,y,z], [x,y,z]]}}
## (dirección del brazo y del antebrazo). El editor la recupera al elegir la prenda.
static func entry_to_json(bone: String, pos: Vector3, rot: Basis, scl: Vector3, arms: Dictionary = {}, slot: String = "") -> Dictionary:
	var deg := rot.get_euler() * (180.0 / PI)
	var out := {
		"bone": bone,
		"pos": [snappedf(pos.x, 0.0001), snappedf(pos.y, 0.0001), snappedf(pos.z, 0.0001)],
		"rot": [snappedf(deg.x, 0.001), snappedf(deg.y, 0.001), snappedf(deg.z, 0.001)],
		"scale": [snappedf(scl.x, 0.0001), snappedf(scl.y, 0.0001), snappedf(scl.z, 0.0001)],
	}
	if not arms.is_empty():
		out["arms"] = arms
	if slot != "":
		out["slot"] = slot
	return out

## Transformación de la prenda normalizada en el espacio del esqueleto en reposo (unidades del esqueleto).
static func skeleton_transform(entry: Dictionary, ms: float) -> Transform3D:
	var e := parse_entry(entry)
	var basis: Basis = (e["rot"] as Basis) * Basis.from_scale((e["scale"] as Vector3) / ms)
	return Transform3D(basis, (e["pos"] as Vector3) / ms)

## Carga una prenda y la devuelve en un Node3D cuya malla queda centrada en el origen y con su lado mayor = 1.
## Devuelve {"node": Node3D, "extent": Vector3 (tamaño normalizado)} o {} si no se puede cargar.
static func normalized(id: String) -> Dictionary:
	var path := DIR + base_id(id) + ".glb"
	var res: Variant = load(path) if ResourceLoader.exists(path) else null
	if not (res is PackedScene):
		return {}
	var inst := (res as PackedScene).instantiate() as Node3D
	var wrap := Node3D.new()
	wrap.name = "Prenda_" + id
	wrap.add_child(inst)
	var box := _tree_aabb(inst)
	if box.size == Vector3.ZERO:
		wrap.free()
		return {}
	var k := 1.0 / maxf(box.size[box.get_longest_axis_index()], 0.0001)
	if is_twin(id):
		# Gemelo: el mismo modelo reflejado en X (el otro pie)
		var m := Vector3(-1, 1, 1)
		inst.transform = Transform3D(Basis.from_scale(m * k), m * (-box.get_center() * k))
	else:
		inst.transform = Transform3D(Basis.from_scale(Vector3.ONE * k), -box.get_center() * k)
	return {"node": wrap, "extent": box.size * k}

# ───────────── Prenda "pegada" al cuerpo (skinning por vecindad) ─────────────
## Las prendas son mallas rígidas: para que sigan al cuerpo y a los brazos se coloca la malla con su ajuste y a cada
## vértice se le dan los pesos de hueso del cuerpo tomados de un campo 3D (cada celda apunta al vértice del cuerpo más
## cercano, y se mezclan las 8 celdas de alrededor: la transición entre, p. ej., el brazo y el torso es suave).
## El resultado se cuelga del Skeleton3D con el mismo Skin que el cuerpo.

const FIELD_CELLS := 110    ## celdas del campo de pesos a lo alto del cuerpo (~1,5 cm)
const FIELD_PAD := 6         ## celdas de margen alrededor del cuerpo
const SKIN_EYES := "rb_Ojos"  ## superficie del cuerpo que no cuenta (ojos)

static var _body_cache: Dictionary = {}
static var _skin_cache: Dictionary = {}

## Malla(s) de la prenda `id` con su ajuste `entry` y los pesos del cuerpo `body` (MeshInstance3D con Skin).
## `ms` = metros por unidad del esqueleto. Devuelve MeshInstance3D sueltos (sin añadir al árbol); se cachea la malla.
static func build_skinned(id: String, entry: Dictionary, body: MeshInstance3D, ms: float) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if body == null or body.mesh == null or body.skin == null:
		return out
	var t := skeleton_transform(entry, ms)
	var arms: Dictionary = parse_entry(entry)["arms"]
	if arms.is_empty() and slot_of(id, entry) == SLOT_SHOES:
		# Un pie sin pose guardada se colocó con las piernas como las dejó su pareja (el editor conserva la pose)
		arms = parse_entry(fits().get(twin_id(id), {}))["arms"]
	var arms_key := JSON.stringify(arms, "", true)
	var key := "%s|%s|%s|%s" % [id, str(t), arms_key, body.mesh.get_instance_id()]
	if not _skin_cache.has(key):
		var disk := "%s_%s" % [id, ("v%d|%s|%s|%d" % [SKIN_VERSION, str(t), arms_key, (body.mesh.get_aabb().size.y * 1000000.0)]).md5_text().substr(0, 12)]
		var meshes := _load_baked(disk)
		if meshes.is_empty():
			meshes = _skin_meshes(id, t, body, arms, String(parse_entry(entry)["bone"]) if slot_of(id, entry) == SLOT_SHOES else "")
			_save_baked(disk, meshes)
		_skin_cache[key] = meshes
	for m in _skin_cache[key]:
		var mi := MeshInstance3D.new()
		mi.name = "Prenda_" + id
		mi.mesh = m
		mi.skin = body.skin
		mi.extra_cull_margin = 5.0   # la malla se mueve con los huesos: su caja estática no vale
		out.append(mi)
	return out

static func clear_skin_cache() -> void:
	_skin_cache.clear()

## Las mallas pegadas se guardan en disco (user://clothing_skin): construir una prenda pesada tarda unos segundos y
## solo hace falta la primera vez con cada ajuste. SKIN_VERSION invalida lo guardado si cambia el algoritmo.
const SKIN_VERSION := 7
const SKIN_DIR := "user://clothing_skin/"

static func _load_baked(name: String) -> Array:
	var out: Array = []
	var i := 0
	while ResourceLoader.exists("%s%s_%d.res" % [SKIN_DIR, name, i]):
		var m := ResourceLoader.load("%s%s_%d.res" % [SKIN_DIR, name, i], "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE)
		if m == null:
			return []
		out.append(m)
		i += 1
	return out

static func _save_baked(name: String, meshes: Array) -> void:
	for m in meshes:
		if (m as ArrayMesh).get_surface_count() == 0:
			return   # una malla vacía (fallo al construir) no se guarda: se quedaría fija en la caché
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SKIN_DIR))
	for i in meshes.size():
		ResourceSaver.save(meshes[i], "%s%s_%d.res" % [SKIN_DIR, name, i])

## Con pose de brazos (`arms`, la del editor al ajustar la prenda): la prenda se colocó sobre el cuerpo con los brazos en
## esa pose, así que los pesos se toman del cuerpo EN ESA POSE y cada vértice se lleva luego a la pose de reposo
## deshaciendo su mezcla de huesos (inversa del skinning). Así las mangas quedan pegadas a los brazos y no al torso.
static func _skin_meshes(id: String, t: Transform3D, body: MeshInstance3D, arms: Dictionary = {}, shoe_bone: String = "") -> Array:
	var n := normalized(id)
	if n.is_empty():
		return []
	var wrap: Node3D = n["node"]
	# Zapatos: siempre se deshace la mezcla de huesos del reposo (los pesos del cuerpo no son la identidad en reposo)
	var pose := _arm_pose(body, arms, shoe_bone != "")
	var data := _body_data(body, pose)
	var mats: Array = pose.get("mats", [])
	var meshes: Array = []
	for node in wrap.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := t * _path_xf(mi, wrap)
		var nb := xf.basis.inverse().transposed()
		var am := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			# Datos propios del importador (CUSTOM0-3, p. ej. de modelos de Sketchfab) no hacen falta y rompen add_surface_from_arrays
			for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arr[ci] = null
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nv := PackedVector3Array()
			nv.resize(v.size())
			var bones := PackedInt32Array()
			bones.resize(v.size() * 4)
			var weights := PackedFloat32Array()
			weights.resize(v.size() * 4)
			if xf.basis.determinant() < 0.0 and arr[Mesh.ARRAY_INDEX] != null:
				# Reflejado (pie gemelo): se invierte el orden de los triángulos para que no queden del revés
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				for q in range(0, idx.size() - 2, 3):
					var tmp := idx[q + 1]
					idx[q + 1] = idx[q + 2]
					idx[q + 2] = tmp
				arr[Mesh.ARRAY_INDEX] = idx
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var ts: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var has_n := ns.size() == v.size()
			var has_t := ts.size() == v.size() * 4
			for i in v.size():
				var p := xf * v[i]
				_weights_for(p, data, bones, weights, i)
				var nrm := (nb * ns[i]).normalized() if has_n else Vector3.ZERO
				var tan := (xf.basis * Vector3(ts[i * 4], ts[i * 4 + 1], ts[i * 4 + 2])).normalized() if has_t else Vector3.ZERO
				if not mats.is_empty():
					# Mezcla de huesos de este vértice en la pose del ajuste -> se deshace para llevarlo al reposo
					var m := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
					for slot in 4:
						var w := weights[i * 4 + slot]
						if w > 0.0:
							var bm: Transform3D = mats[bones[i * 4 + slot]]
							m = Transform3D(Basis(m.basis.x + bm.basis.x * w, m.basis.y + bm.basis.y * w, m.basis.z + bm.basis.z * w), m.origin + bm.origin * w)
					if absf(m.basis.determinant()) > 1e-6:
						var inv := m.affine_inverse()
						p = inv * p
						if has_n:
							nrm = (m.basis.transposed() * nrm).normalized()
						if has_t:
							tan = (inv.basis * tan).normalized()
				nv[i] = p
				if has_n:
					ns[i] = nrm
				if has_t:
					ts[i * 4] = tan.x
					ts[i * 4 + 1] = tan.y
					ts[i * 4 + 2] = tan.z
			arr[Mesh.ARRAY_VERTEX] = nv
			if has_n:
				arr[Mesh.ARRAY_NORMAL] = ns
			if has_t:
				arr[Mesh.ARRAY_TANGENT] = ts
			arr[Mesh.ARRAY_BONES] = bones
			arr[Mesh.ARRAY_WEIGHTS] = weights
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, mi.mesh.surface_get_material(s))
		meshes.append(am)
	wrap.free()
	return meshes

## Miembros que se pueden posar: brazos ("Left"/"Right") y piernas ("LeftLeg"/"RightLeg").
const LIMBS := ["Left", "Right", "LeftLeg", "RightLeg"]

## Huesos de cada tramo de un miembro: [[articulación, extremo], …] (brazo→codo, antebrazo→mano; muslo→rodilla, pierna→pie).
static func limb_chain(limb: String) -> Array:
	if limb.ends_with("Leg"):
		var side := limb.trim_suffix("Leg")
		return [["mixamorig_%sUpLeg" % side, "mixamorig_%sLeg" % side],
				["mixamorig_%sLeg" % side, "mixamorig_%sFoot" % side]]
	return [["mixamorig_%sArm" % limb, "mixamorig_%sForeArm" % limb],
			["mixamorig_%sForeArm" % limb, "mixamorig_%sHand" % limb]]

## Pose de brazos y piernas guardada por el editor ({"Left"/"Right"/"LeftLeg"/"RightLeg": {"dirs": [brazo, antebrazo]}}), calculada sin tocar el
## esqueleto (igual que el editor: cada tramo se gira para apuntar a su dirección). Devuelve {"mats": por índice del Skin,
## hueso_en_pose * bind} o {} si no hay pose o esqueleto.
static func _arm_pose(body: MeshInstance3D, arms: Dictionary, force: bool = false) -> Dictionary:
	if (arms.is_empty() and not force) or body.skin == null:
		return {}
	var skel := body.get_node_or_null(body.skeleton) as Skeleton3D
	if skel == null:
		return {}
	var count := skel.get_bone_count()
	var locals: Array[Transform3D] = []
	for b in count:
		locals.append(skel.get_bone_rest(b))
	var posed := false
	for side in LIMBS:
		var a: Variant = arms.get(side, {})
		var dirs: Array = (a as Dictionary).get("dirs", []) if a is Dictionary else []
		if dirs.size() < 2:
			continue
		var chain := limb_chain(side)
		for k in chain.size():
			var b := skel.find_bone(chain[k][0])
			var c := skel.find_bone(chain[k][1])
			if b < 0 or c < 0:
				continue
			var g := _globals(skel, locals)
			var d := (g[c].origin - g[b].origin).normalized()
			var tgt := vec(dirs[k], d).normalized()
			if d == Vector3.ZERO or tgt == Vector3.ZERO:
				continue
			var p := skel.get_bone_parent(b)
			var parent_g := g[p].basis.orthonormalized() if p >= 0 else Basis.IDENTITY
			var rest := skel.get_bone_rest(b)
			var q := (parent_g.inverse() * Basis(Quaternion(d, tgt)) * parent_g * rest.basis.orthonormalized()).get_rotation_quaternion()
			locals[b] = Transform3D(Basis(q) * Basis.from_scale(rest.basis.get_scale()), rest.origin)
			posed = true
	if not posed and not force:
		return {}
	var g := _globals(skel, locals)
	var mats: Array = []
	for i in body.skin.get_bind_count():
		var bi := body.skin.get_bind_bone(i)
		if bi < 0:
			bi = skel.find_bone(body.skin.get_bind_name(i))
		mats.append(g[bi] * body.skin.get_bind_pose(i) if bi >= 0 else Transform3D.IDENTITY)
	return {"mats": mats, "key": JSON.stringify(arms, "", true)}

## Transformaciones globales (espacio del esqueleto) a partir de las locales.
static func _globals(skel: Skeleton3D, locals: Array[Transform3D]) -> Array[Transform3D]:
	var count := locals.size()
	var g: Array[Transform3D] = []
	g.resize(count)
	var done := PackedByteArray()
	done.resize(count)
	for b in count:
		var stack: Array[int] = []
		var x := b
		while x >= 0 and done[x] == 0:
			stack.push_back(x)
			x = skel.get_bone_parent(x)
		while not stack.is_empty():
			var y: int = stack.pop_back()
			var p := skel.get_bone_parent(y)
			g[y] = g[p] * locals[y] if p >= 0 else locals[y]
			done[y] = 1
	return g

static func _path_xf(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

static func _cell(p: Vector3, origin: Vector3, size: float) -> Vector3i:
	return Vector3i(floori((p.x - origin.x) / size), floori((p.y - origin.y) / size), floori((p.z - origin.z) / size))

## Vértices del cuerpo (sin ojos) con sus 4 mayores pesos y el campo 3D: cada celda guarda el índice del vértice del
## cuerpo más cercano (relleno por oleadas desde las celdas que contienen vértices).
static func _body_data(body: MeshInstance3D, pose: Dictionary = {}) -> Dictionary:
	var mesh := body.mesh
	var ckey := "%d|%s" % [mesh.get_instance_id(), String(pose.get("key", ""))]
	if _body_cache.has(ckey):
		return _body_cache[ckey]
	var mats: Array = pose.get("mats", [])
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat != null and mat.resource_name == SKIN_EYES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if v.is_empty() or b.is_empty():
			continue
		var per := b.size() / v.size()
		for i in v.size():
			var best_b: Array = [0, 0, 0, 0]
			var best_w: Array = [0.0, 0.0, 0.0, 0.0]
			for k in per:
				var wk := w[i * per + k]
				for slot in 4:
					if wk > float(best_w[slot]):
						best_w.insert(slot, wk)
						best_b.insert(slot, b[i * per + k])
						best_w.resize(4)
						best_b.resize(4)
						break
			var total := 0.0
			for slot in 4:
				total += float(best_w[slot])
			var pv := v[i]
			if not mats.is_empty():   # el cuerpo en la pose del ajuste
				var acc := Vector3.ZERO
				for slot in 4:
					var bw := float(best_w[slot]) / maxf(total, 0.0001)
					if bw > 0.0:
						acc += ((mats[int(best_b[slot])] as Transform3D) * v[i]) * bw
				pv = acc
			verts.append(pv)
			for slot in 4:
				bones.append(int(best_b[slot]))
				wts.append(float(best_w[slot]) / maxf(total, 0.0001))
	var box := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(p)
	var cell := maxf(box.size.y / float(FIELD_CELLS), 0.000001)
	var origin := box.position - Vector3.ONE * cell * float(FIELD_PAD)
	var dims := Vector3i(ceili(box.size.x / cell), ceili(box.size.y / cell), ceili(box.size.z / cell)) + Vector3i.ONE * (FIELD_PAD * 2 + 1)
	var sx := dims.y * dims.z
	var src := PackedInt32Array()
	src.resize(dims.x * sx)
	src.fill(-1)
	var queue := PackedInt32Array()
	for i in verts.size():
		var c := _cell(verts[i], origin, cell)
		var idx := c.x * sx + c.y * dims.z + c.z
		if src[idx] < 0:
			src[idx] = i
			queue.append(idx)
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var sv := src[idx]
		var cx := idx / sx
		var rem := idx % sx
		var cy := rem / dims.z
		var cz := rem % dims.z
		if cx > 0 and src[idx - sx] < 0:
			src[idx - sx] = sv
			queue.append(idx - sx)
		if cx < dims.x - 1 and src[idx + sx] < 0:
			src[idx + sx] = sv
			queue.append(idx + sx)
		if cy > 0 and src[idx - dims.z] < 0:
			src[idx - dims.z] = sv
			queue.append(idx - dims.z)
		if cy < dims.y - 1 and src[idx + dims.z] < 0:
			src[idx + dims.z] = sv
			queue.append(idx + dims.z)
		if cz > 0 and src[idx - 1] < 0:
			src[idx - 1] = sv
			queue.append(idx - 1)
		if cz < dims.z - 1 and src[idx + 1] < 0:
			src[idx + 1] = sv
			queue.append(idx + 1)
	var data := {"bones": bones, "weights": wts, "src": src, "dims": dims, "origin": origin, "cell": cell}
	_body_cache[ckey] = data
	return data

## Pesos del vértice `i` de la prenda en `p`: interpolación trilineal de las 8 celdas del campo que lo rodean.
static func _weights_for(p: Vector3, data: Dictionary, out_b: PackedInt32Array, out_w: PackedFloat32Array, i: int) -> void:
	var bones: PackedInt32Array = data["bones"]
	var wts: PackedFloat32Array = data["weights"]
	var src: PackedInt32Array = data["src"]
	var dims: Vector3i = data["dims"]
	var f: Vector3 = (p - (data["origin"] as Vector3)) / float(data["cell"]) - Vector3(0.5, 0.5, 0.5)
	var x0 := floori(f.x)
	var y0 := floori(f.y)
	var z0 := floori(f.z)
	var fx := f.x - x0
	var fy := f.y - y0
	var fz := f.z - z0
	var ab := PackedInt32Array()
	var aw := PackedFloat32Array()
	for corner in 8:
		var dx := corner & 1
		var dy := (corner >> 1) & 1
		var dz := (corner >> 2) & 1
		var k := (fx if dx == 1 else 1.0 - fx) * (fy if dy == 1 else 1.0 - fy) * (fz if dz == 1 else 1.0 - fz)
		if k <= 0.0001:
			continue
		var j := src[(clampi(x0 + dx, 0, dims.x - 1) * dims.y + clampi(y0 + dy, 0, dims.y - 1)) * dims.z + clampi(z0 + dz, 0, dims.z - 1)]
		if j < 0:
			continue
		for slot in 4:
			var bw := wts[j * 4 + slot]
			if bw <= 0.0:
				continue
			var bi := bones[j * 4 + slot]
			var at := ab.find(bi)
			if at < 0:
				ab.append(bi)
				aw.append(bw * k)
			else:
				aw[at] += bw * k
	# Los 4 mayores, normalizados
	var total := 0.0
	for slot in 4:
		var best := -1
		var bv := 0.0
		for a in aw.size():
			if aw[a] > bv:
				bv = aw[a]
				best = a
		if best < 0:
			out_b[i * 4 + slot] = 0
			out_w[i * 4 + slot] = 0.0
		else:
			out_b[i * 4 + slot] = ab[best]
			out_w[i * 4 + slot] = bv
			total += bv
			aw[best] = 0.0
	if total <= 0.0:
		out_w[i * 4] = 1.0
		return
	for slot in 4:
		out_w[i * 4 + slot] /= total

## Caja de todas las mallas bajo `root` en el espacio de `root` (con las transformaciones de sus nodos).
static func _tree_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != root and p is Node3D:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var b := t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
