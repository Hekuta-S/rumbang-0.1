shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;   // = prop_toon.gdshader

// Árbol dibujado (tools/make_map_sprites.py, assets/textures/toon/props/arboles.png) en una MultiMesh de quads:
// gira solo alrededor del eje vertical para mirar a la cámara (billboard cilíndrico) y sigue de pie.
// INSTANCE_CUSTOM: x = columna (variante), y = fila (0 entero, 1 tocón, 2 parte de arriba),
//                  z = espejo (±1, se aplica a la UV), w = inclinación en rad alrededor de `pivot_y` (temblor al golpearlo / caída).
// Las transformadas de la MultiMesh solo llevan posición y escala uniforme (sin giro).
// Objetivo: renderer Mobile (Android, Mali-G57) y Forward+ (PC). Coste: 1 lectura de textura y recorte alfa (sin
// mezcla), una llamada de dibujo por trozo del mapa. Sin variantes.

group_uniforms hoja;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(4.0, 3.0);
group_uniforms animacion;
uniform float pivot_y = 0.0;          // m (sin escalar) sobre la base donde gira la inclinación
uniform vec3 tint : source_color = vec3(0.85);   // el dibujo ya trae su sombreado: algo más oscuro que el suelo
uniform float fade = 1.0;             // < 1: se encoge desde el pivote (la parte que cae desaparece)

// La normal mira sobre todo hacia arriba (como el suelo de alrededor): todos los árboles reciben la misma luz,
// los mire la cámara desde donde los mire.
const float NORMAL_LIFT = 2.5;

varying vec2 v_cell;
varying float v_flip;

void vertex() {
	v_cell = INSTANCE_CUSTOM.xy;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = vec3(to_cam.z, 0.0, -to_cam.x);
	v_flip = INSTANCE_CUSTOM.z;
	vec2 v = VERTEX.xy;
	v.y -= pivot_y;
	float a = INSTANCE_CUSTOM.w;
	v = vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)) * fade;
	v.y += pivot_y;
	VERTEX = right * v.x + vec3(0.0, v.y, 0.0);
	NORMAL = normalize(to_cam + vec3(0.0, NORMAL_LIFT, 0.0));
}

void fragment() {
	// Espejo por la UV (dar la vuelta a la geometría dejaría ver la cara de atrás, con la normal invertida)
	vec2 uv = (v_cell + vec2(mix(1.0 - UV.x, UV.x, step(0.0, v_flip)), UV.y)) / grid;
	vec4 c = texture(sheet, uv);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;      // recorte duro: el borde de tinta ya está dibujado en la textura
	ROUGHNESS = 1.0;
}
