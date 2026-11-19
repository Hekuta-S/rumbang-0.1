// Ver enemy_sim_native.h. Cada bloque cita la función GDScript que replica.
#include "enemy_sim_native.h"
#include "enemy_motion_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
// EnemyData
constexpr double SPAN_MID_DIST = 14.0;
constexpr double SPAN_FAR_DIST = 40.0;
constexpr double SPAN_NEAR_MIN = 3.0;
constexpr double SPAN_IDLE_DIST = 60.0;
constexpr double RING_SPAN_MARGIN = 0.5;
constexpr double SEP_RADIUS = 1.0;
constexpr double SEP_STRENGTH = 2.2;
// EnemyBehavior
constexpr double RANGED_COOLDOWN = 4.5;
constexpr double SNIPER_COOLDOWN = 5.5;
constexpr double MORTAR_COOLDOWN = 6.5;
constexpr int64_t GLOBAL_SHOT_GAP_MS = 400;
constexpr double BURST_FROM = 90.0;
constexpr double BURST_GAP = 0.3;
constexpr double STRAFE_SPEED = 0.55;
constexpr double LUNGE_FROM = 60.0;
constexpr double LUNGE_MIN = 4.5;
constexpr double LUNGE_MAX = 9.5;
constexpr double LUNGE_WINDUP = 0.55;
constexpr double LUNGE_TIME = 0.45;
constexpr double LUNGE_SPEED_MULT = 3.6;
constexpr double LUNGE_DAMAGE_MULT = 1.4;
constexpr double LUNGE_CD_MIN = 5.0, LUNGE_CD_MAX = 8.0;
constexpr double SLAM_FROM = 120.0;
constexpr double SLAM_MIN = 3.5, SLAM_MAX = 10.0;
constexpr double SLAM_COOLDOWN = 8.0;
constexpr double ENRAGE_HP = 0.35;
constexpr double ENRAGE_SPEED = 1.5;
constexpr double RING_GAP = 1.3;
constexpr double RELEASE_GAP = 3.0;
constexpr double ORBIT_SPEED = 0.45;
// HiveMind
constexpr int MELEE_TOKENS = 12;
constexpr double TOKEN_RETRY = 1.0;
constexpr double DENS_CELL = 1.0;
constexpr int DENS_SIDE = 128;
constexpr int DENS_MAX_NEIGHBORS = 6;
constexpr int64_t DENS_REBUILD_TICKS = 4;
// EnemyData.EnemyType
enum { T_RANGED = 0, T_NORMAL = 1, T_BRUTE = 2, T_SNIPER = 3, T_ZOMBIE = 4, T_MORTAR = 5 };
constexpr int EV_STRIDE = 6;

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}
} // namespace

EnemySimNative::EnemySimNative() {
	n_global_position = StringName("global_position");
	n_prev_position = StringName("prev_position");
	n_velocity = StringName("velocity");
	n_yaw = StringName("yaw");
	n_is_alerted = StringName("is_alerted");
	n_tick_span = StringName("tick_span");
	n_tick_age = StringName("tick_age");
	n_ground_y = StringName("ground_y");
	n_bridge_i = StringName("bridge_i");
	n_vat_walking = StringName("vat_walking");
	n_knockback_velocity = StringName("knockback_velocity");
	n_slow_timer = StringName("slow_timer");
	n_slow_multiplier = StringName("slow_multiplier");
	n_hp = StringName("hp");
	n_max_hp = StringName("max_hp");
	n_speed = StringName("speed");
	n_attack_range = StringName("attack_range");
	n_detection_range = StringName("detection_range");
	n_scale = StringName("scale");
	n_type = StringName("type");
	n_mode_speed_mult = StringName("_mode_speed_mult");
	n_attack_cooldown = StringName("attack_cooldown");
	n_special_cd = StringName("special_cd");
	n_lunger = StringName("lunger");
	n_orbit_sign = StringName("orbit_sign");
	n_logic_timer = StringName("_logic_timer");
	n_vat_phase = StringName("vat_phase");
	n_vat_flash = StringName("vat_flash");
	n_last_dist = StringName("_last_dist");
	n_has_token = StringName("has_token");
	n_burst_left = StringName("burst_left");
	n_vat_idx = StringName("vat_idx");
}

void EnemySimNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("vis_setup", "models", "capacity", "stride"), &EnemySimNative::vis_setup);
	ClassDB::bind_method(D_METHOD("set_full_writeback", "on"), &EnemySimNative::set_full_writeback);
	ClassDB::bind_method(D_METHOD("add", "enemy"), &EnemySimNative::add);
	ClassDB::bind_method(D_METHOD("remove", "idx"), &EnemySimNative::remove);
	ClassDB::bind_method(D_METHOD("load_full", "idx"), &EnemySimNative::load_full);
	ClassDB::bind_method(D_METHOD("load_stats", "idx"), &EnemySimNative::load_stats);
	ClassDB::bind_method(D_METHOD("add_knockback", "idx", "v"), &EnemySimNative::add_knockback);
	ClassDB::bind_method(D_METHOD("set_knockback", "idx", "v"), &EnemySimNative::set_knockback);
	ClassDB::bind_method(D_METHOD("apply_slow", "idx", "duration", "mult"), &EnemySimNative::apply_slow);
	ClassDB::bind_method(D_METHOD("set_alerted", "idx", "on"), &EnemySimNative::set_alerted);
	ClassDB::bind_method(D_METHOD("set_position", "idx", "pos"), &EnemySimNative::set_position);
	ClassDB::bind_method(D_METHOD("flash", "idx", "tick"), &EnemySimNative::flash);
	ClassDB::bind_method(D_METHOD("clear"), &EnemySimNative::clear);
	ClassDB::bind_method(D_METHOD("count"), &EnemySimNative::count);
	ClassDB::bind_method(D_METHOD("get_tokens_used"), &EnemySimNative::get_tokens_used);
	ClassDB::bind_method(D_METHOD("has_token", "idx"), &EnemySimNative::has_token);
	ClassDB::bind_method(D_METHOD("step", "motion", "delta", "tick", "player_pos", "player_vel", "crowd_scale",
								 "elapsed", "now_ms", "physics_frame", "use_tokens", "use_density"),
			&EnemySimNative::step);
	ClassDB::bind_method(D_METHOD("vis_buffer", "model"), &EnemySimNative::vis_buffer);
	ClassDB::bind_method(D_METHOD("vis_take_dirty", "model"), &EnemySimNative::vis_take_dirty);
	ClassDB::bind_method(D_METHOD("vis_count", "model"), &EnemySimNative::vis_count);
}

double EnemySimNative::randf() {
	// xorshift64*: [0, 1)
	rng ^= rng >> 12;
	rng ^= rng << 25;
	rng ^= rng >> 27;
	return (double)((rng * 2685821657736338717ull) >> 11) * (1.0 / 9007199254740992.0);
}

// ───────────────────────────── Altas, bajas y recarga desde el objeto ─────────────────────────────

void EnemySimNative::vis_setup(int p_models, int p_capacity, int p_stride) {
	vis_capacity = p_capacity;
	vis_stride = p_stride;
	vis_lists.assign(p_models, std::vector<int>());
	vis_bufs.assign(p_models, PackedFloat32Array());
	vis_dirty.assign(p_models, 0);
	for (int k = 0; k < p_models; k++) {
		vis_bufs[k].resize((int64_t)p_capacity * p_stride);
		vis_bufs[k].fill(0.0f);
	}
}

// Igual que EnemyManager.spawn: el índice devuelto es el active_idx del enemigo.
int EnemySimNative::add(Object *p_obj) {
	En e;
	e.obj = p_obj;
	ens.push_back(e);
	int idx = (int)ens.size() - 1;
	load_full(idx);
	En &n = ens[idx];
	// Casilla fija en el cubo de impostores (EnemyVisuals.attach)
	int model = (int)p_obj->get(n_vat_idx);
	if (model >= 0 && model < (int)vis_lists.size() && (int)vis_lists[model].size() < vis_capacity) {
		n.vis_model = model;
		n.vis_slot = (int)vis_lists[model].size();
		vis_lists[model].push_back(idx);
		vis_bufs[model].ptrw()[(int64_t)n.vis_slot * vis_stride + 10] = -1000.0f; // sin golpe reciente
	}
	return idx;
}

// Swap-remove, igual que EnemyManager.release (el último ocupa el hueco).
void EnemySimNative::remove(int p_idx) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	release_token(e, 0.0);
	// EnemyVisuals.detach
	if (e.vis_slot >= 0) {
		std::vector<int> &list = vis_lists[e.vis_model];
		int slot = e.vis_slot;
		int last_enemy = list.back();
		list.pop_back();
		if (slot < (int)list.size()) {
			list[slot] = last_enemy;
			ens[last_enemy].vis_slot = slot;
			float *buf = vis_bufs[e.vis_model].ptrw();
			int64_t src = (int64_t)list.size() * vis_stride;
			int64_t dst = (int64_t)slot * vis_stride;
			for (int j = 0; j < vis_stride; j++) {
				buf[dst + j] = buf[src + j];
			}
		}
		vis_dirty[e.vis_model] = 1;
	}
	int last = (int)ens.size() - 1;
	if (p_idx != last) {
		ens[p_idx] = ens[last];
		En &m = ens[p_idx];
		if (m.vis_slot >= 0) {
			vis_lists[m.vis_model][m.vis_slot] = p_idx;
		}
	}
	ens.pop_back();
}

void EnemySimNative::load_full(int p_idx) {
	En &e = ens[p_idx];
	Object *o = e.obj;
	e.type = (int)o->get(n_type);
	Vector3 p = o->get(n_global_position);
	Vector3 q = o->get(n_prev_position);
	Vector3 v = o->get(n_velocity);
	Vector3 k = o->get(n_knockback_velocity);
	e.px = p.x, e.py = p.y, e.pz = p.z;
	e.qx = q.x, e.qy = q.y, e.qz = q.z;
	e.vx = v.x, e.vy = v.y, e.vz = v.z;
	e.kx = k.x, e.ky = k.y, e.kz = k.z;
	e.sepx = e.sepz = 0.0;
	e.ground_y = (double)o->get(n_ground_y);
	e.bridge_i = (int)o->get(n_bridge_i);
	e.yaw = (double)o->get(n_yaw);
	e.mode_speed_mult = (double)o->get(n_mode_speed_mult);
	e.attack_cooldown = (double)o->get(n_attack_cooldown);
	e.special_cd = (double)o->get(n_special_cd);
	e.lunger = (bool)o->get(n_lunger);
	e.orbit_sign = (double)o->get(n_orbit_sign);
	e.logic_timer = (double)o->get(n_logic_timer);
	e.tick_age = (int)o->get(n_tick_age);
	e.tick_span = (int)o->get(n_tick_span);
	e.vat_phase = (double)o->get(n_vat_phase);
	e.slow_timer = (double)o->get(n_slow_timer);
	e.slow_mult = (double)o->get(n_slow_multiplier);
	e.burst_left = (int)o->get(n_burst_left);
	e.attack_windup = 0.0;
	e.special_state = 0;
	e.special_t = 0.0;
	e.special_hit = false;
	e.token_wait = 0.0;
	e.has_token = false;
	e.vat_flash = 0.0;
	e.hive_cell = -1;
	e.walking = false;
	e.kb_live = (k.x * k.x + k.y * k.y + k.z * k.z) > 0.0;
	e.slow_live = e.slow_timer > 0.0;
	load_stats(p_idx);
	e.alert_sent = e.alerted;
}

// Atributos que cambia el resto del juego (vida, velocidad, escala, alerta, teletransporte).
void EnemySimNative::load_stats(int p_idx) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	Object *o = e.obj;
	e.hp = (double)o->get(n_hp);
	e.max_hp = (double)o->get(n_max_hp);
	e.speed = (double)o->get(n_speed);
	e.attack_range = (double)o->get(n_attack_range);
	e.detection_range = (double)o->get(n_detection_range);
	Vector3 s = o->get(n_scale);
	e.sx = s.x, e.sy = s.y, e.sz = s.z;
	e.alerted = (bool)o->get(n_is_alerted);
	e.alert_sent = e.alerted;
	Vector3 p = o->get(n_global_position);
	if (std::abs(p.x - e.px) > 1e-4 || std::abs(p.z - e.pz) > 1e-4 || std::abs(p.y - e.py) > 1e-4) {
		set_position(p_idx, p);
	}
}

void EnemySimNative::set_position(int p_idx, const Vector3 &p_pos) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	e.px = e.qx = p_pos.x;
	e.py = e.qy = p_pos.y;
	e.pz = e.qz = p_pos.z;
	e.ground_y = motion != nullptr ? motion->height_at(p_pos.x, p_pos.z) : p_pos.y;
	e.bridge_i = -1;
}

void EnemySimNative::add_knockback(int p_idx, const Vector3 &p_v) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	// EnemyData.apply_knockback: (kb + v).limit_length(24)
	double x = e.kx + p_v.x, y = e.ky + p_v.y, z = e.kz + p_v.z;
	double l = std::sqrt(x * x + y * y + z * z);
	if (l > 24.0) {
		double f = 24.0 / l;
		x *= f, y *= f, z *= f;
	}
	e.kx = x, e.ky = y, e.kz = z;
	e.kb_live = true;
}

void EnemySimNative::set_knockback(int p_idx, const Vector3 &p_v) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	e.kx = p_v.x, e.ky = p_v.y, e.kz = p_v.z;
	e.kb_live = true;
}

// EnemyData.apply_slow
void EnemySimNative::apply_slow(int p_idx, double p_duration, double p_mult) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	e.slow_mult = std::min(e.slow_mult, p_mult);
	e.slow_timer = std::max(e.slow_timer, p_duration);
	e.slow_live = true;
}

void EnemySimNative::set_alerted(int p_idx, bool p_on) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	ens[p_idx].alerted = p_on;
	ens[p_idx].alert_sent = p_on;
}

// EnemyVisuals.flash
void EnemySimNative::flash(int p_idx, double p_tick) {
	if (p_idx < 0 || p_idx >= (int)ens.size()) {
		return;
	}
	En &e = ens[p_idx];
	e.vat_flash = std::max(e.vat_flash, 0.08);
	e.flash_live = true;
	if (e.vis_slot < 0) {
		return;
	}
	vis_bufs[e.vis_model].ptrw()[(int64_t)e.vis_slot * vis_stride + 10] = (float)p_tick;
	vis_dirty[e.vis_model] = 1;
}

void EnemySimNative::clear() {
	ens.clear();
	for (auto &l : vis_lists) {
		l.clear();
	}
	for (auto &d : vis_dirty) {
		d = 1;
	}
	tokens_used = 0;
	dframe = -1;
}

bool EnemySimNative::has_token(int p_idx) const {
	return p_idx >= 0 && p_idx < (int)ens.size() && ens[p_idx].has_token;
}

// ───────────────────────────── HiveMind ─────────────────────────────

bool EnemySimNative::acquire_token(En &e) {
	if (!use_tokens || e.has_token) {
		return true;
	}
	if (e.token_wait > 0.0 || tokens_used >= MELEE_TOKENS) {
		return false;
	}
	tokens_used++;
	e.has_token = true;
	return true;
}

void EnemySimNative::release_token(En &e, double retry) {
	if (e.has_token) {
		e.has_token = false;
		tokens_used = std::max(tokens_used - 1, 0);
	}
	e.token_wait = std::max(e.token_wait, retry);
}

// HiveMind._build_density (solo con los enemigos de datos)
void EnemySimNative::build_density() {
	const int n = DENS_SIDE * DENS_SIDE;
	if ((int)dcount.size() != n) {
		dcount.resize(n);
		dsx.resize(n);
		dsz.resize(n);
	}
	std::fill(dcount.begin(), dcount.end(), 0);
	std::fill(dsx.begin(), dsx.end(), 0.0f);
	std::fill(dsz.begin(), dsz.end(), 0.0f);
	const double inv = 1.0 / DENS_CELL;
	const int half = DENS_SIDE / 2;
	dox = (int)std::floor(pl_x * inv) - half;
	doz = (int)std::floor(pl_z * inv) - half;
	for (En &e : ens) {
		int ix = (int)std::floor(e.px * inv) - dox;
		int iz = (int)std::floor(e.pz * inv) - doz;
		if (ix < 0 || iz < 0 || ix >= DENS_SIDE || iz >= DENS_SIDE) {
			e.hive_cell = -1;
			continue;
		}
		int i = iz * DENS_SIDE + ix;
		e.hive_cell = i;
		dcount[i] += 1;
		dsx[i] += (float)e.px;
		dsz[i] += (float)e.pz;
	}
}

// EnemyData._compute_separation + HiveMind.separation_push. Fuera de la ventana de densidad (más de 64 m
// del jugador) no hay empuje: el GDScript usaba ahí la separación exacta de EnemyRegistry.
void EnemySimNative::compute_separation(En &e) {
	e.sepx = e.sepz = 0.0;
	if (!e.alerted || !use_density) {
		return;
	}
	const double inv = 1.0 / DENS_CELL;
	int mx = (int)std::floor(e.px * inv) - dox;
	int mz = (int)std::floor(e.pz * inv) - doz;
	if (mx < 0 || mz < 0 || mx >= DENS_SIDE || mz >= DENS_SIDE) {
		return;
	}
	const double radius = SEP_RADIUS;
	int span = (int)std::ceil(radius * inv);
	double r2 = radius * radius;
	double pushx = 0.0, pushz = 0.0;
	int budget = DENS_MAX_NEIGHBORS;
	for (int iz = std::max(mz - span, 0); iz <= std::min(mz + span, DENS_SIDE - 1) && budget > 0; iz++) {
		for (int ix = std::max(mx - span, 0); ix <= std::min(mx + span, DENS_SIDE - 1); ix++) {
			int i = iz * DENS_SIDE + ix;
			int m = dcount[i];
			double sx = dsx[i];
			double sz = dsz[i];
			if (i == e.hive_cell) {
				m -= 1;
				sx -= e.px;
				sz -= e.pz;
			}
			if (m <= 0) {
				continue;
			}
			double ax = e.px - sx / (double)m;
			double az = e.pz - sz / (double)m;
			double d2 = ax * ax + az * az;
			if (d2 > r2) {
				continue;
			}
			if (d2 < 0.0001) {
				ax = randf() - 0.5;
				az = randf() - 0.5;
				d2 = 0.25;
			}
			double d = std::sqrt(d2);
			int k = std::min(m, budget);
			double w = (1.0 - std::min(d / radius, 1.0)) / d * (double)k;
			pushx += ax * w;
			pushz += az * w;
			budget -= k;
			if (budget <= 0) {
				break;
			}
		}
	}
	double l2 = pushx * pushx + pushz * pushz;
	if (l2 > 0.0001) {
		if (l2 > 1.0) {
			double l = std::sqrt(l2);
			pushx /= l;
			pushz /= l;
		}
		e.sepx = pushx * SEP_STRENGTH;
		e.sepz = pushz * SEP_STRENGTH;
	}
}

bool EnemySimNative::try_global_shot() {
	if (t_now_ms - last_shot_ms < GLOBAL_SHOT_GAP_MS) {
		return false;
	}
	last_shot_ms = t_now_ms;
	return true;
}

void EnemySimNative::push_event(int kind, int idx, double a, double b, double c, double d) {
	int64_t n = events.size();
	events.resize(n + EV_STRIDE);
	float *w = events.ptrw() + n;
	w[0] = (float)kind;
	w[1] = (float)idx;
	w[2] = (float)a;
	w[3] = (float)b;
	w[4] = (float)c;
	w[5] = (float)d;
}

// ───────────────────────────── IA (EnemyBehavior.*.process_ai) ─────────────────────────────

// MeleeGoblinBehavior.process_ai
void EnemySimNative::ai_melee(int i, double dt, double tx, double tz, double dist, double spd, double &ox, double &oz) {
	En &e = ens[i];
	double ring = e.attack_range + RING_GAP;
	if (e.has_token && dist > ring + RELEASE_GAP) {
		release_token(e, 0.0);
	}
	if (dist <= ring && !acquire_token(e)) {
		e.attack_windup = 0.0;
		// _wait_in_ring
		if (dist < 0.01) {
			ox = oz = 0.0;
			return;
		}
		double rx = tx / dist, rz = tz / dist;
		double tgx = -rz * e.orbit_sign, tgz = rx * e.orbit_sign;
		double err = clampd((dist - ring) / RING_GAP, -1.0, 1.0);
		ox = (tgx * ORBIT_SPEED + rx * err) * spd;
		oz = (tgz * ORBIT_SPEED + rz * err) * spd;
		return;
	}
	ox = oz = 0.0;
	if (dist > e.attack_range - 0.2 && dist > 0.0) {
		ox = tx / dist * spd;
		oz = tz / dist * spd;
	}
	if (dist <= e.attack_range) {
		if (e.attack_cooldown <= 0.0) {
			e.attack_windup += dt;
			if (e.attack_windup >= 0.4) {
				e.attack_cooldown = 2.0;
				e.attack_windup = 0.0;
				push_event(EV_MELEE_HIT, i, 1.0);
				release_token(e, TOKEN_RETRY);
			}
		}
	} else {
		e.attack_windup = 0.0;
	}
}

void EnemySimNative::ai(int i, double dt, double tx, double tz, double dist, double spd, double &ox, double &oz) {
	En &e = ens[i];
	ox = oz = 0.0;
	double nx = dist > 0.0 ? tx / dist : 0.0;
	double nz = dist > 0.0 ? tz / dist : 0.0;
	switch (e.type) {
		case T_RANGED: {
			if (dist > 11.5) {
				ox = nx * spd, oz = nz * spd;
			} else if (dist < 8.0) {
				ox = -nx * spd, oz = -nz * spd;
			} else if (dist > 0.01) {
				ox = -nz * e.orbit_sign * spd * STRAFE_SPEED;
				oz = nx * e.orbit_sign * spd * STRAFE_SPEED;
			}
			bool burst_shot = e.burst_left > 0 && e.attack_cooldown <= 0.0;
			if (burst_shot || (dist <= e.attack_range && e.attack_cooldown <= 0.0 && try_global_shot())) {
				if (burst_shot) {
					e.burst_left = 0;
					e.attack_cooldown = RANGED_COOLDOWN;
				} else if (t_elapsed >= BURST_FROM) {
					e.burst_left = 1;
					e.attack_cooldown = BURST_GAP;
				} else {
					e.attack_cooldown = RANGED_COOLDOWN;
				}
				e.orbit_sign = -e.orbit_sign;
				push_event(EV_RANGED_SHOT, i, tx, 0.0, tz, 16.0);
			}
		} break;
		case T_SNIPER: {
			if (dist > 8.5) {
				ox = nx * spd, oz = nz * spd;
			} else if (dist < 5.0) {
				ox = -nx * spd, oz = -nz * spd;
			}
			if (dist <= e.attack_range && e.attack_cooldown <= 0.0 && try_global_shot()) {
				e.attack_cooldown = SNIPER_COOLDOWN;
				// SniperGoblinBehavior.lead_aim
				double ax = tx, az = tz;
				if (t_elapsed >= BURST_FROM) {
					ax += pv_x * (dist / 34.0) * 0.8;
					az += pv_z * (dist / 34.0) * 0.8;
				}
				push_event(EV_SNIPER_SHOT, i, ax, 0.0, az, 34.0);
			}
		} break;
		case T_MORTAR: {
			if (dist > 24.0) {
				ox = nx * spd, oz = nz * spd;
			} else if (dist < 16.0) {
				ox = -nx * spd, oz = -nz * spd;
			}
			if (dist <= e.attack_range && dist >= 10.0 && e.attack_cooldown <= 0.0 && try_global_shot()) {
				e.attack_cooldown = MORTAR_COOLDOWN;
				push_event(EV_MORTAR, i);
			}
		} break;
		case T_NORMAL: {
			// NormalGoblinBehavior.process_ai (embestida)
			if (e.special_state == 1) {
				e.special_t -= dt;
				e.vat_flash = 0.15;
				e.flash_live = true;
				if (e.special_t <= 0.0) {
					e.special_state = 2;
					e.special_t = LUNGE_TIME;
					e.special_hit = false;
					e.sdx = nx, e.sdy = 0.0, e.sdz = nz;
				}
				return;
			}
			if (e.special_state == 2) {
				e.special_t -= dt;
				if (!e.special_hit && dist <= e.attack_range + 0.4) {
					e.special_hit = true;
					push_event(EV_MELEE_HIT, i, LUNGE_DAMAGE_MULT);
				}
				if (e.special_t <= 0.0 || e.special_hit) {
					e.special_state = 0;
					e.special_cd = LUNGE_CD_MIN + randf() * (LUNGE_CD_MAX - LUNGE_CD_MIN);
				}
				ox = e.sdx * spd * LUNGE_SPEED_MULT;
				oz = e.sdz * spd * LUNGE_SPEED_MULT;
				return;
			}
			if (e.lunger && e.special_cd <= 0.0 && dist >= LUNGE_MIN && dist <= LUNGE_MAX && t_elapsed >= LUNGE_FROM) {
				e.special_state = 1;
				e.special_t = LUNGE_WINDUP;
				return;
			}
			ai_melee(i, dt, tx, tz, dist, spd, ox, oz);
		} break;
		case T_BRUTE: {
			// HeavyBruteBehavior.process_ai (golpe al suelo)
			if (e.special_cd <= 0.0 && dist >= SLAM_MIN && dist <= SLAM_MAX && t_elapsed >= SLAM_FROM) {
				e.special_cd = SLAM_COOLDOWN;
				push_event(EV_SLAM, i);
			}
			ai_melee(i, dt, tx, tz, dist, spd, ox, oz);
		} break;
		case T_ZOMBIE: {
			double f = (e.hp < e.max_hp * ENRAGE_HP && t_elapsed >= LUNGE_FROM) ? ENRAGE_SPEED : 1.0;
			ai_melee(i, dt, tx, tz, dist, spd * f, ox, oz);
		} break;
		default:
			break;
	}
}

// ───────────────────────────── Movimiento y actualización ─────────────────────────────

// EnemyData._move -> EnemyMotion.move
void EnemySimNative::move(En &e, double dt) {
	e.vy = 0.0;
	if (motion != nullptr) {
		Vector4 r = motion->move(e.px, e.pz, e.vx, e.vz, dt, e.ground_y, e.bridge_i, pl_x, pl_z);
		e.px = r.x;
		e.pz = r.y;
		e.py = r.z;
		e.ground_y = r.z;
		e.bridge_i = (int)r.w;
	} else {
		e.px += e.vx * dt;
		e.pz += e.vz * dt;
	}
}

// EnemyData.update
void EnemySimNative::update(int i, double dt) {
	En &e = ens[i];
	e.qx = e.px, e.qy = e.py, e.qz = e.pz;

	if (e.attack_cooldown > 0.0) {
		e.attack_cooldown -= dt;
	}
	if (e.special_cd > 0.0) {
		e.special_cd -= dt;
	}
	if (e.token_wait > 0.0) {
		e.token_wait -= dt;
	}
	if (e.slow_timer > 0.0) {
		e.slow_timer -= dt;
		if (e.slow_timer <= 0.0) {
			e.slow_mult = 1.0;
		}
	}
	double kl2 = e.kx * e.kx + e.ky * e.ky + e.kz * e.kz;
	if (kl2 > 0.01) {
		double kl = std::sqrt(kl2);
		double d = 30.0 * dt;
		if (kl <= d) {
			e.kx = e.ky = e.kz = 0.0;
		} else {
			double f = (kl - d) / kl;
			e.kx *= f, e.ky *= f, e.kz *= f;
		}
	} else {
		e.kx = e.ky = e.kz = 0.0;
	}
	e.vat_flash = std::max(e.vat_flash - dt, 0.0);

	double tx = pl_x - e.px;
	double tz = pl_z - e.pz;
	double d2 = tx * tx + tz * tz;
	double dist = std::sqrt(d2);
	e.last_dist = dist;

	if (!e.alerted && dist > SPAN_IDLE_DIST) {
		e.tick_span = 8;
	} else if (!e.alerted || dist > SPAN_FAR_DIST / t_crowd) {
		e.tick_span = 4;
	} else if (dist > std::max(SPAN_MID_DIST / t_crowd, SPAN_NEAR_MIN)) {
		e.tick_span = 2;
	} else {
		e.tick_span = 1;
	}
	if (e.tick_span == 1 && !e.has_token && dist > e.attack_range + RING_SPAN_MARGIN) {
		e.tick_span = 2;
	}

	e.logic_timer -= dt;
	if (e.logic_timer <= 0.0) {
		e.logic_timer = (0.2 + randf() * 0.1) * t_crowd;
		if (!e.alerted) {
			if (d2 <= e.detection_range * e.detection_range || e.hp < e.max_hp) {
				e.alerted = true;
			}
		}
		compute_separation(e);
	}

	if (!e.alerted) {
		e.vx = e.kx, e.vy = e.ky, e.vz = e.kz;
		move(e, dt);
		e.walking = (e.vx * e.vx + e.vz * e.vz) > 0.2;
		return;
	}

	if (d2 > 0.01) {
		e.yaw = std::atan2(-tx, -tz);
	}
	double spd = e.speed * e.slow_mult * e.mode_speed_mult;
	double ox = 0.0, oz = 0.0;
	ai(i, dt, tx, tz, dist, spd, ox, oz);
	En &f = ens[i];
	f.vx = ox + f.kx + f.sepx;
	f.vy = f.ky;
	f.vz = oz + f.kz + f.sepz;
	move(f, dt);
	f.walking = (f.vx * f.vx + f.vz * f.vz) > 0.2;
}

// Lo que el resto del juego lee de EnemyData.
void EnemySimNative::writeback(En &e) {
	Object *o = e.obj;
	o->set(n_global_position, Vector3(e.px, e.py, e.pz));
	o->set(n_prev_position, Vector3(e.qx, e.qy, e.qz));
	o->set(n_velocity, Vector3(e.vx, 0.0, e.vz));
	o->set(n_yaw, e.yaw);
	o->set(n_tick_span, e.tick_span);
	if (e.alerted != e.alert_sent) {
		e.alert_sent = e.alerted;
		o->set(n_is_alerted, e.alerted);
	}
	bool kb_now = (e.kx != 0.0 || e.ky != 0.0 || e.kz != 0.0);
	if (kb_now || e.kb_live) {
		o->set(n_knockback_velocity, Vector3(e.kx, e.ky, e.kz));
		e.kb_live = kb_now;
	}
	bool slow_now = e.slow_timer > 0.0;
	if (slow_now || e.slow_live) {
		o->set(n_slow_timer, e.slow_timer);
		o->set(n_slow_multiplier, e.slow_mult);
		e.slow_live = slow_now;
	}
	if (full_writeback) {
		o->set(n_vat_walking, e.walking);
		o->set(n_last_dist, e.last_dist);
		bool flash_now = e.vat_flash > 0.0;
		if (flash_now || e.flash_live) {
			o->set(n_vat_flash, e.vat_flash);
			e.flash_live = flash_now;
		}
	}
}

// EnemyVisuals.write
void EnemySimNative::vis_write(const En &e, double tick_f) {
	if (e.vis_slot < 0) {
		return;
	}
	float *buf = vis_bufs[e.vis_model].ptrw();
	int64_t i = (int64_t)e.vis_slot * vis_stride;
	buf[i] = (float)e.sx;
	buf[i + 1] = (float)(e.qx - e.px);
	buf[i + 2] = (float)tick_f;
	buf[i + 3] = (float)e.px;
	buf[i + 4] = (float)e.sy;
	buf[i + 5] = (float)(e.qy - e.py);
	buf[i + 6] = (float)e.tick_span;
	buf[i + 7] = (float)e.py;
	buf[i + 8] = (float)e.yaw;
	buf[i + 9] = (float)(e.qz - e.pz);
	buf[i + 11] = (float)e.pz;
	buf[i + 12] = (float)e.vat_phase;
	buf[i + 13] = e.walking ? 1.0f : 0.0f;
	buf[i + 14] = e.slow_timer > 0.0 ? 1.0f : 0.0f;
	vis_dirty[e.vis_model] = 1;
}

// EnemyManager._physics_process
PackedFloat32Array EnemySimNative::step(Object *p_motion, double p_delta, int64_t p_tick, const Vector3 &p_player_pos,
		const Vector3 &p_player_vel, double p_crowd_scale, double p_elapsed, int64_t p_now_ms,
		int64_t p_physics_frame, bool p_use_tokens, bool p_use_density) {
	events.resize(0);
	motion = p_motion != nullptr ? Object::cast_to<EnemyMotionNative>(p_motion) : nullptr;
	t_delta = p_delta;
	t_crowd = p_crowd_scale;
	t_elapsed = p_elapsed;
	t_now_ms = p_now_ms;
	pl_x = p_player_pos.x, pl_y = p_player_pos.y, pl_z = p_player_pos.z;
	pv_x = p_player_vel.x, pv_z = p_player_vel.z;
	use_tokens = p_use_tokens;
	use_density = p_use_density;
	if (use_density && (dframe < 0 || p_physics_frame - dframe >= DENS_REBUILD_TICKS || p_physics_frame < dframe)) {
		dframe = p_physics_frame;
		build_density();
	}
	const double tick_f = (double)p_tick;
	const int n = (int)ens.size();
	for (int i = 0; i < n; i++) {
		En &e = ens[i];
		e.tick_age += 1;
		if (e.tick_age >= e.tick_span) {
			double dt = p_delta * (double)e.tick_age;
			e.tick_age = 0;
			update(i, dt);
			En &u = ens[i];
			writeback(u);
			vis_write(u, tick_f);
		}
		if (full_writeback) {
			ens[i].obj->set(n_tick_age, ens[i].tick_age);
		}
	}
	return events;
}

PackedFloat32Array EnemySimNative::vis_buffer(int p_model) const {
	if (p_model < 0 || p_model >= (int)vis_bufs.size()) {
		return PackedFloat32Array();
	}
	return vis_bufs[p_model];
}

bool EnemySimNative::vis_take_dirty(int p_model) {
	if (p_model < 0 || p_model >= (int)vis_dirty.size() || !vis_dirty[p_model]) {
		return false;
	}
	vis_dirty[p_model] = 0;
	return true;
}

int EnemySimNative::vis_count(int p_model) const {
	if (p_model < 0 || p_model >= (int)vis_lists.size()) {
		return 0;
	}
	return (int)vis_lists[p_model].size();
}
