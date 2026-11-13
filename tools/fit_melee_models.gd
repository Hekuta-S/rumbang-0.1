extends SceneTree
## Mide los modelos nuevos de dagas y mazas: eje pomo->punta/cabeza, ancho y perfil de grosor.
## Uso (headless): godot --headless --path . -s tools/fit_melee_models.gd <carpeta> <archivo> [<archivo> ...]
##
## El eje largo se saca con PCA (varianza principal) y no con el par de vértices más lejano: en
## modelos con guarda, pomo con anilla o cabezas grandes ese par cae en diagonal y dejaba el arma
## torcida. El extremo "de trabajo" se decide por categoría: en las dagas es la punta (banda fina),
## en las mazas la cabeza (banda gruesa).

const FOLDERS := {
	"dagas": "res://assets/models/weapons/dagas",
	"mazas": "res://assets/models/weapons/mazas",
}

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := "dagas"
	var files: Array[String] = []
	if args.size() >= 2:
		folder = args[0]
		for i in range(1, args.size()):
			files.append(args[i])
	else:
		await _measure_all("dagas", ["chinese_style_dagger", "cloaking_dagger", "dague", "dague_runes"])
		await _measure_all("mazas", ["bone_mace", "mekka_mace", "mace_model_textured", "skull_mace", "spiked_black_iron_mace"])
		quit()
		return
	for f in files:
		var dir: String = FOLDERS.get(folder, FOLDERS["dagas"])
		if not FileAccess.file_exists("%s/%s.glb" % [dir, f]):
			dir = "res://assets/models/weapons/%s" % folder
		await _measure(dir, f)
	quit()

func _measure_all(folder: String, files: Array) -> void:
	for f in files:
		await _measure(String(FOLDERS[folder]), String(f))

func _cov_mul(v: Vector3, m: Array) -> Vector3:
	# m = [xx, yy, zz, xy, xz, yz]
	return Vector3(
		m[0] * v.x + m[3] * v.y + m[4] * v.z,
		m[3] * v.x + m[1] * v.y + m[5] * v.z,
		m[4] * v.x + m[5] * v.y + m[2] * v.z)

func _principal_axis(pts: Array[Vector3], c: Vector3, seed: Vector3) -> Vector3:
	var m := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for p in pts:
		var d := p - c
		m[0] += d.x * d.x
		m[1] += d.y * d.y
		m[2] += d.z * d.z
		m[3] += d.x * d.y
		m[4] += d.x * d.z
		m[5] += d.y * d.z
	var v := seed if seed.length_squared() > 0.000001 else Vector3.UP
	v = v.normalized()
	for _i in 64:
		var nv := _cov_mul(v, m)
		if nv.length_squared() < 0.0000000001:
			break
		v = nv.normalized()
	return v

func _band_radius(pts: Array[Vector3], axis: Vector3, c: Vector3, t_min: float, t_max: float, lo: bool) -> Array:
	var span := t_max - t_min
	var band := span * 0.12
	var rs := 0.0
	var ns := 0
	for p in pts:
		var t := (p - c).dot(axis)
		if (lo and t <= t_min + band) or (not lo and t >= t_max - band):
			rs += ((p - c) - axis * t).length()
			ns += 1
	return [rs / maxi(ns, 1), ns]

func _measure(dir: String, f: String) -> void:
	var path := "%s/%s.glb" % [dir, f]
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	await process_frame
	var pts: Array[Vector3] = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := inst.global_transform.affine_inverse() * m.global_transform
		for s in m.mesh.get_surface_count():
			var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var step := maxi(vs.size() / 4000, 1)
			for i in range(0, vs.size(), step):
				pts.append(xf * vs[i])
	if pts.is_empty():
		print("FIT ", f, " EMPTY")
		inst.queue_free()
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()

	# Semilla: par de vértices más lejano (buena aproximación para arrancar la potencia).
	var a := pts[0]
	for p in pts:
		if p.distance_to(c) > a.distance_to(c):
			a = p
	var b := a
	for p in pts:
		if p.distance_to(a) > b.distance_to(a):
			b = p
	var axis := _principal_axis(pts, c, (b - a).normalized())

	var t_min := INF
	var t_max := -INF
	for p in pts:
		var t := (p - c).dot(axis)
		t_min = minf(t_min, t)
		t_max = maxf(t_max, t)
	var len := t_max - t_min
	var lo := _band_radius(pts, axis, c, t_min, t_max, true)
	var hi := _band_radius(pts, axis, c, t_min, t_max, false)
	var r_lo := float(lo[0])
	var r_hi := float(hi[0])
	# Punta/cabeza del lado "hi" si conviene; en dagas manda el extremo fino, en mazas el grueso.
	var want_hi_dagger := r_hi < r_lo
	var want_hi_mace := r_hi > r_lo
	var dagger := dir.ends_with("dagas")
	if (dagger and not want_hi_dagger) or (not dagger and not want_hi_mace):
		axis = -axis
		var tmp := t_min
		t_min = -t_max
		t_max = -tmp
	var pommel := c + axis * t_min
	var tip := c + axis * t_max

	var u := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var best_ang := 0.0
	var best_ext := 0.0
	for k in 36:
		var ang := PI * k / 36.0
		var d := u * cos(ang) + v * sin(ang)
		var mn := INF
		var mx := -INF
		for p in pts:
			var e := (p - c).dot(d)
			mn = minf(mn, e)
			mx = maxf(mx, e)
		if mx - mn > best_ext:
			best_ext = mx - mn
			best_ang = ang
	var wide := (u * cos(best_ang) + v * sin(best_ang)).normalized()
	var rprof := []
	for k in 12:
		var rs := 0.0
		var ns := 0
		for p in pts:
			var t := (p - pommel).dot(axis) / len
			if int(clampf(t, 0.0, 0.9999) * 12.0) == k:
				rs += ((p - pommel) - axis * (p - pommel).dot(axis)).length()
				ns += 1
		rprof.append(snappedf(rs / maxi(ns, 1) / len, 0.001))
	var prof := []
	for k in 12:
		var w := 0.0
		for p in pts:
			var t := (p - pommel).dot(axis) / len
			if int(clampf(t, 0.0, 0.9999) * 12.0) == k:
				w = maxf(w, absf((p - c).dot(wide)))
		prof.append(snappedf(w * 2.0 / len, 0.001))
	print("FIT ", f, " len=", snappedf(len, 0.0001), " pommel=", pommel, " tip=", tip,
		" up=", axis, " wide=", wide, " rlo=", snappedf(r_lo / len, 0.001), " rhi=", snappedf(r_hi / len, 0.001),
		" rprof=", rprof, " prof=", prof)
	inst.queue_free()
