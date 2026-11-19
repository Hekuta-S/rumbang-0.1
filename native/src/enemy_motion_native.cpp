// Ver enemy_motion_native.h. Cada función replica la de scripts/core/enemy_motion.gd con el mismo nombre.
#include "enemy_motion_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr double CELL = 4.0;            // EnemyMotion.CELL
constexpr double ENEMY_RADIUS = 0.45;   // EnemyMotion.ENEMY_RADIUS
constexpr double PLAYER_RADIUS = 0.5;   // EnemyMotion.PLAYER_RADIUS
constexpr double CLIMB_MULT = 0.4;      // EnemyMotion.CLIMB_MULT
constexpr double BRIDGE_ENTER_TOL = 0.7; // EnemyMotion.BRIDGE_ENTER_TOL
constexpr int OBS_STRIDE = 7;           // EnemyMotion.OBS_STRIDE
constexpr int BSTRIDE = 14;             // EnemyMotion.BSTRIDE

struct V2 {
	double x, y;
};

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}
} // namespace

void EnemyMotionNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_heights", "heights", "side", "half", "cell", "climb_half"), &EnemyMotionNative::set_heights);
	ClassDB::bind_method(D_METHOD("set_obstacles", "obs", "cell_start", "cell_count", "ox0", "oz0", "ow", "oh"), &EnemyMotionNative::set_obstacles);
	ClassDB::bind_method(D_METHOD("set_bridges", "packed"), &EnemyMotionNative::set_bridges);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &EnemyMotionNative::height_at);
	ClassDB::bind_method(D_METHOD("move", "px", "pz", "vx", "vz", "delta", "ground_y", "bridge_i", "player_x", "player_z"),
			&EnemyMotionNative::move);
}

void EnemyMotionNative::set_heights(const PackedFloat32Array &p_hs, int p_side, double p_half, double p_cell, double p_climb_half) {
	hs = p_hs;
	hside = p_side;
	hhalf = p_half;
	hcell = p_cell;
	climb_half = p_climb_half;
}

void EnemyMotionNative::set_obstacles(const PackedFloat32Array &p_obs, const PackedInt32Array &p_start,
		const PackedInt32Array &p_count, int p_ox0, int p_oz0, int p_ow, int p_oh) {
	obs = p_obs;
	ocell_start = p_start;
	ocell_count = p_count;
	ox0 = p_ox0;
	oz0 = p_oz0;
	ow = p_ow;
	oh = p_oh;
}

void EnemyMotionNative::set_bridges(const PackedFloat32Array &p_bpk) {
	bpk = p_bpk;
}

double EnemyMotionNative::height_at(double x, double z) const {
	if (hside <= 1) {
		return 0.0;
	}
	const float *h = hs.ptr();
	const double lim = double(hside - 1) - 0.001;
	const double fx = clampd((x + hhalf) / hcell, 0.0, lim);
	const double fz = clampd((z + hhalf) / hcell, 0.0, lim);
	const int ix = int(fx);
	const int iz = int(fz);
	const double tx = fx - double(ix);
	const double tz = fz - double(iz);
	const int i0 = iz * hside + ix;
	const int i1 = i0 + hside;
	const double a = h[i0] + (h[i0 + 1] - h[i0]) * tx;
	const double b = h[i1] + (h[i1 + 1] - h[i1]) * tx;
	return a + (b - a) * tz;
}

Vector4 EnemyMotionNative::move(double px, double pz, double vx, double vz, double delta, double ground_y, int bridge_i,
		double player_x, double player_z) const {
	V2 np{ px, pz };
	double h_new = ground_y;
	const V2 step{ vx * delta, vz * delta };
	if (step.x * step.x + step.y * step.y <= 0.0000001) {
		return Vector4(np.x, np.y, h_new, bridge_i);
	}
	const float *bp = bpk.ptr();
	const int nb = bpk.size() / BSTRIDE;

	// ── step_layers ──
	if (bridge_i >= 0 && bridge_i < nb) {
		const float *b = bp + bridge_i * BSTRIDE;
		const V2 a{ b[0], b[1] };
		const V2 ab{ b[2], b[3] };
		const double blen = std::sqrt(ab.x * ab.x + ab.y * ab.y);
		const V2 d{ ab.x / blen, ab.y / blen };
		const V2 side{ -d.y, d.x };
		V2 target{ np.x + step.x, np.y + step.y };
		const V2 rel{ target.x - a.x, target.y - a.y };
		const double lim = b[7];
		const double lat = clampd(rel.x * side.x + rel.y * side.y, -lim, lim);
		const double along = rel.x * d.x + rel.y * d.y;
		target = V2{ a.x + d.x * along + side.x * lat, a.y + d.y * along + side.y * lat };
		const double t = along / blen;
		if (t < 0.0 || t > 1.0) {
			np = target;
			h_new = height_at(target.x, target.y);
			bridge_i = -1;
		} else {
			np = target;
			h_new = b[8] + (b[9] - b[8]) * t;
		}
	} else {
		// resolve_step
		const double slen = std::sqrt(step.x * step.x + step.y * step.y);
		const double max_rise = std::max(slen * 1.3, 0.03);
		V2 r{ np.x + step.x, np.y + step.y };
		double rh = height_at(r.x, r.y);
		if (rh - h_new > max_rise) {
			if (std::fabs(r.x) < climb_half && std::fabs(r.y) < climb_half) {
				r = V2{ np.x + step.x * CLIMB_MULT, np.y + step.y * CLIMB_MULT };
				rh = height_at(r.x, r.y);
			} else {
				const V2 tx{ np.x + step.x, np.y };
				const double h_x = height_at(tx.x, tx.y);
				if (h_x - h_new <= max_rise) {
					r = tx;
					rh = h_x;
				} else {
					const V2 tz{ np.x, np.y + step.y };
					const double h_z = height_at(tz.x, tz.y);
					if (h_z - h_new <= max_rise) {
						r = tz;
						rh = h_z;
					} else {
						r = np;
						rh = h_new;
					}
				}
			}
		}
		// ¿se sube a un puente?
		int on_bridge = -1;
		double deck_h = 0.0;
		for (int k = 0; k < nb; k++) {
			const float *b = bp + k * BSTRIDE;
			if (r.x < b[10] || r.x > b[11] || r.y < b[12] || r.y > b[13]) {
				continue;
			}
			const double rx = r.x - b[0];
			const double rz = r.y - b[1];
			const double t = (rx * b[2] + rz * b[3]) * b[4];
			if (t >= 0.0 && t <= 1.0 && std::fabs(rx * b[5] + rz * b[6]) <= b[7]) {
				const double deck = b[8] + (b[9] - b[8]) * t;
				if (std::fabs(deck - h_new) < BRIDGE_ENTER_TOL) {
					on_bridge = k;
					deck_h = deck;
					break;
				}
			}
		}
		np = r;
		if (on_bridge >= 0) {
			h_new = deck_h;
			bridge_i = on_bridge;
		} else {
			h_new = rh;
			bridge_i = -1;
		}
	}

	const V2 before = np;
	// ── _push_out_of_obstacles (no en la tabla de un puente) ──
	if (bridge_i < 0 && ow > 0) {
		const int gx = int(std::floor(np.x / CELL)) - ox0;
		const int gz = int(std::floor(np.y / CELL)) - oz0;
		if (gx >= 0 && gz >= 0 && gx < ow && gz < oh) {
			const int ci = gz * ow + gx;
			const int cnt = ocell_count[ci];
			if (cnt > 0) {
				const float *o = obs.ptr();
				int i = ocell_start[ci];
				const int n = i + cnt * OBS_STRIDE;
				while (i < n) {
					const double cx = o[i];
					const double cz = o[i + 1];
					const double dx = np.x - cx;
					const double dz = np.y - cz;
					const double reach = o[i + 2] + ENEMY_RADIUS;
					const double kind = o[i + 3];
					const double yaw = o[i + 4];
					const double hx = o[i + 5];
					const double hz = o[i + 6];
					i += OBS_STRIDE;
					if (dx * dx + dz * dz >= reach * reach) {
						continue;
					}
					if (kind == 0.0) {
						const double r = hx + ENEMY_RADIUS;
						const double dist = std::sqrt(dx * dx + dz * dz);
						if (dist < r) {
							if (dist > 0.0001) {
								np = V2{ cx + dx / dist * r, cz + dz / dist * r };
							} else {
								np = V2{ cx + r, cz };
							}
						}
					} else {
						// Caja orientada: marco local (rotado -yaw), punto más cercano, empuje hacia fuera
						const double cs = std::cos(-yaw), sn = std::sin(-yaw);
						V2 local{ dx * cs - dz * sn, dx * sn + dz * cs };
						const V2 closest{ clampd(local.x, -hx, hx), clampd(local.y, -hz, hz) };
						const V2 dl{ local.x - closest.x, local.y - closest.y };
						const double dist = std::sqrt(dl.x * dl.x + dl.y * dl.y);
						if (dist < ENEMY_RADIUS) {
							if (dist > 0.0001) {
								local = V2{ closest.x + dl.x / dist * ENEMY_RADIUS, closest.y + dl.y / dist * ENEMY_RADIUS };
							} else {
								const double gap_x = hx - std::fabs(local.x);
								const double gap_z = hz - std::fabs(local.y);
								if (gap_x < gap_z) {
									const double s = (local.x != 0.0 ? local.x : 1.0) < 0.0 ? -1.0 : 1.0;
									local.x = s * (hx + ENEMY_RADIUS);
								} else {
									const double s = (local.y != 0.0 ? local.y : 1.0) < 0.0 ? -1.0 : 1.0;
									local.y = s * (hz + ENEMY_RADIUS);
								}
							}
							const double c2 = std::cos(yaw), s2 = std::sin(yaw);
							np = V2{ cx + local.x * c2 - local.y * s2, cz + local.x * s2 + local.y * c2 };
						}
					}
				}
			}
		}
	}
	// ── _push_out_of_player ──
	{
		const double dx = np.x - player_x;
		const double dz = np.y - player_z;
		const double r = ENEMY_RADIUS + PLAYER_RADIUS;
		const double dist = std::sqrt(dx * dx + dz * dz);
		if (dist < r && dist > 0.0001) {
			np = V2{ player_x + dx / dist * r, player_z + dz / dist * r };
		}
	}
	if (np.x != before.x || np.y != before.y) {
		if (bridge_i < 0) {
			h_new = height_at(np.x, np.y);
		} else {
			// bridge_deck
			const float *b = bp + bridge_i * BSTRIDE;
			const double t = clampd(((np.x - b[0]) * b[2] + (np.y - b[1]) * b[3]) * b[4], 0.0, 1.0);
			h_new = b[8] + (b[9] - b[8]) * t;
		}
	}
	return Vector4(np.x, np.y, h_new, bridge_i);
}
