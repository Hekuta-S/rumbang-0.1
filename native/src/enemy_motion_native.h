// Movimiento de enemigos en C++: la parte más caliente de EnemyMotion (scripts/core/enemy_motion.gd).
// Mismo algoritmo, paso a paso: relieve (altura bilineal, pendientes, trepar mesetas, deslizar en
// acantilados), puentes, obstáculos (cilindros y cajas) y el jugador. EnemyMotion le pasa una vez por mapa
// los mismos arrays empaquetados que usa en GDScript y luego llama a move() por enemigo.
// Si se cambia el algoritmo en enemy_motion.gd hay que cambiarlo aquí también (test_native_motion compara).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace godot {

class EnemyMotionNative : public RefCounted {
	GDCLASS(EnemyMotionNative, RefCounted)

	// Relieve: copia de la malla de alturas del mapa
	PackedFloat32Array hs;
	int hside = 0;
	double hhalf = 0.0;
	double hcell = 1.0;
	double climb_half = 0.0;
	// Obstáculos: rejilla densa (ver EnemyMotion._flatten_obstacles)
	PackedFloat32Array obs;
	PackedInt32Array ocell_start;
	PackedInt32Array ocell_count;
	int ox0 = 0, oz0 = 0, ow = 0, oh = 0;
	// Puentes: EnemyMotion._bpk (BSTRIDE floats por puente)
	PackedFloat32Array bpk;


protected:
	static void _bind_methods();

public:
	void set_heights(const PackedFloat32Array &p_hs, int p_side, double p_half, double p_cell, double p_climb_half);
	void set_obstacles(const PackedFloat32Array &p_obs, const PackedInt32Array &p_start, const PackedInt32Array &p_count,
			int p_ox0, int p_oz0, int p_ow, int p_oh);
	void set_bridges(const PackedFloat32Array &p_bpk);
	double height_at(double x, double z) const;
	// Un paso completo: Vector4(x, z, altura, puente o -1). Igual que EnemyMotion.move.
	Vector4 move(double px, double pz, double vx, double vz, double delta, double ground_y, int bridge_i,
			double player_x, double player_z) const;
};

} // namespace godot
