shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Rocas y adornos de las Cavernas como dibujos cartoon horneados (tools/bake_cave_sprites.gd +
// tools/make_cave_sprites.py → assets/textures/toon/props/cave_rocks.png y cave_decor.png). MultiMesh de quads
// 1x1 por trozo: el quad gira solo alrededor del eje vertical para mirar a la cámara y la celda del atlas se
// elige por el ángulo entre la cámara y el giro de la pieza (8 vistas): al rodearla, "gira" como un modelo.
// INSTANCE_CUSTOM: x = pieza (fila del atlas), y = giro de la pieza (rad), z = luz de antorchas horneada (0..1).
// Las transformadas de la MultiMesh solo llevan posición y escala uniforme.
// Hongos (kind_fx.y/z): balanceo leve, manchas que brillan y respiran (glow_tex), y la misma reacción al jugador
// y a la onda de los golpes que mushroom_glow.gdshader.
// Objetivo: renderer Mobile (Android, Mali-G57) y PC. Coste: 2 lecturas de textura (dibujo + máscara de brillo),
// recorte alfa, sin mezcla. Un solo shader para las dos hojas (sin variantes).

group_uniforms atlas;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 12.0);          // columnas = ángulos, filas = piezas
// Por pieza: x = lado del dibujo (m), y/z = píxel del origen de la pieza en la celda (0..1), w = inclinación
// de la normal hacia arriba (+) o abajo (-, estalactitas: las antorchas quedan por debajo)
uniform vec4 kinds[16];
// Por pieza: x = 1 se tiñe con el color de roca del nivel, y = balanceo (m a 1 m de altura), z = brillo
uniform vec4 kind_fx[16];
group_uniforms color;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_gain = 1.75;               // el dibujo de roca ronda 0,57: lleva el tinte al de las paredes
// Luz de antorchas horneada (solo móvil, como la carcasa): se suma como emisión
uniform float baked_gain = 0.0;
uniform vec3 baked_tint = vec3(1.0, 0.58, 0.26);
group_uniforms brillo;
uniform vec3 glow_color : source_color = vec3(0.45, 1.0, 0.75);
uniform float glow_energy = 1.6;
uniform float pulse_speed = 1.1;
uniform float sway_speed = 0.8;
uniform float near_radius = 4.5;
uniform float near_boost = 1.6;
global uniform vec3 world_actor_pos;
global uniform vec4 world_pulse;              // xy = centro (x, z); z = radio (m); w = fuerza

const float PULSE_WIDTH = 0.8;                // m de ancho del anillo de la onda de un golpe
const float PULSE_BEND = 0.22;                // cuánto se dobla un hongo con la onda (por m² de altura)

varying vec2 v_cell;
varying float v_baked;
varying float v_tint;
varying float v_glow;
varying float v_phase;
varying float v_near;

void vertex() {
	int k = int(INSTANCE_CUSTOM.x + 0.5);
	vec4 kd = kinds[k];
	vec4 fx = kind_fx[k];
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	float phi = atan(to_cam.x, to_cam.z);
	float step_a = TAU / grid.x;
	float a = mod(round((INSTANCE_CUSTOM.y - phi) / step_a), grid.x);
	v_cell = vec2(a, float(k));
	v_baked = INSTANCE_CUSTOM.z;
	v_tint = fx.x;
	v_glow = fx.z;
	vec3 right = vec3(to_cam.z, 0.0, -to_cam.x);
	// quad 1x1: UV = (x + 0.5, 0.5 - y); el origen de la pieza cae en (u0, v0)
	vec2 v = (VERTEX.xy - vec2(kd.y - 0.5, 0.5 - kd.z)) * kd.x;
	vec3 pos = right * v.x + vec3(0.0, v.y, 0.0);
	// Balanceo: crece con el cuadrado de la altura (el pie no se mueve), fase por posición
	v_phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * TAU;
	float h = max(v.y, 0.0);
	float t = TIME * sway_speed + v_phase;
	pos.xz += vec2(sin(t), sin(t * 0.77 + 1.3) * 0.7) * h * h * fx.y;
	// Cerca del jugador brilla más; la onda de un golpe lo dobla hacia fuera
	v_near = (1.0 - smoothstep(1.0, near_radius, distance(origin.xz, world_actor_pos.xz)))
		* step(abs(origin.y - world_actor_pos.y), 3.0);
	vec2 from_hit = origin.xz - world_pulse.xy;
	float dh = max(length(from_hit), 0.001);
	float ring = exp(-pow((dh - world_pulse.z) / PULSE_WIDTH, 2.0)) * world_pulse.w * step(0.0001, fx.y);
	pos.xz += from_hit / dh * ring * PULSE_BEND * h * h;
	v_near = max(v_near, ring);
	// (como en mushroom_glow, el balanceo va en espacio del modelo: escala con la pieza)
	VERTEX = pos;
	NORMAL = normalize(to_cam + vec3(0.0, kd.w, 0.0));
}

void fragment() {
	vec2 uv = (v_cell + UV) / grid;
	vec4 c = texture(sheet, uv);
	ALBEDO = c.rgb * mix(vec3(1.0), tint * tint_gain, v_tint);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;      // recorte duro: el contorno de tinta ya viene dibujado
	ROUGHNESS = 1.0;
	float g = texture(glow_tex, uv).r * v_glow;
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed * (1.0 + 2.0 * v_near) + v_phase);
	EMISSION = ALBEDO * baked_tint * (v_baked * baked_gain)   // baked_gain = 0 en PC
		+ glow_color * g * glow_energy * pulse * (1.0 + near_boost * v_near);
}
