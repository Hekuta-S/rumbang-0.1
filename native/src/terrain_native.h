// Malla del terreno de supervivencia en C++: la parte cara de ProceduralMap._build_terrain
// (scripts/world/procedural_map.gd). Calcula alturas, colores, UV, normales e índices con el mismo
// algoritmo que _terrain() y los bucles de _build_terrain(), usando los mismos objetos FastNoiseLite.
// Si se cambia _terrain() en GDScript hay que cambiarlo aquí también (test_native_terrain compara).
#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class TerrainNative : public RefCounted {
	GDCLASS(TerrainNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// params: half_size, cell_size, hill_amplitude, basin_depth, basin_floor_radius, basin_rim_radius,
	// play_half, cliff_height, basin_center (Vector2), ramp_end (Vector2), ramp_surface_y.
	// mesas / bridges: los mismos Arrays de diccionarios que ProceduralMap._mesas / _bridges.
	// Devuelve [side, heights, verts, colors, uvs, normals, indices].
	Array build(const Dictionary &params, const Ref<FastNoiseLite> &hills, const Ref<FastNoiseLite> &detail,
			const Array &mesas, const Array &bridges) const;
};

} // namespace godot
