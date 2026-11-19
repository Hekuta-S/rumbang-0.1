extends Node

## La malla del terreno en C++ (TerrainNative) es la misma que la de GDScript (ProceduralMap._build_terrain):
## alturas, colores, UV y normales en varias semillas, en PC y con los ajustes de móvil. Mide los dos.
## Sin la extensión compilada la prueba se salta (no falla).
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	if not ClassDB.class_exists(&"TerrainNative"):
		print("SKIPPED: extensión nativa no cargada")
		get_tree().quit(0)
		return
	var t_gd := 0
	var t_cpp := 0
	for map_seed in [3, 27, 144, 512, 1337]:
		for cell in [1.5, 2.5]:
			var m := ProceduralMap.new()
			m.map_seed = map_seed
			add_child(m)
			m.cell_size = cell
			m._rng.seed = map_seed
			m.used_seed = map_seed
			# Mismo estado que generate() justo antes de _build_terrain
			m._clear()
			m._rng.seed = map_seed
			m._setup_noise()
			m._pick_layout()
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			var t0 := Time.get_ticks_usec()
			m._build_terrain_arrays(a)
			t_gd += Time.get_ticks_usec() - t0
			var h_gd: PackedFloat32Array = m._heights.duplicate()
			t0 = Time.get_ticks_usec()
			var r: Array = ClassDB.instantiate(&"TerrainNative").build({"half_size": m.half_size, "cell_size": m.cell_size,
				"hill_amplitude": m.hill_amplitude, "basin_depth": m.basin_depth, "basin_floor_radius": m.basin_floor_radius,
				"basin_rim_radius": m.basin_rim_radius, "play_half": m.play_half, "cliff_height": m.cliff_height,
				"basin_center": m._basin_center, "ramp_end": m._ramp_end, "ramp_surface_y": m._ramp_surface_y},
				m._noise_hills, m._noise_detail, m._mesas, m._bridges)
			t_cpp += Time.get_ticks_usec() - t0
			var ok_size: bool = int(r[0]) == m._side and (r[1] as PackedFloat32Array).size() == h_gd.size()
			var worst_h := 0.0
			var worst_c := 0.0
			var worst_n := 0.0
			var worst_uv := 0.0
			if ok_size:
				var hc: PackedFloat32Array = r[1]
				var cc: PackedColorArray = r[3]
				var uc: PackedVector2Array = r[4]
				var nc: PackedVector3Array = r[5]
				var cg: PackedColorArray = a[Mesh.ARRAY_COLOR]
				var ug: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				var ng: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				for i in h_gd.size():
					worst_h = maxf(worst_h, absf(hc[i] - h_gd[i]))
					var dc: Color = cc[i] - cg[i]
					worst_c = maxf(worst_c, maxf(maxf(absf(dc.r), absf(dc.g)), maxf(absf(dc.b), absf(dc.a))))
					worst_uv = maxf(worst_uv, absf(uc[i].x - ug[i].x))
					worst_n = maxf(worst_n, nc[i].distance_to(ng[i]))
				var ok_idx: bool = (r[6] as PackedInt32Array) == (a[Mesh.ARRAY_INDEX] as PackedInt32Array)
				_check(worst_h < 0.01 and worst_c < 0.01 and worst_uv < 0.001 and worst_n < 0.01 and ok_idx,
					"semilla %d celda %.1f: alturas %.5f, colores %.5f, uv %.5f, normales %.5f, índices %s" % [map_seed, cell, worst_h, worst_c, worst_uv, worst_n, ok_idx])
			else:
				_check(false, "semilla %d: tamaño distinto" % map_seed)
			m.free()
			await get_tree().process_frame
	print("TIEMPO: GDScript %.1f ms, C++ %.1f ms por malla (%.0fx)" % [t_gd / 10000.0, t_cpp / 10000.0, float(t_gd) / maxf(float(t_cpp), 1.0)])
	print("ALL NATIVE TERRAIN CHECKS PASSED" if not _fail else "NATIVE TERRAIN CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
