shader_type canvas_item;

// Contorno de tinta (cómic) alrededor de una imagen con alfa: la tira de armas del HUD y sus iconos. Se dibuja
// en la parte transparente que rodea la figura, así que la imagen necesita un poco de margen transparente
// (las del HUD lo tienen). Encima va la imagen tal cual: no cambia sus colores.

uniform vec4 ink_color : source_color = vec4(0.03, 0.022, 0.05, 1.0);
uniform float ink_px = 3.0;               // grosor en píxeles de la TEXTURA
uniform vec2 shadow_px = vec2(3.0, 4.0);   // sombra dura, en píxeles de la textura

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float ring = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5235988;
		ring = max(ring, texture(TEXTURE, UV + vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE * ink_px).a);
	}
	float shadow = texture(TEXTURE, UV - shadow_px * TEXTURE_PIXEL_SIZE).a * 0.8;
	vec4 ink = vec4(ink_color.rgb, smoothstep(0.25, 0.6, max(ring, shadow)) * ink_color.a);
	COLOR = mix(ink, t, t.a) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
