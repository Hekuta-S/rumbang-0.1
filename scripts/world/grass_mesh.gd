class_name GrassMesh
extends RefCounted

## Mechón de pasto procedural: varias hojas triangulares en abanico, con
## degradado de color por vértice y shader de viento (grass_wind.gdshader).

const SHADER: Shader = preload("res://assets/shaders/grass_wind.gdshader")
const BLADES := 7
const BASE := Color(0.06, 0.16, 0.05)
const TIP := Color(0.32, 0.55, 0.18)

static var _cached: Mesh

static func build() -> Mesh:
	if _cached != null:
		return _cached
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in BLADES:
		var ang := TAU * float(i) / BLADES + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x) * rng.randf_range(0.035, 0.06)
		var root := dir * rng.randf_range(0.0, 0.12)
		var h := rng.randf_range(0.28, 0.5)
		var tip := root + dir * rng.randf_range(0.08, 0.2) + Vector3(0.0, h, 0.0)
		var tip_col := TIP.lerp(Color(0.45, 0.5, 0.2), rng.randf() * 0.4)
		st.set_normal(Vector3.UP)
		st.set_color(BASE); st.set_uv(Vector2(0, 1)); st.add_vertex(root - side)
		st.set_color(BASE); st.set_uv(Vector2(1, 1)); st.add_vertex(root + side)
		st.set_color(tip_col); st.set_uv(Vector2(0.5, 0)); st.add_vertex(tip)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	st.set_material(mat)
	_cached = st.commit()
	return _cached
