// Simulación completa de los enemigos de datos (EnemyData) en C++: una sola llamada por tick de física.
// Replica EnemyManager._physics_process + EnemyData.update + EnemyBehavior.process_ai + tokens y densidad
// de HiveMind + EnemyVisuals.write (modo impostor). Todo el estado caliente vive aquí, en un array por
// enemigo; tras cada actualización se escribe de vuelta en el objeto EnemyData lo que lee el resto del juego
// (global_position, prev_position, velocity, yaw, is_alerted, tick_span...), así las armas y consultas no
// cambian. Lo que el C++ no puede hacer (disparar, golpear al jugador, el golpe al suelo) sale como eventos
// que EnemyManager ejecuta en GDScript.
// Si se cambia la IA en enemy_data.gd / enemy_behavior.gd / hive_mind.gd hay que cambiarla aquí también.
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class EnemyMotionNative;

class EnemySimNative : public RefCounted {
	GDCLASS(EnemySimNative, RefCounted)

public:
	enum EventKind {
		EV_RANGED_SHOT = 1, // a,b,c = dirección (to_player) ; d = velocidad de la bala
		EV_SNIPER_SHOT = 2, // a,b,c = dirección adelantada ; d = velocidad
		EV_MORTAR = 3,
		EV_MELEE_HIT = 4, // a = multiplicador de daño
		EV_SLAM = 5,
		EV_BURST = 6, // la babosa roja revienta
	};

private:
	struct En {
		Object *obj = nullptr;
		int type = 0;
		// Estado espacial
		double px = 0, py = 0, pz = 0;
		double qx = 0, qy = 0, qz = 0; // prev_position
		double vx = 0, vy = 0, vz = 0;
		double kx = 0, ky = 0, kz = 0; // knockback_velocity
		double sepx = 0, sepz = 0;
		double ground_y = 0;
		int bridge_i = -1;
		double yaw = 0;
		double sx = 1, sy = 1, sz = 1; // scale
		// Atributos (los mantiene GDScript; se recargan al marcar el enemigo como sucio)
		double hp = 1, max_hp = 1, speed = 1, attack_range = 1, detection_range = 40;
		double mode_speed_mult = 1;
		// IA
		double attack_cooldown = 0, attack_windup = 0, special_cd = 0, special_t = 0, token_wait = 0;
		double slow_timer = 0, slow_mult = 1, logic_timer = 0, vat_flash = 0, last_dist = 0;
		double sdx = 0, sdy = 0, sdz = 0; // special_dir
		double orbit_sign = 1;
		int special_state = 0, burst_left = 0, tick_span = 1, tick_age = 0, hive_cell = -1;
		bool alerted = false, has_token = false, special_hit = false, lunger = false, walking = false;
		// Lo que hay que escribir de vuelta en el objeto
		bool kb_live = false, slow_live = false, alert_sent = false, flash_live = false;
		// Dibujo (modo impostor)
		int vis_model = -1, vis_slot = -1;
		double vat_phase = 0;
	};

	std::vector<En> ens;
	// Dibujo: por modelo, índice de enemigo en cada casilla + búfer del MultiMesh
	int vis_stride = 16, vis_capacity = 512;
	std::vector<std::vector<int>> vis_lists;
	std::vector<PackedFloat32Array> vis_bufs;
	std::vector<uint8_t> vis_dirty;

	PackedFloat32Array events;
	int tokens_used = 0;
	int64_t last_shot_ms = -10000;
	uint64_t rng = 0x9E3779B97F4A7C15ull;
	bool full_writeback = false; // modo malla (no impostor): el dibujo lee tick_age, vat_flash... cada frame

	// Densidad (HiveMind._build_density)
	std::vector<int> dcount;
	std::vector<float> dsx, dsz;
	int64_t dframe = -1;
	int dox = 0, doz = 0;

	// Parámetros del tick
	double t_delta = 0, t_crowd = 1, t_elapsed = 0;
	double pl_x = 0, pl_y = 0, pl_z = 0, pv_x = 0, pv_z = 0;
	int64_t t_now_ms = 0;
	bool use_tokens = true, use_density = true;
	EnemyMotionNative *motion = nullptr;

	// Nombres de las propiedades de EnemyData
	StringName n_global_position, n_prev_position, n_velocity, n_yaw, n_is_alerted, n_tick_span, n_tick_age,
			n_ground_y, n_bridge_i, n_vat_walking, n_knockback_velocity, n_slow_timer, n_slow_multiplier, n_hp,
			n_max_hp, n_speed, n_attack_range, n_detection_range, n_scale, n_type, n_mode_speed_mult,
			n_attack_cooldown, n_special_cd, n_lunger, n_orbit_sign, n_logic_timer, n_vat_phase, n_vat_flash,
			n_last_dist, n_has_token, n_burst_left, n_vat_idx;

	double randf();
	void update(int i, double dt);
	void move(En &e, double dt);
	void compute_separation(En &e);
	void build_density();
	bool acquire_token(En &e);
	void release_token(En &e, double retry);
	bool try_global_shot();
	void push_event(int kind, int idx, double a = 0, double b = 0, double c = 0, double d = 0);
	void ai(int i, double dt, double tx, double tz, double dist, double spd, double &ox, double &oz);
	void ai_melee(int i, double dt, double tx, double tz, double dist, double spd, double &ox, double &oz);
	void writeback(En &e);
	void vis_write(const En &e, double tick_f);

protected:
	static void _bind_methods();

public:
	EnemySimNative();

	void vis_setup(int p_models, int p_capacity, int p_stride);
	void set_full_writeback(bool p_on) { full_writeback = p_on; }
	int add(Object *p_obj);
	void remove(int p_idx);
	void load_full(int p_idx);
	void load_stats(int p_idx);
	void add_knockback(int p_idx, const Vector3 &p_v);
	void set_knockback(int p_idx, const Vector3 &p_v);
	void apply_slow(int p_idx, double p_duration, double p_mult);
	void set_alerted(int p_idx, bool p_on);
	void set_position(int p_idx, const Vector3 &p_pos);
	void flash(int p_idx, double p_tick);
	void clear();
	int count() const { return (int)ens.size(); }
	int get_tokens_used() const { return tokens_used; }
	bool has_token(int p_idx) const;
	// Para que GDScript sepa si esta biblioteca ya conoce las criaturas (ratas, babosas): una antigua no.
	bool supports_creatures() const { return true; }

	// Un tick completo. Devuelve los eventos (6 floats cada uno: tipo, índice, a, b, c, d).
	PackedFloat32Array step(Object *p_motion, double p_delta, int64_t p_tick, const Vector3 &p_player_pos,
			const Vector3 &p_player_vel, double p_crowd_scale, double p_elapsed, int64_t p_now_ms,
			int64_t p_physics_frame, bool p_use_tokens, bool p_use_density);

	PackedFloat32Array vis_buffer(int p_model) const;
	bool vis_take_dirty(int p_model);
	int vis_count(int p_model) const;
};

} // namespace godot
