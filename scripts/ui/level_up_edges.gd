class_name LevelUpEdges
extends ColorRect

## Subida de nivel: triángulos dorados que entran desde los bordes de la pantalla (como las líneas de velocidad
## al esprintar en la mazmorra, pero más gruesos y épicos). Va justo debajo del menú de cartas, enmarcándolas.
## Un solo ColorRect con shader: sin nodos por pieza. Corre con el juego en pausa.

const LIFE := 1.5
const LAYER := 99                     ## justo bajo UpgradeChoiceUI (100)

const SHADER_CODE := """
shader_type canvas_item;
uniform float grow = 0.0;     // 0..1 entrada de los triángulos
uniform float fade = 1.0;
float h(float x) { return fract(sin(x * 91.17) * 43758.5453); }
void fragment() {
	vec2 c = UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float a = atan(c.y, c.x) / 6.28318 + 0.5;
	float slots = 30.0;
	float id = floor(a * slots);
	float tri = 1.0 - abs(fract(a * slots) - 0.5) * 2.0;      // 1 en el centro del triángulo, 0 en sus bordes
	float len = 0.10 + 0.22 * h(id * 1.7);
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0 + id);
	vec2 q = abs(UV - 0.5) * 2.0;
	float d = max(q.x, q.y);                                   // 0 centro, 1 borde de la pantalla
	float reach = 1.0 - len * pulse * grow * tri;              // la punta apunta al centro
	float inside = step(reach, d);
	float rim = step(reach + 0.012, d);                        // borde de tinta fino
	vec3 col = mix(vec3(0.06, 0.03, 0.05), mix(vec3(1.0, 0.8, 0.22), vec3(1.0, 0.95, 0.6), tri), rim);
	COLOR = vec4(col, inside * 0.9 * fade);
}
"""

var _t := 0.0

static func play(parent: Node) -> LevelUpEdges:
	var e := LevelUpEdges.new()
	e.name = "LevelUpEdges"
	e.process_mode = Node.PROCESS_MODE_ALWAYS
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	e.material = m
	var layer := CanvasLayer.new()
	layer.name = "LevelUpEdgesLayer"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(e)
	parent.get_tree().root.add_child.call_deferred(layer)
	return e

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply()

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		get_parent().queue_free()
		return
	_apply()

func _apply() -> void:
	var grow := 1.0 - pow(1.0 - clampf(_t / 0.3, 0.0, 1.0), 3.0)      # entra rápido
	var fade := clampf((LIFE - _t) / 0.5, 0.0, 1.0)
	var m := material as ShaderMaterial
	m.set_shader_parameter("grow", grow)
	m.set_shader_parameter("fade", fade)
