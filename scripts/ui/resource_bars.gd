class_name ResourceBars
extends Control

## Energía, maná y balas del jugador (solo mazmorra), justo debajo de la barra de vida.
##  - Barra cian (más gruesa): energía (golpes cuerpo a cuerpo, rodar, saltar).
##  - Barra violeta: maná (magia). Barra naranja con el número: balas del arma de fuego que llevas en la mano;
##    solo aparece si alguna de tus armas usa balas.
## Parpadea en rojo cuando un recurso no alcanza para la acción que intentaste.

const W := 300.0
const BAR_H := 11.0
const ENERGY_H := 17.0               ## la energía se gasta en casi todo: barra más gruesa y con borde
const GAP := 5.0
const PAD := 10.0

const ENERGY_COLOR := Color(0.25, 0.95, 1.0)   ## neón cian
const MANA_COLOR := Color(0.78, 0.38, 1.0)    ## violeta arcano
const AMMO_COLOR := Color(1.0, 0.55, 0.15)
const DENIED_COLOR := Color(1.0, 0.2, 0.2)
const FRAME := Color(0.08, 0.07, 0.09, 0.82)
const BORDER := Color(0.62, 0.56, 0.47)

var _player: Node3D
var _res: PlayerResources
var _denied := {}                    ## Kind -> tiempo restante de parpadeo
var _font: Font
var _show_ammo := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = GameData.game_mode == "dungeon"
	_layout()

## Alto según las filas visibles. Desktop: anclado abajo a la izquierda (crece hacia arriba) sobre el adorno de
## la barra de armas; móvil: arriba a la izquierda, pegado bajo el panel de vida de 44 px.
func _layout() -> void:
	var h := PAD * 2.0 + ENERGY_H + GAP + BAR_H
	if _show_ammo:
		h += GAP + BAR_H
	custom_minimum_size = Vector2(W + PAD * 2.0, h)
	if Quality.is_mobile():
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = 22.0
		offset_top = 22.0 + 44.0
		offset_right = offset_left + custom_minimum_size.x
		offset_bottom = offset_top + custom_minimum_size.y
	else:
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = 22.0
		offset_right = offset_left + custom_minimum_size.x
		offset_bottom = -64.0
		offset_top = offset_bottom - custom_minimum_size.y

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
	var inv: PlayerWeaponInventory = _player.get("weapon_inventory") if _player else null
	var show_ammo := inv != null and inv.has_ammo_weapon()
	if show_ammo != _show_ammo:
		_show_ammo = show_ammo
		_layout()
	for k in _denied.keys():
		_denied[k] -= delta
		if _denied[k] <= 0.0:
			_denied.erase(k)
	queue_redraw()

func _on_denied(kind: int) -> void:
	_denied[kind] = 0.35

func _bar(y: float, h: float, ratio: float, color: Color, kind: int, text: String) -> void:
	var flash: bool = _denied.has(kind) and int(_denied[kind] * 20.0) % 2 == 0
	var col := DENIED_COLOR if flash else color
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

func _draw() -> void:
	if _res == null or not _res.active:
		return
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), RumbangStyle.NEON_CYAN)
	var y := PAD
	_bar(y, ENERGY_H, _res.energy / _res.energy_max(), ENERGY_COLOR, PlayerResources.Kind.ENERGY, "ENERGÍA %d" % int(_res.energy))
	y += ENERGY_H + GAP
	_bar(y, BAR_H, _res.mana / _res.mana_max(), MANA_COLOR, PlayerResources.Kind.MANA, "MANÁ %d" % int(_res.mana))
	y += BAR_H + GAP
	if not _show_ammo:
		return
	var weapon: int = _player.current_weapon() if _player and _player.has_method("current_weapon") else -1
	var max_ammo := _res.max_ammo_of(weapon)
	if max_ammo > 0:
		var a := _res.ammo_of(weapon)
		_bar(y, BAR_H, float(a) / float(max_ammo), AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS %d / %d" % [a, max_ammo])
	else:
		_bar(y, BAR_H, 0.0, AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS —")
