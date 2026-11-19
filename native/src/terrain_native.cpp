// Ver terrain_native.h. terrain() replica ProceduralMap._terrain() línea a línea.
#include "terrain_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {
constexpr double MESA_WALL = 0.6;    // ProceduralMap.MESA_WALL
constexpr double RAMP_HALF_W = 2.6;  // ProceduralMap.RAMP_HALF_W

struct V2 {
	double x, y;
	V2 operator-(const V2 &o) const { return V2{ x - o.x, y - o.y }; }
	V2 operator+(const V2 &o) const { return V2{ x + o.x, y + o.y }; }
	V2 operator*(double s) const { return V2{ x * s, y * s }; }
	double dot(const V2 &o) const { return x * o.x + y * o.y; }
	double cross(const V2 &o) const { return x * o.y - y * o.x; }
	double length() const { return std::sqrt(x * x + y * y); }
};

inline V2 v2(const Variant &v) {
	const Vector2 p = v;
	return V2{ p.x, p.y };
}

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

// Math::smoothstep de Godot (el de GDScript)
inline double smoothstep(double from, double to, double s) {
	if (std::fabs(from - to) < 0.00001 * std::max(1.0, std::fabs(from))) {
		return from <= to ? (s <= from ? 0.0 : 1.0) : (s <= to ? 1.0 : 0.0);
	}
	const double t = clampd((s - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;
}

struct Ramp {
	V2 dir;
	double len, half, foot_h;
	bool chute, has_foot;
};
struct Mesa {
	V2 c;
	double r, top, reach;
	std::vector<Ramp> ramps;
};
struct Bridge {
	V2 a, ab, abn;
	double len2, half;
};

struct Ctx {
	FastNoiseLite *hills;
	FastNoiseLite *detail;
	double hill_amplitude, basin_depth, basin_floor_radius, basin_rim_radius, play_half, cliff_height;
	V2 basin_center, ramp_end;
	double ramp_surface_y;
	std::vector<Mesa> mesas;
	std::vector<Bridge> bridges;

	double nd(double x, double z) const { return detail->get_noise_2d(x, z); }

	bool near_bridge(const V2 &p, double margin) const {
		for (const Bridge &br : bridges) {
			const V2 ap = p - br.a;
			const double t = ap.dot(br.ab) / br.len2;
			if (t > -0.05 && t < 1.05 && std::fabs(ap.cross(br.abn)) < br.half + margin) {
				return true;
			}
		}
		return false;
	}

	// ProceduralMap._terrain: (altura, máscara de cuenca, máscara de rampa, máscara de acantilado)
	void terrain(double x, double z, double &out_h, double &out_bt, double &out_ramp, double &out_ct) const {
		const V2 p{ x, z };
		const double r = p.length();
		double h = hills->get_noise_2d(x, z) * hill_amplitude + nd(x, z) * 0.7;
		h *= smoothstep(9.0, 24.0, r);

		const double d = (p - basin_center).length();
		const double bt = 1.0 - smoothstep(basin_floor_radius, basin_rim_radius, d);
		const double bowl = -basin_depth + nd(x * 2.0, z * 2.0) * 0.25;
		h = lerpd(h, bowl, bt);
		const double lip = (d - basin_rim_radius) / 4.0;
		h += 1.2 * std::exp(-lip * lip);

		const V2 ab = ramp_end - basin_center;
		const double ab_len = ab.length();
		const double t = clampd((p - basin_center).dot(ab) / (ab_len * ab_len), 0.0, 1.0);
		const V2 closest = basin_center + ab * t;
		const double l = (p - closest).length();
		const double w = 1.0 - smoothstep(3.5, 7.5, l);
		const double start = basin_floor_radius * 0.6;
		const double s = clampd((t * ab_len - start) / (ab_len - start), 0.0, 1.0);
		const double target = lerpd(-basin_depth, ramp_surface_y, s);
		h = lerpd(h, std::min(h, target), w);
		double ramp_mask = w * (1.0 - bt);

		double rws[16];
		for (const Mesa &m : mesas) {
			const double dm = (p - m.c).length();
			if (dm > m.r + m.reach) {
				continue;
			}
			const bool at_bridge = near_bridge(p, 1.5);
			const double top = m.top + (at_bridge ? 0.0 : nd(x * 1.5, z * 1.5) * 0.15);
			const V2 rel = p - m.c;
			double near_ramp = 0.0;
			const size_t nr = std::min<size_t>(m.ramps.size(), 16);
			for (size_t k = 0; k < nr; k++) {
				const Ramp &rp = m.ramps[k];
				const double u = rel.dot(rp.dir);
				const double lat = std::fabs(rel.cross(rp.dir));
				const double hw = rp.half;
				rws[k] = (1.0 - smoothstep(hw, hw + 1.0, lat)) * smoothstep(m.r - 4.0, m.r - 3.0, u);
				near_ramp = std::max(near_ramp, u > m.r - 4.0 ? 1.0 - smoothstep(hw + 1.0, hw + 3.0, lat) : 0.0);
			}
			if (at_bridge) {
				near_ramp = 1.0;
			}
			const double de = dm * (1.0 + 0.07 * nd(x * 0.7, z * 0.7) * (1.0 - near_ramp));
			const double inside = 1.0 - smoothstep(m.r - MESA_WALL, m.r + MESA_WALL, de);
			h = std::max(h, lerpd(h, top, inside));
			for (size_t k = 0; k < nr; k++) {
				const double rw = rws[k];
				if (rw <= 0.0) {
					continue;
				}
				const Ramp &rp = m.ramps[k];
				const double u = rel.dot(rp.dir);
				const double rs = clampd((u - (m.r - MESA_WALL)) / (rp.len + MESA_WALL), 0.0, 1.0);
				if (rp.chute) {
					const double foot_h = rp.has_foot ? rp.foot_h : h;
					h = rs < 1.0 ? lerpd(h, lerpd(top, foot_h, rs), rw) : h;
				} else {
					h = std::max(h, lerpd(h, lerpd(top, h, rs), rw));
				}
				ramp_mask = std::max(ramp_mask, rw * (1.0 - rs * 0.3));
			}
		}

		const double e = std::max(std::fabs(x), std::fabs(z));
		const double ct = smoothstep(play_half, play_half + 7.0, e);
		h += ct * (cliff_height + nd(x * 3.0, z * 3.0) * 3.0);

		out_h = h;
		out_bt = bt;
		out_ramp = ramp_mask;
		out_ct = ct;
	}
};
} // namespace

void TerrainNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "params", "hills", "detail", "mesas", "bridges"), &TerrainNative::build);
}

Array TerrainNative::build(const Dictionary &params, const Ref<FastNoiseLite> &hills, const Ref<FastNoiseLite> &detail,
		const Array &mesas, const Array &bridges) const {
	Ctx cx;
	cx.hills = hills.ptr();
	cx.detail = detail.ptr();
	const double half_size = params["half_size"];
	const double cell_size = params["cell_size"];
	cx.hill_amplitude = params["hill_amplitude"];
	cx.basin_depth = params["basin_depth"];
	cx.basin_floor_radius = params["basin_floor_radius"];
	cx.basin_rim_radius = params["basin_rim_radius"];
	cx.play_half = params["play_half"];
	cx.cliff_height = params["cliff_height"];
	cx.basin_center = v2(params["basin_center"]);
	cx.ramp_end = v2(params["ramp_end"]);
	cx.ramp_surface_y = params["ramp_surface_y"];
	for (int i = 0; i < mesas.size(); i++) {
		const Dictionary m = mesas[i];
		Mesa ms;
		ms.c = v2(m["c"]);
		ms.r = m["r"];
		ms.top = m["top"];
		ms.reach = m["reach"];
		const Array ramps = m["ramps"];
		for (int k = 0; k < ramps.size(); k++) {
			const Dictionary rp = ramps[k];
			Ramp r;
			r.dir = v2(rp["dir"]);
			r.len = rp["len"];
			r.half = rp.has("half") ? double(rp["half"]) : RAMP_HALF_W;
			r.chute = rp.has("chute") ? bool(rp["chute"]) : false;
			r.has_foot = rp.has("foot_h");
			r.foot_h = r.has_foot ? double(rp["foot_h"]) : 0.0;
			ms.ramps.push_back(r);
		}
		cx.mesas.push_back(ms);
	}
	for (int i = 0; i < bridges.size(); i++) {
		const Dictionary br = bridges[i];
		Bridge b;
		b.a = v2(br["a"]);
		b.ab = v2(br["b"]) - b.a;
		b.len2 = b.ab.dot(b.ab);
		const double l = std::sqrt(b.len2);
		b.abn = l > 0.0 ? b.ab * (1.0 / l) : V2{ 0.0, 0.0 };
		b.half = br["half"];
		cx.bridges.push_back(b);
	}

	const int side = int(std::round(half_size * 2.0 / cell_size)) + 1;
	const int n = side * side;
	PackedFloat32Array heights;
	heights.resize(n);
	PackedVector3Array verts;
	verts.resize(n);
	PackedColorArray colors;
	colors.resize(n);
	PackedVector2Array uvs;
	uvs.resize(n);
	float *hp = heights.ptrw();
	Vector3 *vp = verts.ptrw();
	Color *cp = colors.ptrw();
	Vector2 *up = uvs.ptrw();
	for (int j = 0; j < side; j++) {
		for (int i = 0; i < side; i++) {
			const double x = -half_size + double(i) * cell_size;
			const double z = -half_size + double(j) * cell_size;
			double h, bt, rm, ct;
			cx.terrain(x, z, h, bt, rm, ct);
			const int idx = j * side + i;
			hp[idx] = float(h);
			vp[idx] = Vector3(x, hp[idx], z);
			const double plaza = 1.0 - smoothstep(6.0, 16.0, std::sqrt(x * x + z * z));
			cp[idx] = Color(bt, rm, plaza, ct);
			up[idx] = Vector2(cx.nd(x * 1.6 + 300.0, z * 1.6 - 120.0) * 0.5 + 0.5, 0.0);
		}
	}

	PackedVector3Array normals;
	normals.resize(n);
	Vector3 *np = normals.ptrw();
	for (int j = 0; j < side; j++) {
		for (int i = 0; i < side; i++) {
			const float hl = hp[j * side + std::max(i - 1, 0)];
			const float hr = hp[j * side + std::min(i + 1, side - 1)];
			const float hd = hp[std::max(j - 1, 0) * side + i];
			const float hu = hp[std::min(j + 1, side - 1) * side + i];
			np[j * side + i] = Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized();
		}
	}

	PackedInt32Array indices;
	indices.resize((side - 1) * (side - 1) * 6);
	int32_t *ip = indices.ptrw();
	int k = 0;
	for (int j = 0; j < side - 1; j++) {
		for (int i = 0; i < side - 1; i++) {
			const int a = j * side + i;
			const int b = a + 1;
			const int c = a + side;
			const int d = c + 1;
			ip[k] = a;
			ip[k + 1] = b;
			ip[k + 2] = c;
			ip[k + 3] = b;
			ip[k + 4] = d;
			ip[k + 5] = c;
			k += 6;
		}
	}

	Array out;
	out.push_back(side);
	out.push_back(heights);
	out.push_back(verts);
	out.push_back(colors);
	out.push_back(uvs);
	out.push_back(normals);
	out.push_back(indices);
	return out;
}
