shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

// Marcas que deja la partida en el suelo de Supervivencia (MapMarks): cráteres de explosión y manchas de tinta,
// dibujados vistos desde arriba en assets/textures/toon/fx/marcas.png (tools/make_map_sprites.py, 4 celdas en fila).
// Un quad horizontal por marca en una sola MultiMesh. INSTANCE_CUSTOM: x = celda (0..3), w = opacidad.
// Objetivo: renderer Mobile y Forward+. Coste: 1 lectura de textura con mezcla alfa; sin variantes.

group_uniforms hoja;
uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform float cells = 4.0;

varying float v_cell;
varying float v_alpha;

void vertex() {
	v_cell = INSTANCE_CUSTOM.x;
	v_alpha = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec4 c = texture(sheet, vec2((v_cell + UV.x) / cells, UV.y));
	ALBEDO = c.rgb;
	ALPHA = c.a * v_alpha;
	ROUGHNESS = 1.0;
}
