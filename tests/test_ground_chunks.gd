extends Node

## El suelo de supervivencia se dibuja por trozos (ProceduralMap._finish_terrain): juntos deben dar
## exactamente la malla entera. Comprueba que cubren todas las celdas (mismos triángulos), que los vértices
## de borde coinciden con la rejilla (sin costuras) y que cada trozo es pequeño (la cámara puede descartarlo).
var _fail := false
var _n := 0
const NORMAL_TOL := 0.01       ## error de la compresión de normales de Godot
## El suelo real sale de TerrainNative (C++) y la referencia de aquí del GDScript: difieren en ~1e-5 m en algún punto
const POS_TOL := 0.001

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	# Arrange: mapa generado con una semilla fija
	var m := ProceduralMap.new()
	m.map_seed = 27
	add_child(m)
	m._rng.seed = 27
	m.used_seed = 27
	m._clear()
	m._rng.seed = 27
	m._setup_noise()
	m._pick_layout()
	var full := []
	full.resize(Mesh.ARRAY_MAX)
	m._build_terrain_arrays(full)
	if m.district:
		m.district.carve(full)             # como _build_terrain: el Barrio del Desagüe se talla sobre la malla
	var side: int = m._side
	var verts: PackedVector3Array = full[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = full[Mesh.ARRAY_NORMAL]

	# Act
	m._finish_terrain(full)
	var ground := m.get_node("Ground")
	var chunks := ground.get_children()

	# Assert
	var cells := side - 1
	var per_side := ceili(float(cells) / ProceduralMap.GROUND_CHUNK_CELLS)
	_check(chunks.size() == per_side * per_side, "%d trozos (esperado %d)" % [chunks.size(), per_side * per_side])
	var tris := 0
	var max_extent := 0.0
	var seam_ok := true
	var grid_ok := true
	var shared := 0
	var verts_set := {}
	for c in chunks:
		var mi := c as MeshInstance3D
		var a: Array = mi.mesh.surface_get_arrays(0)
		var cv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var aabb := mi.mesh.get_aabb()
		max_extent = maxf(max_extent, maxf(aabb.size.x, aabb.size.z))
		for k in cv.size():
			# Cada vértice del trozo es un vértice de la rejilla, con su misma normal
			var gi := int(round((cv[k].x + m.half_size) / m.cell_size))
			var gj := int(round((cv[k].z + m.half_size) / m.cell_size))
			var g := gj * side + gi
			# Godot comprime las normales al guardar la malla: contra la rejilla, con tolerancia
			if cv[k].distance_to(verts[g]) > POS_TOL or cn[k].distance_to(normals[g]) > NORMAL_TOL:
				grid_ok = false
			# Un vértice de borde aparece en 2-4 trozos: debe ser idéntico en todos (si no, se ve la costura)
			if verts_set.has(g):
				shared += 1
				var prev: Array = verts_set[g]
				if prev[0] != cv[k] or prev[1] != cn[k]:
					seam_ok = false
			else:
				verts_set[g] = [cv[k], cn[k]]
	_check(tris == cells * cells * 2, "triángulos %d = malla entera %d" % [tris, cells * cells * 2])
	_check(verts_set.size() == side * side, "los trozos cubren los %d vértices de la rejilla" % (side * side))
	_check(grid_ok, "posiciones y normales iguales a la rejilla entera")
	_check(shared > 0 and seam_ok, "%d vértices de borde compartidos, idénticos en cada trozo (sin costuras)" % shared)
	var chunk_m := ProceduralMap.GROUND_CHUNK_CELLS * m.cell_size + 0.01
	_check(max_extent <= chunk_m, "cada trozo mide como mucho %.1f m (máx %.1f)" % [chunk_m, max_extent])
	_check(m.get_node_or_null("GroundBody") != null, "la colisión sigue existiendo")
	var mat := (chunks[0] as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var low := Quality.level() == Quality.Level.LOW
	var want: Shader = ProceduralMap.GROUND_SHADER_MOBILE if Quality.is_mobile() or low else ProceduralMap.GROUND_SHADER
	_check(mat != null and mat.shader == want, "shader del suelo según calidad (baja=%s)" % low)
	print("ALL GROUND CHUNK CHECKS PASSED" if not _fail else "GROUND CHUNK CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
