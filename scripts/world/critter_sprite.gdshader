shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Fauna ambiental (AmbientCritters): un MultiMesh de quads que miran a la cámara, con el dibujo sacado de un atlas.
// Datos por instancia (INSTANCE_CUSTOM):
//   x, y = los dos fotogramas del atlas entre los que alterna (iguales = quieto)
//   z    = alternancias por segundo (aleteo, zancada)
//   w    = banderas: +1 voltear en horizontal, +2 brilla (luciérnagas, bichos de los hongos)
// El color de la instancia tiñe el dibujo y su alfa lo desvanece.

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float grid = 4.0;             // celdas por lado del atlas
uniform float glow_energy = 3.5;

varying float v_glow;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float beat = fract(TIME * c.z + float(INSTANCE_ID) * 0.37);
	float frame = floor((c.z > 0.0 && beat > 0.5 ? c.y : c.x) + 0.5);
	vec2 uv = UV;
	if (mod(c.w, 2.0) > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	UV = (vec2(mod(frame, grid), floor(frame / grid)) + uv) / grid;
	v_glow = step(1.5, c.w);
	// Mira a la cámara conservando el tamaño de la instancia
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1],
		MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb * mix(1.0, glow_energy, v_glow);
	ALPHA = t.a * COLOR.a;
}
