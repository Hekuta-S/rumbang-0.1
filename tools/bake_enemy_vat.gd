extends SceneTree

## Hornea las animaciones de los enemigos en texturas (VAT = Vertex Animation Texture) para dibujarlos
## con MultiMesh. Para cada modelo genera en res://assets/vat/:
##   <clave>_mesh.res   malla estática (sin huesos) con el orden de vértices del horneado
##   <clave>_idle.res   textura RGBAH: posición de cada vértice en cada fotograma de "idle"
##   <clave>_walk.res   ídem para "caminar"
##   <clave>_meta.json  fotogramas, nº de vértices, ancho de textura y filas por fotograma
## Las posiciones salen ya en el espacio del enemigo (con el mismo ajuste de tamaño que Enemy._fit_model).
##
## Uso (desde la carpeta del proyecto):
##   godot --headless --path . -s tools/bake_enemy_vat.gd

const OUT := "res://assets/vat/"
## Fotogramas por segundo horneados (la interpolación del shader suaviza entre ellos). Menos = textura más ligera.
const ANIM_FPS := {"idle": 8.0, "walk": 15.0}
const TEX_W := 2048
const TARGET_HEIGHT := 1.45   # igual que Enemy._fit_model()
const DIR := "res://assets/models/entities/enemigos/goblins/"

const MODELS := {
	"magoblin": {"idle": "idle_magoblin.fbx", "walk": "caminar_magoblin.fbx"},
	"normal": {"idle": "idle_normal_goblin.fbx", "walk": "caminar_normal_goblin.fbx"},
	"bruto": {"idle": "idle_goblin_bruto.fbx", "walk": "caminar_goblin_bruto.fbx"},
	"zombie": {"idle": "goblin_idle_zombie.fbx", "walk": "goblin_caminar_zombie.fbx"},
}

var _keys: Array = []
var _i := 0
var _stage := 0
var _holder: Node3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_keys = MODELS.keys()

func _process(_delta: float) -> bool:
	# Un modelo por frame para dejar que el árbol procese entre horneados
	if _i >= _keys.size():
		print("BAKE_DONE")
		quit()
		return true
	_bake(_keys[_i])
	_i += 1
	return false

func _first_of(n: Node, type_name: String) -> Node:
	if n.is_class(type_name):
		return n
	for c in n.get_children():
		var r := _first_of(c, type_name)
		if r:
			return r
	return null

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

## Skinning por CPU de una superficie con la pose actual del esqueleto (posiciones en el espacio del esqueleto).
func _skin_surface(mi: MeshInstance3D, skel: Skeleton3D, si: int) -> PackedVector3Array:
	var arr := mi.mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	out.resize(verts.size())
	if bones.is_empty() or mi.skin == null:
		return verts
	var stride := bones.size() / verts.size()
	var skin := mi.skin
	var mats: Array[Transform3D] = []
	for b in range(skin.get_bind_count()):
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		mats.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	for i in range(verts.size()):
		var acc := Vector3.ZERO
		for k in range(stride):
			var w := weights[i * stride + k]
			if w > 0.0:
				acc += w * (mats[bones[i * stride + k]] * verts[i])
		out[i] = acc
	return out


## lod0 es la malla "base" (sin sufijo en los archivos); lod1 y lod2 son los niveles lejanos.
const LOD_NAMES := ["lod0", "lod1", "lod2"]
const WORK := "res://assets/vat/_work/"

## Lee un OBJ (v/vt/vn y caras triangulares con índices v/vt/vn) y devuelve sus esquinas únicas como arrays.
func _read_obj(path: String) -> Dictionary:
	var v := PackedVector3Array()
	var vt := PackedVector2Array()
	var vn := PackedVector3Array()
	var corner_key := {}
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("v "):
			var p := line.substr(2).split_floats(" ", false)
			v.append(Vector3(p[0], p[1], p[2]))
		elif line.begins_with("vt "):
			var p := line.substr(3).split_floats(" ", false)
			vt.append(Vector2(p[0], p[1]))
		elif line.begins_with("vn "):
			var p := line.substr(3).split_floats(" ", false)
			vn.append(Vector3(p[0], p[1], p[2]))
		elif line.begins_with("f "):
			var corners := line.substr(2).strip_edges().split(" ", false)
			var ids: Array[int] = []
			for c in corners:
				var parts := c.split("/")
				var vi := int(parts[0]) - 1
				var ti := int(parts[1]) - 1 if parts.size() > 1 and parts[1] != "" else -1
				var ni := int(parts[2]) - 1 if parts.size() > 2 and parts[2] != "" else -1
				var key := "%d/%d/%d" % [vi, ti, ni]
				if not corner_key.has(key):
					corner_key[key] = pos.size()
					pos.append(v[vi])
					uv.append(vt[ti] if ti >= 0 else Vector2.ZERO)
					nor.append(vn[ni] if ni >= 0 else Vector3.UP)
				ids.append(corner_key[key])
			for k in range(1, ids.size() - 1):
				idx.append(ids[0]); idx.append(ids[k]); idx.append(ids[k + 1])
	return {"pos": pos, "nor": nor, "uv": uv, "idx": idx}

## Vuelca la malla de reposo ORIGINAL a OBJ (para simplificarla en Blender, ver tools/blender_decimate_lods.py).
func _write_obj(path: String, v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, ix: PackedInt32Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	var f := FileAccess.open(path, FileAccess.WRITE)
	for i in range(v.size()):
		f.store_line("v %.6f %.6f %.6f" % [v[i].x, v[i].y, v[i].z])
	for i in range(v.size()):
		f.store_line("vt %.6f %.6f" % [uv[i].x, uv[i].y])
	for i in range(v.size()):
		f.store_line("vn %.5f %.5f %.5f" % [n[i].x, n[i].y, n[i].z])
	for t in range(0, ix.size(), 3):
		var a := ix[t] + 1
		var b := ix[t + 1] + 1
		var c := ix[t + 2] + 1
		f.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [a, a, a, b, b, b, c, c, c])
	f.close()

func _bake_lods(key: String, model: Node3D, ap: AnimationPlayer, lib: AnimationLibrary, meshes: Array,
		orig_pos: PackedVector3Array, _orig_nor: PackedVector3Array, _orig_uv: PackedVector2Array) -> Array:
	var out: Array = []
	var mi := meshes[0] as MeshInstance3D
	var skel := _first_of(model, "Skeleton3D") as Skeleton3D
	var arr := mi.mesh.surface_get_arrays(0)
	var o_bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var o_weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride := o_bones.size() / orig_pos.size()

	# Rejilla espacial de los vértices originales (celdas de 4 cm) para heredar la skin del más cercano
	const CELL := 0.04
	var grid := {}
	for i in range(orig_pos.size()):
		var c := Vector3i(int(floor(orig_pos[i].x / CELL)), int(floor(orig_pos[i].y / CELL)), int(floor(orig_pos[i].z / CELL)))
		if grid.has(c):
			(grid[c] as Array).append(i)
		else:
			grid[c] = [i]

	for lod in LOD_NAMES:
		var obj := _read_obj(WORK + "%s_%s.obj" % [key, lod])
		if obj.is_empty():
			continue
		var pos: PackedVector3Array = obj["pos"]
		var nearest := PackedInt32Array()
		nearest.resize(pos.size())
		for i in range(pos.size()):
			var c := Vector3i(int(floor(pos[i].x / CELL)), int(floor(pos[i].y / CELL)), int(floor(pos[i].z / CELL)))
			var best := -1
			var best_d := INF
			var ring := 1
			while best < 0 and ring < 8:
				for dx in range(-ring, ring + 1):
					for dy in range(-ring, ring + 1):
						for dz in range(-ring, ring + 1):
							var cell: Array = grid.get(Vector3i(c.x + dx, c.y + dy, c.z + dz), [])
							for oi in cell:
								var d := pos[i].distance_squared_to(orig_pos[oi])
								if d < best_d:
									best_d = d
									best = oi
				ring += 1
			nearest[i] = best

		var rows := int(ceil(float(pos.size()) / float(TEX_W)))
		var info := {"name": lod, "verts": pos.size(), "rows": rows, "tris": (obj["idx"] as PackedInt32Array).size() / 3}
		# 1) Posiciones de todos los fotogramas (idle y walk) para conocer los límites del modelo
		var anim_pos := {}
		var bmin := Vector3(1e9, 1e9, 1e9)
		var bmax := Vector3(-1e9, -1e9, -1e9)
		for anim_name in ["idle", "walk"]:
			var anim := lib.get_animation(anim_name)
			var fps: float = ANIM_FPS[anim_name]
			var frames := maxi(2, int(round(anim.length * fps)))
			var per_frame: Array = []
			for f in range(frames):
				ap.play(anim_name)
				ap.seek(float(f) / fps, true)
				ap.pause()
				var mats: Array[Transform3D] = []
				for b in range(mi.skin.get_bind_count()):
					var bone := mi.skin.get_bind_bone(b)
					if bone < 0:
						bone = skel.find_bone(mi.skin.get_bind_name(b))
					mats.append(skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(b))
				var xf := skel.global_transform
				var fp := PackedVector3Array()
				fp.resize(pos.size())
				for i in range(pos.size()):
					var o := nearest[i]
					var acc := Vector3.ZERO
					for k in range(stride):
						var w := o_weights[o * stride + k]
						if w > 0.0:
							acc += w * (mats[o_bones[o * stride + k]] * pos[i])
					var wp := xf * acc
					fp[i] = wp
					bmin = Vector3(minf(bmin.x, wp.x), minf(bmin.y, wp.y), minf(bmin.z, wp.z))
					bmax = Vector3(maxf(bmax.x, wp.x), maxf(bmax.y, wp.y), maxf(bmax.z, wp.z))
				per_frame.append(fp)
			anim_pos[anim_name] = per_frame
		# 2) Cuantización a 8 bits por canal (RGBA8: 4 bytes por vértice y fotograma en vez de 8 con half-float).
		#    El shader recupera la posición como pos_min + color * pos_size. Margen del 1 % en los límites.
		var pad := (bmax - bmin) * 0.01 + Vector3(0.001, 0.001, 0.001)
		bmin -= pad
		bmax += pad
		var bsize := bmax - bmin
		info["vmin"] = [bmin.x, bmin.y, bmin.z]
		info["vsize"] = [bsize.x, bsize.y, bsize.z]
		for anim_name in ["idle", "walk"]:
			var per_frame: Array = anim_pos[anim_name]
			var img := Image.create(TEX_W, rows * per_frame.size(), false, Image.FORMAT_RGBA8)
			for f in range(per_frame.size()):
				var fp: PackedVector3Array = per_frame[f]
				for i in range(fp.size()):
					var q := (fp[i] - bmin) / bsize
					img.set_pixel(i % TEX_W, f * rows + i / TEX_W, Color(q.x, q.y, q.z, 1.0))
			var file_suffix: String = "" if lod == "lod0" else "_" + lod
			ResourceSaver.save(ImageTexture.create_from_image(img), OUT + "%s%s_%s.res" % [key, file_suffix, anim_name])

		# Malla del LOD (esquinas únicas; mismas normales/UV que exportó Blender)
		var a2 := []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = pos
		a2[Mesh.ARRAY_NORMAL] = obj["nor"]
		a2[Mesh.ARRAY_TEX_UV] = obj["uv"]
		a2[Mesh.ARRAY_INDEX] = obj["idx"]
		var m2 := ArrayMesh.new()
		m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		m2.custom_aabb = AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5.0, 4.0, 5.0))
		ResourceSaver.save(m2, OUT + "%s%s_mesh.res" % [key, "" if lod == "lod0" else "_" + lod])
		out.append(info)
	return out

func _bake(key: String) -> void:
	var cfg: Dictionary = MODELS[key]
	var holder := Node3D.new()
	root.add_child(holder)

	var idle_scene := load(DIR + cfg["idle"]) as PackedScene
	var walk_scene := load(DIR + cfg["walk"]) as PackedScene
	var model := idle_scene.instantiate() as Node3D
	holder.add_child(model)

	# Mismo ajuste de tamaño y orientación que el juego
	var first_mi := _first_of(model, "MeshInstance3D") as MeshInstance3D
	var aabb: AABB = first_mi.mesh.get_aabb()
	var s := TARGET_HEIGHT / maxf(aabb.size.y, 0.001)
	model.scale = Vector3(s, s, s)
	model.rotation.y = PI
	model.position.y = -aabb.position.y * s

	var ap := _first_of(model, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		push_error("[%s] sin AnimationPlayer" % key)
		return
	# Igual que Enemy._setup_animations: primera animación = idle; la de caminar viene del otro FBX
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	var lib := ap.get_animation_library("")
	var names := lib.get_animation_list()
	var first_name := String(names[0])
	if first_name != "idle":
		var a := lib.get_animation(first_name)
		lib.remove_animation(first_name)
		lib.add_animation("idle", a)
	var walk_inst := walk_scene.instantiate()
	var walk_ap := _first_of(walk_inst, "AnimationPlayer") as AnimationPlayer
	lib.add_animation("walk", walk_ap.get_animation(walk_ap.get_animation_list()[0]).duplicate(true))
	walk_inst.free()

	var meshes: Array = []
	_collect_meshes(model, meshes)
	var total_verts := 0
	for mi in meshes:
		for si in range((mi as MeshInstance3D).mesh.get_surface_count()):
			total_verts += (mi as MeshInstance3D).mesh.surface_get_array_len(si)
	var rows_per_frame := int(ceil(float(total_verts) / float(TEX_W)))

	# Comprobación: en pose de reposo el skinning por CPU debe reproducir los vértices originales
	var skel0 := _first_of(model, "Skeleton3D") as Skeleton3D
	var max_err := 0.0
	for mi_n in meshes:
		var mi0 := mi_n as MeshInstance3D
		for si in range(mi0.mesh.get_surface_count()):
			var orig: PackedVector3Array = mi0.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var skinned := _skin_surface(mi0, skel0, si)
			for vi in range(0, orig.size(), 17):
				max_err = maxf(max_err, orig[vi].distance_to(skinned[vi]))
	print("CHECK ", key, " err_reposo=", snappedf(max_err, 0.0001), " mi==skel_transform=", (meshes[0] as MeshInstance3D).global_transform.is_equal_approx(skel0.global_transform))

	var meta := {"verts": total_verts, "tex_w": TEX_W, "rows": rows_per_frame}
	for anim_name in ["idle", "walk"]:
		var anim := lib.get_animation(anim_name)
		var fps: float = ANIM_FPS[anim_name]
		var frames := maxi(2, int(round(anim.length * fps)))
		var img := Image.create(TEX_W, rows_per_frame * frames, false, Image.FORMAT_RGBAH)
		var miny := 1e9
		var maxy := -1e9
		for f in range(frames):
			ap.play(anim_name)
			ap.seek(float(f) / fps, true)
			ap.pause()
			var vid := 0
			for mi_n in meshes:
				var mi := mi_n as MeshInstance3D
				var skel := _first_of(model, "Skeleton3D") as Skeleton3D
				for si in range(mi.mesh.get_surface_count()):
					var verts := _skin_surface(mi, skel, si)
					var xf := skel.global_transform
					for v in verts:
						var p := xf * v
						img.set_pixel(vid % TEX_W, f * rows_per_frame + vid / TEX_W, Color(p.x, p.y, p.z, 1.0))
						vid += 1
						if f == 0:
							miny = minf(miny, p.y)
							maxy = maxf(maxy, p.y)
		meta[anim_name + "_fps"] = fps
		meta[anim_name + "_frames"] = frames
		meta[anim_name + "_length"] = anim.length
		if anim_name == "idle":
			meta["frame0_height"] = maxy - miny
		ResourceSaver.save(ImageTexture.create_from_image(img), OUT + "%s_%s.res" % [key, anim_name])

	# Malla estática: todas las superficies fusionadas en una, mismo orden que el horneado
	var verts_all := PackedVector3Array()
	var norms_all := PackedVector3Array()
	var uvs_all := PackedVector2Array()
	var idx_all := PackedInt32Array()
	for mi_n in meshes:
		var mi := mi_n as MeshInstance3D
		for si in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(si)
			var base := verts_all.size()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			verts_all.append_array(vs)
			var ns = arr[Mesh.ARRAY_NORMAL]
			if ns == null:
				ns = PackedVector3Array()
				ns.resize(vs.size())
			norms_all.append_array(ns)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			if uv == null:
				uv = PackedVector2Array()
				uv.resize(vs.size())
			uvs_all.append_array(uv)
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix == null:
				for k in range(vs.size()):
					idx_all.append(base + k)
			else:
				for k in ix:
					idx_all.append(base + int(k))
	var out_arr := []
	out_arr.resize(Mesh.ARRAY_MAX)
	out_arr[Mesh.ARRAY_VERTEX] = verts_all
	out_arr[Mesh.ARRAY_NORMAL] = norms_all
	out_arr[Mesh.ARRAY_TEX_UV] = uvs_all
	out_arr[Mesh.ARRAY_INDEX] = idx_all
	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arr)
	out_mesh.custom_aabb = AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5.0, 4.0, 5.0))
	ResourceSaver.save(out_mesh, OUT + "%s_mesh.res" % key)

	# Niveles de detalle simplificados con Blender (ver tools/export_enemy_rest_obj.gd): cada LOD tiene su
	# propia malla y sus propias texturas VAT (la skin se hereda del vértice original más cercano).
	_write_obj(WORK + "%s.obj" % key, verts_all, norms_all, uvs_all, idx_all)
	var lod_infos := _bake_lods(key, model, ap, lib, meshes, verts_all, norms_all, uvs_all)
	var far_infos: Array = []
	for info in lod_infos:
		if info["name"] == "lod0":
			# la malla base ahora es la simplificada: sus filas/vértices sustituyen a los del original
			meta["rows"] = info["rows"]
			meta["verts"] = info["verts"]
			meta["tris"] = info["tris"]
			meta["vmin"] = info["vmin"]
			meta["vsize"] = info["vsize"]
		else:
			far_infos.append(info)
	meta["lods"] = far_infos

	var f := FileAccess.open(OUT + "%s_meta.json" % key, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	print("BAKED ", key, " ", meta)
	holder.queue_free()
