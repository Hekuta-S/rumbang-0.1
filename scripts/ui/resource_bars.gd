class_name ResourceBars
extends Control

## Energía, maná y balas del jugador (solo mazmorra), justo debajo de la barra de vida.
##  - Energía: siempre (golpes cuerpo a cuerpo, rodar, saltar).
##  - Maná: solo si el arma que llevas en la mano gasta maná (magia).
##  - Balas: solo si el arma que llevas en la mano es de fuego (con el número de balas).
## Escritorio: no dibuja nada; FloatingVitals pinta la energía (pips, uno cada ENERGY_PIP puntos), el maná y las
## balas en vertical junto al personaje leyendo de aquí. El rect se conserva como ancla de la disposición.
## Móvil: panel con barras inclinadas (HudDraw).
## Parpadea en rojo cuando un recurso no alcanza para la acción que intentaste.

const W := 300.0
const BAR_H := 11.0
const ENERGY_H := 17.0               ## la energía se gasta en casi todo: barra más gruesa y con borde
const GAP := 5.0
const PAD := 10.0

const ENERGY_PIP := 25.0             ## puntos de energía por pip

const ENERGY_COLOR := Color(0.25, 0.95, 1.0)   ## neón cian
const MANA_COLOR := Color(0.78, 0.38, 1.0)    ## violeta arcano
const AMMO_COLOR := Color(1.0, 0.55, 0.15)
const DENIED_COLOR := Color(1.0, 0.2, 0.2)
const EXHAUSTED_COLOR := Color(0.85, 0.5, 0.3)
const FRAME := Color(0.08, 0.07, 0.09, 0.82)
const BORDER := Color(0.62, 0.56, 0.47)

var _player: Node3D
var _res: PlayerResources
var _denied := {}                    ## Kind -> tiempo restante de parpadeo
var _font: Font
var _show_mana := false
var _show_ammo := false
var _mobile := false

## Cambió el alto (aparece o desaparece una barra): el HUD recoloca la fila de oro + pausa.
signal layout_changed

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = GameData.game_mode == "dungeon"
	apply_layout(Quality.is_mobile())

## Alto ocupado en pantalla (0 si no se ve: supervivencia).
func used_height() -> float:
	return custom_minimum_size.y if visible else 0.0

## Coloca las barras (ver HudLayout). Desktop: hueco fijo bajo la vida (HudLayout.RESOURCES_H), las filas se
## dibujan desde arriba; móvil: arriba a la izquierda, pegadas bajo el panel de vida, con el alto de las filas visibles.
func apply_layout(mobile: bool) -> void:
	_mobile = mobile
	_layout()

func _layout() -> void:
	if _mobile:
		var h := PAD * 2.0 + ENERGY_H
		if _show_mana:
			h += GAP + BAR_H
		if _show_ammo:
			h += GAP + BAR_H
		custom_minimum_size = Vector2(W + PAD * 2.0, h)
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = HudLayout.MARGIN
		offset_top = HudLayout.MARGIN + HudLayout.VITALS_H
		offset_right = offset_left + custom_minimum_size.x
		offset_bottom = offset_top + custom_minimum_size.y
	else:
		custom_minimum_size = Vector2(W + PAD * 2.0, HudLayout.RESOURCES_H)
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = HudLayout.MARGIN
		offset_right = offset_left + custom_minimum_size.x
		offset_bottom = HudLayout.RESOURCES_BOTTOM
		offset_top = offset_bottom - custom_minimum_size.y
	layout_changed.emit()

func _current_weapon() -> int:
	if _player and _player.has_method("current_weapon"):
		return _player.current_weapon()
	return -1

## ¿El arma en la mano usa balas? (reserva de la mazmorra o cargador)
func _uses_ammo(weapon: int) -> bool:
	if weapon < 0 or _res == null:
		return false
	if _res.kind_of(weapon) == PlayerResources.Kind.AMMO:
		return true
	var inv: PlayerWeaponInventory = _player.get("weapon_inventory") if _player else null
	return inv != null and int(inv.weapon_mag_size.get(weapon, 0)) > 0

func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_res = null
	if _player and _res == null:
		_res = _player.get("resources")
		if _res:
			_res.denied.connect(_on_denied)
	var weapon := _current_weapon()
	var show_mana := _res != null and weapon >= 0 and _res.kind_of(weapon) == PlayerResources.Kind.MANA
	var show_ammo := _uses_ammo(weapon)
	if show_mana != _show_mana or show_ammo != _show_ammo:
		_show_mana = show_mana
		_show_ammo = show_ammo
		_layout()
	for k in _denied.keys():
		_denied[k] -= delta
		if _denied[k] <= 0.0:
			_denied.erase(k)
	queue_redraw()

func _on_denied(kind: int) -> void:
	_denied[kind] = 0.35

func _flash_col(kind: int, color: Color) -> Color:
	var flash: bool = _denied.has(kind) and int(_denied[kind] * 20.0) % 2 == 0
	return DENIED_COLOR if flash else color

func _ammo_values() -> Vector2i:
	var weapon := _current_weapon()
	var max_ammo := _res.max_ammo_of(weapon)
	if max_ammo > 0:
		return Vector2i(_res.ammo_of(weapon), max_ammo)
	var inv: PlayerWeaponInventory = _player.get("weapon_inventory") if _player else null
	var mag: int = int(inv.weapon_mag_size.get(weapon, 0)) if inv else 0
	if mag > 0:
		return Vector2i(int(inv.weapon_ammo.get(weapon, mag)), mag)
	return Vector2i(0, 0)

# --- Móvil: panel con barras inclinadas ------------------------------------------------------------------------

func _bar(y: float, h: float, ratio: float, color: Color, kind: int, text: String) -> void:
	var col := _flash_col(kind, color)
	# Icono: rombo del color del recurso
	var c := Vector2(PAD + 5.0, y + h * 0.5)
	var d := 5.0 if h <= BAR_H else 6.5
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), col)
	var r := Rect2(PAD + 14.0, y, W - 14.0, h)
	HudDraw.bar(self, r, ratio, col, -1.0, 0.25 if kind != PlayerResources.Kind.AMMO else 0.0)
	if kind == PlayerResources.Kind.ENERGY:
		# Borde claro del color del recurso: se distingue sobre fondos oscuros y claros
		var outline := HudDraw._slant(r.grow(1.0), 0.0, r.size.x + 2.0 - (h + 2.0) * 0.55)
		outline.append(outline[0])
		draw_polyline(outline, Color(col.lightened(0.35), 0.95), 1.5, true)
	if text != "":
		var fs := 10 if h <= BAR_H else 12
		HudDraw.text(self, _font, Vector2(PAD + 22.0, y + h * 0.5 + fs * 0.4), text, fs, Color(1, 1, 1, 0.95))

func _draw_mobile() -> void:
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), RumbangStyle.NEON_CYAN)
	var y := PAD
	# Agotado: la barra se apaga a gris anaranjado hasta que empieza a recuperarse
	var tired: bool = _res.is_exhausted()
	_bar(y, ENERGY_H, _res.energy / _res.energy_max(), EXHAUSTED_COLOR if tired else ENERGY_COLOR, PlayerResources.Kind.ENERGY,
		"AGOTADO" if tired else "ENERGÍA %d" % int(_res.energy))
	y += ENERGY_H + GAP
	if _show_mana:
		_bar(y, BAR_H, _res.mana / _res.mana_max(), MANA_COLOR, PlayerResources.Kind.MANA, "MANÁ %d" % int(_res.mana))
		y += BAR_H + GAP
	if _show_ammo:
		var a := _ammo_values()
		if a.y > 0:
			_bar(y, BAR_H, float(a.x) / float(a.y), AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS %d / %d" % [a.x, a.y])
		else:
			_bar(y, BAR_H, 0.0, AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS —")

func _draw() -> void:
	if _res == null or not _res.active:
		return
	if _mobile:
		_draw_mobile()     # escritorio: dibuja FloatingVitals
