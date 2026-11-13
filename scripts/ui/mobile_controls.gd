extends CanvasLayer

## Controles táctiles: joystick flotante (mover) + botones de acción.
## - El joystick aparece donde se toca la mitad izquierda de la pantalla (si no se toca, descansa en
##   su sitio habitual).
## - Botones abajo a la derecha: ATAQUE (grande, mantener = ataque continuo) rodeado de dos arcos:
##   SALTO, RODAR, ESPECIAL y FIJAR objetivo (arco interior); HABILIDAD, PARAR, RECARGAR y ARMA (arco exterior).
## - FIJAR: tocar fija/suelta; mantener y deslizar hacia un lado cambia al enemigo de ese lado.
## - Cualquier otro dedo que arrastre mueve la cámara.
## - Respeta el área segura (muescas / barras del sistema) y se recoloca al cambiar el tamaño.
## - Suelta todo al pausar, al perder el foco o al ocultarse (nada se queda "pegado").

const DEAD_ZONE := 0.12
const EDGE_MARGIN := 28.0
const IDLE_ALPHA := 0.5
const ACTIVE_ALPHA := 0.95
const JOY_ZONE_WIDTH := 0.5        ## fracción izquierda de la pantalla donde nace el joystick
const JOY_ZONE_TOP := 0.2          ## no nace en el 20 % superior (HUD)
## FIJAR: arrastre necesario (px, o radios del botón si es mayor) para cambiar de objetivo.
const TARGET_SWIPE_MIN := 34.0
const TARGET_SWIPE_RADII := 0.7

## Botones de acción. mode: "hold" = activo mientras el dedo esté puesto; "tap" = un solo pulso.
## ring 0 = botón grande; 1 y 2 = arcos interior y exterior; angle en grados (270 = arriba, 180 = izquierda).
## Cada botón se dibuja con un icono vectorial (ver _draw_icon), sin texto.
const BUTTONS := [
	{"key": "attack", "name": "Ataque", "mode": "hold", "color": Color(1.0, 0.35, 0.3), "ring": 0, "angle": 0.0},
	{"key": "jump", "name": "Salto", "mode": "hold", "color": Color(0.25, 0.85, 0.45), "ring": 1, "angle": 176.0},
	{"key": "dodge", "name": "Rodar", "mode": "tap", "color": Color(0.35, 0.7, 1.0), "ring": 1, "angle": 214.0},
	{"key": "alt", "name": "Ataque especial", "mode": "hold", "color": Color(1.0, 0.6, 0.2), "ring": 1, "angle": 252.0},
	{"key": "target", "name": "Fijar objetivo", "mode": "tap", "color": Color(1.0, 0.3, 0.45), "ring": 1, "angle": 290.0},
	{"key": "skill", "name": "Habilidad", "mode": "tap", "color": Color(0.8, 0.45, 1.0), "ring": 2, "angle": 185.0},
	{"key": "parry", "name": "Parar", "mode": "tap", "color": Color(1.0, 0.9, 0.3), "ring": 2, "angle": 215.0},
	{"key": "reload", "name": "Recargar", "mode": "tap", "color": Color(0.6, 0.9, 0.9), "ring": 2, "angle": 245.0},
	{"key": "weapon", "name": "Cambiar arma", "mode": "tap", "color": Color(0.85, 0.85, 0.9), "ring": 2, "angle": 275.0},
	# Solo en el salón (menú)
	{"key": "run", "name": "Correr", "mode": "hold", "color": Color(0.35, 0.7, 1.0), "ring": 1, "angle": 215.0},
	{"key": "interact", "name": "Interactuar", "mode": "tap", "color": Color(1.0, 0.85, 0.3), "ring": 0, "angle": 0.0},
]

## Botones permitidos por modo (el primero ocupa el botón grande, el segundo el arco interior).
## "survival": solo caminar (joystick) y saltar. "hub" (salón): caminar, correr e interactuar.
## Cualquier otro modo (mazmorra) muestra todos los botones de combate.
const MODE_KEYS := {
	"survival": ["jump"],
	"hub": ["interact", "run"],
}
const HUB_ONLY := ["run", "interact"]

## "survival", "hub" o "dungeon". Si no se asigna antes de añadir el nodo, se toma de GameData.game_mode.
var mode := ""

## Editor de disposición: el joystick también se puede mover/escalar.
const JOY_KEY := "joystick"
const EDIT_SCALE_MIN := 0.5
const EDIT_SCALE_MAX := 2.0

var _overlay: Control
var _touch_available := false

var _joy_radius := 80.0
var _joy_rest := Vector2.ZERO          ## centro de reposo del joystick
var _joy_center := Vector2.ZERO        ## centro actual (flotante mientras se usa)
var _joy_offset := Vector2.ZERO        ## desplazamiento del pulgar, limitado al radio
var _joy_id := -1

var _btn_center: Array[Vector2] = []   ## centro de cada botón (mismo orden que BUTTONS)
var _btn_radius: Array[float] = []
var _btn_id: Array[int] = []           ## dedo que lo pulsa (-1 = libre)

var _look_id := -1
var _alpha := IDLE_ALPHA

# Botón FIJAR: tocar fija/suelta; mantener y deslizar cambia de objetivo hacia esa dirección.
var _tgt_origin := Vector2.ZERO        ## punto desde el que se mide el arrastre (se reinicia en cada cambio)
var _tgt_drag := Vector2.ZERO          ## desplazamiento actual del dedo (para dibujar la guía)
var _tgt_was_locked := false           ## había objetivo al pulsar: soltar sin arrastrar lo suelta
var _tgt_switched := false             ## se cambió de objetivo durante esta pulsación

# Editor de disposición
var _editing := false
var _edit_sel := ""                    ## clave seleccionada ("" = ninguna, JOY_KEY = joystick)
var _edit_drag_id := -1
var _edit_grab := Vector2.ZERO         ## desfase dedo → centro al empezar a arrastrar
var _edit_layer: CanvasLayer
var _edit_panel: PanelContainer
var _edit_title: Label
var _edit_slider: HSlider
var _edit_val: Label
var _edit_visible: CheckButton

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mobile_controls")
	if mode == "":
		mode = GameData.game_mode
	SettingsManager.touch_edit_requested.connect(begin_edit)
	_touch_available = DisplayServer.is_touchscreen_available()
	VirtualInput.touch_ui_active = true
	for i in BUTTONS.size():
		_btn_center.append(Vector2.ZERO)
		_btn_radius.append(40.0)
		_btn_id.append(-1)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # textura de piedra del joystick (StoneUI)
	_overlay.draw.connect(_draw_controls)
	add_child(_overlay)

	get_viewport().size_changed.connect(_layout)
	SettingsManager.touch_layout_changed.connect(_on_settings_changed)
	visibility_changed.connect(func(): if not visible: _release_all())
	_layout()

## Tamaño, opacidad o visibilidad cambiados desde el menú de ajustes.
func _on_settings_changed() -> void:
	_release_all()
	_layout()

func _is_hidden(i: int) -> bool:
	return SettingsManager.touch_hidden.has(String(BUTTONS[i]["key"]))

## RECARGAR solo tiene sentido con un arma de balas: sin ninguna no se dibuja ni recibe toques
## (en el editor de disposición sigue visible para poder colocarlo).
var _has_ammo_weapon := false
func _is_unavailable(i: int) -> bool:
	var key := String(BUTTONS[i]["key"])
	if not _in_mode(key):
		return true
	return key == "reload" and not _has_ammo_weapon and not _editing

## ¿El botón existe en el modo actual?
func _in_mode(key: String) -> bool:
	if MODE_KEYS.has(mode):
		return (MODE_KEYS[mode] as Array).has(key)
	return not HUB_ONLY.has(key)

func _refresh_ammo_weapon() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var inv: PlayerWeaponInventory = player.get("weapon_inventory") if player else null
	var has := inv != null and inv.has_ammo_weapon()
	if has != _has_ammo_weapon:
		_has_ammo_weapon = has
		_overlay.queue_redraw()

func _exit_tree() -> void:
	if _editing:
		end_edit()
	VirtualInput.touch_ui_active = false
	_release_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

# ───────────────────────────── Disposición ─────────────────────────────

func _layout() -> void:
	if _btn_center.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var shortest := minf(vp.x, vp.y)
	var k := SettingsManager.touch_scale
	_joy_radius = clampf(shortest * 0.13, 56.0, 105.0) * k
	var big_r := clampf(shortest * 0.115, 48.0, 92.0) * k
	var small_r := clampf(shortest * 0.058, 28.0, 48.0) * k

	# Área segura: márgenes extra en los bordes (muescas, barra de gestos...)
	var safe_l := 0.0
	var safe_r := 0.0
	var safe_b := 0.0
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x > 0 and win.y > 0 and safe.size.x > 0:
		var sx := vp.x / float(win.x)
		var sy := vp.y / float(win.y)
		safe_l = maxf(0.0, float(safe.position.x) * sx)
		safe_r = maxf(0.0, float(win.x - safe.end.x) * sx)
		safe_b = maxf(0.0, float(win.y - safe.end.y) * sy)

	_joy_rest = Vector2(safe_l + EDGE_MARGIN + _joy_radius, vp.y - safe_b - EDGE_MARGIN - _joy_radius)
	var jc := _custom(JOY_KEY)
	if not jc.is_empty():
		_joy_radius *= _custom_scale(jc)
		var jm := _joy_radius + 4.0
		_joy_rest = Vector2(clampf(float(jc["x"]) * vp.x, jm, vp.x - jm), clampf(float(jc["y"]) * vp.y, jm, vp.y - jm))
	if _joy_id == -1:
		_joy_center = _joy_rest
		_joy_offset = Vector2.ZERO

	var origin := Vector2(vp.x - safe_r - EDGE_MARGIN - big_r, vp.y - safe_b - EDGE_MARGIN - big_r)
	var ring1 := big_r + small_r + 10.0
	var ring2 := ring1 + small_r * 2.0 + 8.0
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var ring := int(b["ring"])
		var angle := float(b["angle"])
		if MODE_KEYS.has(mode):
			# Modos con pocos botones: el principal ocupa el sitio del ataque, el segundo el arco interior
			var rank: int = (MODE_KEYS[mode] as Array).find(String(b["key"]))
			if rank == 0:
				ring = 0
			elif rank > 0:
				ring = 1
				angle = 215.0
		match ring:
			0:
				_btn_center[i] = origin
				_btn_radius[i] = big_r
			1:
				_btn_center[i] = origin + Vector2.from_angle(deg_to_rad(angle)) * ring1
				_btn_radius[i] = small_r
			_:
				_btn_center[i] = origin + Vector2.from_angle(deg_to_rad(angle)) * ring2
				_btn_radius[i] = small_r
		# Disposición personalizada (posición y tamaño elegidos por el jugador)
		var bc := _custom(String(b["key"]))
		if not bc.is_empty():
			_btn_radius[i] *= _custom_scale(bc)
			_btn_center[i] = Vector2(float(bc["x"]) * vp.x, float(bc["y"]) * vp.y)
		# Que ningún botón se salga de la pantalla
		_btn_center[i].x = clampf(_btn_center[i].x, _btn_radius[i] + 4.0, vp.x - _btn_radius[i] - 4.0)
		_btn_center[i].y = clampf(_btn_center[i].y, _btn_radius[i] + 4.0, vp.y - _btn_radius[i] - 4.0)
	_overlay.queue_redraw()

func _custom(key: String) -> Dictionary:
	var c: Variant = SettingsManager.touch_custom.get(key)
	if c is Dictionary and c.has("x") and c.has("y"):
		return c
	return {}

func _custom_scale(c: Dictionary) -> float:
	return clampf(float(c.get("s", 1.0)), EDIT_SCALE_MIN, EDIT_SCALE_MAX)

# ───────────────────────────── Dibujo ─────────────────────────────

func _any_button_down() -> bool:
	for id in _btn_id:
		if id != -1:
			return true
	return false

func _process(delta: float) -> void:
	# Pausa: soltar todo para que el personaje no siga corriendo al volver
	if get_tree().paused and (_joy_id != -1 or _any_button_down() or _look_id != -1):
		_release_all()
	_refresh_ammo_weapon()
	var target := ACTIVE_ALPHA if (_joy_id != -1 or _any_button_down()) else IDLE_ALPHA
	var new_alpha := lerpf(_alpha, target, minf(1.0, delta * 12.0))
	if absf(new_alpha - _alpha) > 0.003:
		_alpha = new_alpha
		_overlay.queue_redraw()

func _draw_controls() -> void:
	var a := _alpha * SettingsManager.touch_opacity
	if _editing:
		a = 1.0
		_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(0.02, 0.02, 0.06, 0.82))
	_draw_joystick(a)

	# Botones de acción: huecos de hierro como los del inventario (pozo oscuro, resplandor del color
	# del botón, anillo de metal con muescas e icono); se aprietan al pulsarlos.
	for i in BUTTONS.size():
		var hidden := _is_hidden(i)
		if (hidden and not _editing) or _is_unavailable(i):
			continue
		var b: Dictionary = BUTTONS[i]
		var pressed := _btn_id[i] != -1
		var c: Vector2 = _btn_center[i]
		var r: float = _btn_radius[i] * (0.93 if pressed else 1.0)
		var ba := a * (0.35 if hidden else 1.0)   # en el editor, los ocultos salen apagados
		_draw_socket(c, r, b["color"], ba, pressed, int(b["ring"]) == 0)
		var icon_col: Color = Color.WHITE if pressed else (b["color"] as Color).lightened(0.55)
		var ic := c
		if pressed and b["key"] == "target" and _tgt_drag != Vector2.ZERO:
			ic += _tgt_drag   # la mira sigue al dedo: guía del cambio de objetivo
			_overlay.draw_line(c, ic, Color(StoneUI.AMBER, 0.7 * ba), 2.0, true)
		_draw_icon(String(b["key"]), ic + Vector2(0, 1.5), r * 0.92, Color(0, 0, 0, 0.6 * ba))   # sombra del icono
		_draw_icon(String(b["key"]), ic, r * 0.92, Color(icon_col, ba))
		if _editing and b["key"] == _edit_sel:
			_draw_selection(c, r)
	if _editing and _edit_sel == JOY_KEY:
		_draw_selection(_joy_center, _joy_radius)

## Joystick: disco de piedra oscura con borde de hierro y ocho muescas; el pulgar es un pomo de hierro.
func _draw_joystick(a: float) -> void:
	var c := _joy_center
	var r := _joy_radius
	var band := maxf(6.0, r * 0.14)
	var st := StoneUI.STONE_DARK
	StoneUI.draw_stone_disc(_overlay, c, r - band * 0.5, Color(st.r, st.g, st.b, 0.85 * a))
	_overlay.draw_arc(c, r - band - 4.0, 0.0, TAU, 56, Color(0, 0, 0, 0.35 * a), 6.0, true)   # sombra interior
	# guía de dirección: anillo fino y cuatro marcas ámbar
	_overlay.draw_arc(c, r * 0.55, 0.0, TAU, 48, Color(StoneUI.OUTLINE, 0.45 * a), 1.5, true)
	for k in 4:
		var d := Vector2.from_angle(-PI * 0.5 + k * PI * 0.5)
		var tip := c + d * (r - band - 6.0)
		var side := Vector2(-d.y, d.x) * r * 0.07
		_overlay.draw_colored_polygon(PackedVector2Array([tip, tip - d * r * 0.1 + side, tip - d * r * 0.1 - side]),
			Color(StoneUI.AMBER, 0.55 * a))
	StoneUI.draw_iron_ring(_overlay, c, r - band, r, a, 8)
	# pomo de hierro
	var kp := c + _joy_offset
	var kr := r * 0.42
	var active := _joy_id != -1
	_overlay.draw_circle(kp + Vector2(0, kr * 0.12), kr, Color(0, 0, 0, 0.4 * a))   # sombra
	_overlay.draw_circle(kp, kr, Color(StoneUI.IRON_DARK, 0.95 * a))
	_overlay.draw_circle(kp, kr * 0.8, Color(StoneUI.IRON, 0.95 * a))
	_overlay.draw_arc(kp, kr * 0.62, PI * 0.95, PI * 1.55, 20, Color(StoneUI.IRON_LIGHT, 0.7 * a), maxf(2.0, kr * 0.12), true)
	_overlay.draw_arc(kp, kr, 0.0, TAU, 40, Color(StoneUI.OUTLINE, a), 1.8, true)
	_overlay.draw_circle(kp, kr * 0.22, Color(StoneUI.AMBER if active else StoneUI.IRON_LIGHT, a))
	_overlay.draw_circle(kp, kr * 0.1, Color(StoneUI.OUTLINE, a))
	if active:
		_overlay.draw_arc(kp, kr + 2.0, 0.0, TAU, 40, Color(StoneUI.AMBER, 0.8 * a), 2.0, true)

## Hueco redondo del estilo del inventario. `big` = botón de ataque (anillo doble con remaches).
func _draw_socket(c: Vector2, r: float, col: Color, a: float, pressed: bool, big: bool) -> void:
	var band := maxf(5.0, r * (0.17 if big else 0.2))
	var inner := r - band
	_overlay.draw_circle(c + Vector2(0, 2.0), r, Color(0, 0, 0, 0.35 * a))   # sombra sobre la escena
	_overlay.draw_circle(c, inner, Color(0.025, 0.04, 0.04, 0.82 * a))
	var glow := 0.75 if pressed else 0.5
	for i in 5:
		_overlay.draw_arc(c, inner - 1.5 - i * (inner * 0.07), 0.0, TAU, 48,
			Color(col, (glow - i * 0.1) * a), maxf(2.0, inner * 0.07), true)
	if pressed:
		_overlay.draw_circle(c, inner * 0.6, Color(col, 0.18 * a))
	StoneUI.draw_iron_ring(_overlay, c, inner, r, a, 8 if big else 4)
	if big:
		# segundo aro exterior con remaches, como la placa del HUD de armas
		var outer := r + band * 0.55
		_overlay.draw_arc(c, outer, 0.0, TAU, 64, Color(StoneUI.IRON_DARK, a), band * 0.5, true)
		_overlay.draw_arc(c, outer + band * 0.25, 0.0, TAU, 64, Color(StoneUI.OUTLINE, a), 1.4, true)
		for k in 8:
			var p := c + Vector2.from_angle(PI / 8.0 + k * TAU / 8.0) * outer
			_overlay.draw_circle(p, maxf(1.8, band * 0.16), Color(StoneUI.IRON_LIGHT, a))
			_overlay.draw_circle(p, maxf(0.9, band * 0.07), Color(StoneUI.OUTLINE, a))
	if pressed:
		_overlay.draw_arc(c, inner - 1.0, 0.0, TAU, 48, Color(StoneUI.AMBER, a), 3.0, true)

func _draw_selection(c: Vector2, r: float) -> void:
	var amber := Color(StoneUI.AMBER, 0.95)
	_overlay.draw_arc(c, r + 10.0, 0.0, TAU, 64, amber, 3.0, true)
	for k in 4:
		var dir := Vector2.from_angle(PI * 0.25 + k * PI * 0.5)
		StoneUI.draw_diamond(_overlay, c + dir * (r + 10.0), 5.0)

# ───────────────────────────── Iconos ─────────────────────────────

## Icono vectorial centrado en c; r = radio del botón.
func _draw_icon(key: String, c: Vector2, r: float, col: Color) -> void:
	var u := r * 0.5
	var w := maxf(2.5, r * 0.1)
	var o := _overlay
	match key:
		"attack":   # espada en diagonal con guarda
			o.draw_line(c + Vector2(-0.75, 0.75) * u, c + Vector2(0.8, -0.8) * u, col, w * 1.6, true)
			var perp := Vector2(1, 1).normalized() * u * 0.5
			var guard := c + Vector2(-0.2, 0.2) * u
			o.draw_line(guard - perp, guard + perp, col, w * 1.4, true)
			o.draw_circle(c + Vector2(-0.8, 0.8) * u, w * 1.1, col)
		"jump":     # flecha de salto
			var k := u * 0.9
			o.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k), c + Vector2(k, k * 0.55), c + Vector2(0, k * 0.1), c + Vector2(-k, k * 0.55),
			]), col)
		"dodge":    # dos chevrones hacia delante (impulso)
			for dx in [-0.5, 0.25]:
				o.draw_polyline(PackedVector2Array([
					c + Vector2(dx * u, -0.7 * u), c + Vector2((dx + 0.6) * u, 0.0), c + Vector2(dx * u, 0.7 * u),
				]), col, w * 1.3, true)
		"alt":      # destello de 4 puntas
			var pts := PackedVector2Array()
			for k in 8:
				var rad := u * (0.95 if k % 2 == 0 else 0.3)
				pts.append(c + Vector2.from_angle(-PI * 0.5 + k * PI * 0.25) * rad)
			o.draw_colored_polygon(pts, col)
		"target":   # mira
			o.draw_arc(c, u * 0.6, 0.0, TAU, 32, col, w, true)
			for k in 4:
				var d := Vector2.from_angle(k * PI * 0.5)
				o.draw_line(c + d * u * 0.4, c + d * u * 1.05, col, w, true)
			o.draw_circle(c, w * 0.9, col)
		"skill":    # rayo
			o.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.2, -1.0) * u, c + Vector2(-0.55, 0.1) * u, c + Vector2(-0.05, 0.1) * u,
				c + Vector2(-0.25, 1.0) * u, c + Vector2(0.55, -0.2) * u, c + Vector2(0.05, -0.2) * u,
			]), col)
		"parry":    # escudo
			var shield := PackedVector2Array([
				c + Vector2(-0.8, -0.75) * u, c + Vector2(0.0, -0.95) * u, c + Vector2(0.8, -0.75) * u,
				c + Vector2(0.75, 0.15) * u, c + Vector2(0.0, 1.0) * u, c + Vector2(-0.75, 0.15) * u,
			])
			o.draw_colored_polygon(shield, Color(col.r, col.g, col.b, col.a * 0.35))
			var outline := shield.duplicate()
			outline.append(shield[0])
			o.draw_polyline(outline, col, w, true)
		"reload":   # flecha circular
			var rad := u * 0.7
			var end_a := deg_to_rad(230.0)
			o.draw_arc(c, rad, deg_to_rad(-60.0), end_a, 28, col, w * 1.3, true)
			var p := c + Vector2.from_angle(end_a) * rad
			var tangent := Vector2(-sin(end_a), cos(end_a))
			var normal := Vector2.from_angle(end_a)
			o.draw_colored_polygon(PackedVector2Array([
				p + tangent * u * 0.6, p + normal * u * 0.4, p - normal * u * 0.4,
			]), col)
		"weapon":   # intercambio: dos flechas opuestas
			_draw_arrow(c + Vector2(-0.8, -0.38) * u, c + Vector2(0.8, -0.38) * u, u * 0.4, w * 1.3, col)
			_draw_arrow(c + Vector2(0.8, 0.38) * u, c + Vector2(-0.8, 0.38) * u, u * 0.4, w * 1.3, col)

func _draw_arrow(from: Vector2, to: Vector2, head: float, w: float, col: Color) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	_overlay.draw_line(from, to, col, w, true)
	_overlay.draw_polyline(PackedVector2Array([to - dir * head + side * head, to, to - dir * head - side * head]), col, w, true)

# ───────────────────────────── Entrada ─────────────────────────────

func _input(event: InputEvent) -> void:
	if _editing:
		_edit_input(event)
		return
	if not visible or get_tree().paused:
		return

	if event is InputEventScreenTouch:
		_on_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
	elif not _touch_available:
		# Pruebas en PC con el ratón (en un móvil el toque ya llega como InputEventScreenTouch)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_on_press(0, event.position, event.pressed)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_on_drag(0, event.position, event.relative)

## Botón más cercano cuyo radio táctil contiene el punto. Elegir el MÁS CERCANO (no el primero del
## array) evita que las zonas ampliadas de los botones vecinos se roben los toques: antes, un toque en
## el borde de FIJAR podía caer en la zona de ATAQUE ESPECIAL y no fijaba a nadie.
func _button_at(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in BUTTONS.size():
		if _btn_id[i] != -1 or _is_hidden(i) or _is_unavailable(i):
			continue
		var d := pos.distance_to(_btn_center[i])
		if d <= _btn_radius[i] * 1.2 and d < best_d:
			best_d = d
			best = i
	return best

func _on_press(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var bi := _button_at(pos)
		if bi != -1:
			_btn_id[bi] = idx
			if String(BUTTONS[bi]["key"]) == "target":
				_tgt_origin = pos
				_tgt_drag = Vector2.ZERO
				_tgt_switched = false
				_tgt_was_locked = VirtualInput.target_locked
			_set_button(bi, true)
			_overlay.queue_redraw()
		elif _joy_id == -1 and _in_joystick_zone(pos):
			_joy_id = idx
			_joy_center = _clamp_to_screen(pos)
			_update_joystick(pos)
		elif _look_id == -1 and idx != _joy_id and not _btn_id.has(idx):
			_look_id = idx
	else:
		var bi := _btn_id.find(idx)
		if bi != -1:
			_btn_id[bi] = -1
			_set_button(bi, false)
			_overlay.queue_redraw()
		elif idx == _joy_id:
			_joy_id = -1
			_joy_center = _joy_rest
			_joy_offset = Vector2.ZERO
			VirtualInput.movement_vector = Vector2.ZERO
			_overlay.queue_redraw()
		elif idx == _look_id:
			_look_id = -1

## Traduce el estado de un botón a VirtualInput.
func _set_button(bi: int, down: bool) -> void:
	match String(BUTTONS[bi]["key"]):
		"attack": VirtualInput.is_attacking = down
		"jump": VirtualInput.is_jumping = down
		"run": VirtualInput.is_running = down
		"interact": VirtualInput.just_pressed_interact = down or VirtualInput.just_pressed_interact
		"alt": VirtualInput.is_alt_attack = down
		"skill": VirtualInput.just_pressed_skill = down or VirtualInput.just_pressed_skill
		"reload": VirtualInput.just_pressed_reload = down or VirtualInput.just_pressed_reload
		"dodge": VirtualInput.just_pressed_dodge = down or VirtualInput.just_pressed_dodge
		"parry": VirtualInput.just_pressed_parry = down or VirtualInput.just_pressed_parry
		"weapon": VirtualInput.just_pressed_cycle_next = down or VirtualInput.just_pressed_cycle_next
		"target":
			# Sin objetivo: fija al pulsar. Con objetivo: suelta al levantar el dedo, salvo que se
			# haya arrastrado para cambiar de objetivo.
			if down and not _tgt_was_locked:
				VirtualInput.just_pressed_target = true
			elif not down:
				if _tgt_was_locked and not _tgt_switched:
					VirtualInput.just_pressed_target = true
				_tgt_drag = Vector2.ZERO

func _on_drag(idx: int, pos: Vector2, relative: Vector2) -> void:
	if idx == _joy_id:
		_update_joystick(pos)
	elif idx == _look_id:
		VirtualInput.look_vector += relative
	elif idx != -1 and _button_id("target") == idx:
		_drag_target(pos)
	elif VirtualInput.attack_aims and _button_id("attack") == idx:
		# Apuntando con el botón de disparo: el mismo dedo mueve la mira
		VirtualInput.look_vector += relative
	elif VirtualInput.alt_aims and _button_id("alt") == idx:
		# Cargando el especial (lanzamiento de la espalanza): el dedo del botón apunta
		VirtualInput.look_vector += relative

## Arrastre del dedo sobre FIJAR: al pasar el umbral pide cambiar al enemigo de esa dirección y vuelve a
## medir desde ahí, así seguir deslizando salta al siguiente (como inclinar otra vez el stick).
func _drag_target(pos: Vector2) -> void:
	var r := _btn_radius[_key_index("target")]
	var d := pos - _tgt_origin
	if VirtualInput.target_locked and d.length() >= maxf(TARGET_SWIPE_MIN, r * TARGET_SWIPE_RADII):
		VirtualInput.target_switch_dir = d.normalized()
		_tgt_switched = true
		_tgt_origin = pos
		d = Vector2.ZERO
	_tgt_drag = d.limit_length(r * 0.6)
	_overlay.queue_redraw()

## Dedo que mantiene pulsado el botón `key` (-1 si ninguno).
func _button_id(key: String) -> int:
	for i in BUTTONS.size():
		if String(BUTTONS[i]["key"]) == key:
			return _btn_id[i]
	return -1

func _in_joystick_zone(pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return pos.x < vp.x * JOY_ZONE_WIDTH and pos.y > vp.y * JOY_ZONE_TOP

## Evita que el joystick flotante nazca cortado por el borde de la pantalla.
func _clamp_to_screen(pos: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var m := _joy_radius + 8.0
	return Vector2(clampf(pos.x, m, vp.x - m), clampf(pos.y, m, vp.y - m))

func _update_joystick(pos: Vector2) -> void:
	var off := pos - _joy_center
	if off.length() > _joy_radius:
		off = off.normalized() * _joy_radius
	_joy_offset = off
	var n := off / _joy_radius
	var mag := n.length()
	if mag < DEAD_ZONE:
		VirtualInput.movement_vector = Vector2.ZERO
	else:
		# Zona muerta reescalada para que el movimiento arranque suave desde 0
		VirtualInput.movement_vector = n.normalized() * ((mag - DEAD_ZONE) / (1.0 - DEAD_ZONE))
	_overlay.queue_redraw()

func _release_all() -> void:
	_joy_id = -1
	_look_id = -1
	for i in _btn_id.size():
		_btn_id[i] = -1
	_joy_center = _joy_rest
	_joy_offset = Vector2.ZERO
	_tgt_drag = Vector2.ZERO
	_tgt_switched = false
	_tgt_was_locked = false
	VirtualInput.movement_vector = Vector2.ZERO
	VirtualInput.is_jumping = false
	VirtualInput.is_running = false
	VirtualInput.is_attacking = false
	VirtualInput.is_alt_attack = false
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()

# ───────────────────────────── Editor de disposición ─────────────────────────────
## Se abre desde Ajustes → Controles táctiles. Tocar un botón (o el joystick) lo selecciona; arrastrarlo
## lo mueve; el deslizador cambia su tamaño; "Visible" lo muestra/oculta. Funciona con el juego en pausa.

func begin_edit() -> void:
	if _editing:
		return
	_release_all()
	_editing = true
	_edit_sel = ""
	_edit_drag_id = -1
	layer = 125
	_build_edit_panel()
	_refresh_edit_panel()
	_overlay.queue_redraw()

func end_edit() -> void:
	if not _editing:
		return
	_editing = false
	layer = 50
	if is_instance_valid(_edit_layer):
		_edit_layer.queue_free()
	_edit_layer = null
	_edit_panel = null
	SettingsManager.save_settings()
	_layout()
	SettingsManager.touch_edit_finished.emit()

func _key_index(key: String) -> int:
	for i in BUTTONS.size():
		if String(BUTTONS[i]["key"]) == key:
			return i
	return -1

func _edit_center(key: String) -> Vector2:
	return _joy_rest if key == JOY_KEY else _btn_center[_key_index(key)]

func _edit_radius(key: String) -> float:
	return _joy_radius if key == JOY_KEY else _btn_radius[_key_index(key)]

func _edit_name(key: String) -> String:
	return "Joystick" if key == JOY_KEY else String(BUTTONS[_key_index(key)]["name"])

## Elemento bajo el dedo (botones antes que el joystick); "" si no hay.
func _edit_hit(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for i in BUTTONS.size():
		if not _in_mode(String(BUTTONS[i]["key"])):
			continue
		var d := pos.distance_to(_btn_center[i])
		if d <= _btn_radius[i] * 1.15 and d < best_d:
			best = String(BUTTONS[i]["key"])
			best_d = d
	if best == "" and pos.distance_to(_joy_rest) <= _joy_radius * 1.1:
		return JOY_KEY
	return best

func _edit_over_panel(pos: Vector2) -> bool:
	return is_instance_valid(_edit_panel) and _edit_panel.get_global_rect().has_point(pos)

func _edit_input(event: InputEvent) -> void:
	var consumed := false
	if event is InputEventScreenTouch:
		consumed = _edit_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		consumed = _edit_drag(event.index, event.position)
	elif not _touch_available:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			consumed = _edit_press(0, event.position, event.pressed)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			consumed = _edit_drag(0, event.position)
	if consumed:
		get_viewport().set_input_as_handled()

func _edit_press(idx: int, pos: Vector2, pressed: bool) -> bool:
	if pressed:
		if _edit_over_panel(pos):
			return false
		_edit_sel = _edit_hit(pos)
		if _edit_sel != "" and _edit_drag_id == -1:
			_edit_drag_id = idx
			_edit_grab = _edit_center(_edit_sel) - pos
		_refresh_edit_panel()
		_overlay.queue_redraw()
		return true
	if idx == _edit_drag_id:
		_edit_drag_id = -1
		SettingsManager.save_settings()
		_place_edit_panel()
		return true
	return false

func _edit_drag(idx: int, pos: Vector2) -> bool:
	if idx != _edit_drag_id or _edit_sel == "":
		return false
	var vp := get_viewport().get_visible_rect().size
	var r := _edit_radius(_edit_sel) + 4.0
	var target := pos + _edit_grab
	target = Vector2(clampf(target.x, r, vp.x - r), clampf(target.y, r, vp.y - r))
	_store_custom(_edit_sel, target, _selected_scale())
	_layout()
	return true

func _selected_scale() -> float:
	var c := _custom(_edit_sel)
	return 1.0 if c.is_empty() else _custom_scale(c)

func _store_custom(key: String, center: Vector2, s: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	SettingsManager.touch_custom[key] = {"x": center.x / vp.x, "y": center.y / vp.y, "s": s}

func _build_edit_panel() -> void:
	_edit_layer = CanvasLayer.new()
	_edit_layer.layer = 130
	add_child(_edit_layer)
	_edit_panel = StoneUI.StonePanel.new(20.0)
	_edit_panel.theme = RumbangStyle.get_theme()
	_edit_layer.add_child(_edit_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 8)
	_edit_panel.add_child(box)

	box.add_child(StoneUI.Rail.new("CONTROLES TÁCTILES", 13, 240.0))
	_edit_title = Label.new()
	_edit_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_edit_title.add_theme_color_override("font_color", StoneUI.AMBER)
	_edit_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_edit_title.add_theme_constant_override("outline_size", 4)
	box.add_child(_edit_title)

	var size_row := HBoxContainer.new()
	box.add_child(size_row)
	var size_lbl := Label.new()
	size_lbl.text = "Tamaño"
	size_lbl.custom_minimum_size = Vector2(70, 0)
	size_row.add_child(size_lbl)
	_edit_slider = HSlider.new()
	_edit_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_slider.min_value = EDIT_SCALE_MIN
	_edit_slider.max_value = EDIT_SCALE_MAX
	_edit_slider.step = 0.05
	_edit_slider.value = 1.0
	_edit_slider.value_changed.connect(_on_edit_scale)
	var track := StyleBoxFlat.new()
	track.bg_color = StoneUI.IRON_DARK
	track.border_color = StoneUI.IRON
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = StoneUI.AMBER.darkened(0.15)
	_edit_slider.add_theme_stylebox_override("slider", track)
	_edit_slider.add_theme_stylebox_override("grabber_area", fill)
	_edit_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	_edit_slider.drag_ended.connect(func(_changed: bool): SettingsManager.save_settings())
	size_row.add_child(_edit_slider)
	_edit_val = Label.new()
	_edit_val.custom_minimum_size = Vector2(52, 0)
	size_row.add_child(_edit_val)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	box.add_child(row1)
	_edit_visible = CheckButton.new()
	_edit_visible.text = "Visible"
	_edit_visible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_visible.add_theme_color_override("font_color", StoneUI.TEXT)
	_edit_visible.toggled.connect(_on_edit_visible)
	row1.add_child(_edit_visible)
	var reset_one := Button.new()
	reset_one.text = "Restablecer botón"
	StoneUI.style_button(reset_one, 12)
	reset_one.pressed.connect(_on_edit_reset_one)
	row1.add_child(reset_one)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	box.add_child(row2)
	var reset_all := Button.new()
	reset_all.text = "Restablecer todo"
	reset_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StoneUI.style_button(reset_all, 12)
	reset_all.pressed.connect(_on_edit_reset_all)
	row2.add_child(reset_all)
	var done := Button.new()
	done.text = "Listo"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StoneUI.style_button(done, 12)
	done.pressed.connect(end_edit)
	row2.add_child(done)

func _refresh_edit_panel() -> void:
	if _edit_panel == null:
		return
	var has := _edit_sel != ""
	_edit_title.text = _edit_name(_edit_sel) if has else "Toca un botón para editarlo; arrástralo para moverlo"
	_edit_slider.editable = has
	_edit_visible.disabled = (not has) or _edit_sel == JOY_KEY
	var s := _selected_scale() if has else 1.0
	_edit_slider.set_value_no_signal(s)
	_edit_val.text = "×%.2f" % s
	_edit_visible.set_pressed_no_signal(not (has and SettingsManager.touch_hidden.has(_edit_sel)))
	_place_edit_panel()
	_place_edit_panel.call_deferred()   # el título con autowrap cambia de alto al fotograma siguiente

## El panel se coloca en la mitad contraria a la del elemento seleccionado para no taparlo.
func _place_edit_panel() -> void:
	if _edit_panel == null:
		return
	_edit_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _edit_panel.get_combined_minimum_size()
	var at_bottom := _edit_sel != "" and _edit_center(_edit_sel).y < vp.y * 0.5
	_edit_panel.position = Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 12.0 if at_bottom else 12.0)

func _on_edit_scale(v: float) -> void:
	if _edit_sel == "":
		return
	_store_custom(_edit_sel, _edit_center(_edit_sel), v)
	_edit_val.text = "×%.2f" % v
	_layout()

func _on_edit_visible(on: bool) -> void:
	if _edit_sel == "" or _edit_sel == JOY_KEY:
		return
	if on:
		SettingsManager.touch_hidden.erase(_edit_sel)
	elif not SettingsManager.touch_hidden.has(_edit_sel):
		SettingsManager.touch_hidden.append(_edit_sel)
	SettingsManager.save_settings()
	_overlay.queue_redraw()

func _on_edit_reset_one() -> void:
	if _edit_sel == "":
		return
	SettingsManager.touch_custom.erase(_edit_sel)
	SettingsManager.touch_hidden.erase(_edit_sel)
	SettingsManager.save_settings()
	_layout()
	_refresh_edit_panel()

func _on_edit_reset_all() -> void:
	SettingsManager.touch_custom.clear()
	SettingsManager.touch_hidden = []
	SettingsManager.save_settings()
	_layout()
	_refresh_edit_panel()
