shader_type canvas_item;

// Minimapa dibujado (cómic) en vez de pixel art. La textura del mapa tiene 1 píxel por celda (color de
// sala/túnel y alfa 1 en lo explorado); se lee con filtro lineal y se corta el alfa en 0.5: los bordes quedan
// como un contorno suave (esquinas redondeadas, diagonales lisas) en lugar de escalones. Encima:
//  - pulso de dibujo a mano (el borde ondula un poco);
//  - contorno de tinta de `ink_px` píxeles de pantalla alrededor de lo explorado;
//  - sombra dura desplazada;
//  - filete claro por dentro del borde (luz de cómic).
// Las marcas (jugadores, cofres, portal) se dibujan aparte, encima (ver Minimap._draw_view).

uniform vec4 ink_color : source_color = vec4(0.03, 0.022, 0.05, 1.0);
uniform vec2 uv_per_px = vec2(0.01);     // tamaño de un píxel de pantalla en UV (lo pone Minimap cada dibujo)
uniform float ink_px = 2.5;
uniform vec2 shadow_px = vec2(2.0, 3.0);
uniform float wobble_px = 0.9;

// (TEXTURE se lee siempre aquí dentro: pasarlo a una función hace que Godot pierda su filtro y avise)
void fragment() {
	// pulso: desplazamiento suave y continuo, del orden de un píxel de pantalla
	vec2 w = vec2(sin(UV.y * 71.0 + UV.x * 17.0), cos(UV.x * 67.0 - UV.y * 13.0)) * uv_per_px * wobble_px;
	vec2 uv = UV + w;
	vec4 t = texture(TEXTURE, uv);
	float body = smoothstep(0.42, 0.58, t.a);
	// contorno: lo explorado engordado en 8 direcciones
	float ring = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982;
		ring = max(ring, smoothstep(0.42, 0.58, texture(TEXTURE, uv + vec2(cos(a), sin(a)) * uv_per_px * ink_px).a));
	}
	float shadow = smoothstep(0.42, 0.58, texture(TEXTURE, uv - shadow_px * uv_per_px).a);
	// el filtro lineal mezcla el color con el negro transparente de lo no explorado: se deshace dividiendo
	vec3 col = t.rgb / max(t.a, 0.001);
	// filete claro: dentro, cerca del borde de arriba a la izquierda
	float inner = smoothstep(0.42, 0.58, texture(TEXTURE, uv - vec2(1.6, 1.6) * uv_per_px * ink_px).a);
	col = mix(min(col * 1.12 + 0.05, vec3(1.0)), col, inner);
	vec4 outc = vec4(ink_color.rgb, max(ring, shadow * 0.85) * ink_color.a);
	COLOR = mix(outc, vec4(col, 1.0), body);
}
