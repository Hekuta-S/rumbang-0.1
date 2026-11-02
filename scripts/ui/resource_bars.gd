class_name ResourceBars
extends Control

## Energía, maná y balas del jugador (solo mazmorra), justo debajo de la barra de vida.
##  - Barra amarilla: energía (golpes cuerpo a cuerpo, rodar, saltar).
##  - Barra azul: maná (magia). Barra naranja con el número: balas del arma de fuego que llevas en la mano.
## Parpadea en rojo cuando un recurso no alcanza para la acción que intentaste.

const W := 300.0
const BAR_H := 11.0
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
var _rows := 3

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = GameData.game_mode == "dungeon"
	var h := PAD * 2.0 + BAR_H * _rows + GAP * (_rows - 1)
	custom_minimum_size = Vector2(W + PAD * 2.0, h)
	# Justo debajo del panel de vida: abajo a la izquierda sobre el adorno de la barra de armas; en móvil
	# (arriba a la izquierda, donde está el panel de vida de 44 px) pegado bajo él.
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
	for k in _denied.keys():
		_denied[k] -= delta
		if _denied[k] <= 0.0:
			_denied.erase(k)
	queue_redraw()

func _on_denied(kind: int) -> void:
	_denied[kind] = 0.35

func _bar(y: float, ratio: float, color: Color, kind: int, text: String) -> void:
	var flash: bool = _denied.has(kind) and int(_denied[kind] * 20.0) % 2 == 0
	var col := DENIED_COLOR if flash else color
	# Icono: rombo del color del recurso
	var c := Vector2(PAD + 5.0, y + BAR_H * 0.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), col)
	HudDraw.bar(self, Rect2(PAD + 14.0, y, W - 14.0, BAR_H), ratio, col, -1.0, 0.25 if kind != PlayerResources.Kind.AMMO else 0.0)
	if text != "":
		HudDraw.text(self, _font, Vector2(PAD + 22.0, y + BAR_H - 1.0), text, 10, Color(1, 1, 1, 0.95))

func _draw() -> void:
	if _res == null or not _res.active:
		return
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), RumbangStyle.NEON_CYAN)
	var y := PAD
	_bar(y, _res.energy / PlayerResources.ENERGY_MAX, ENERGY_COLOR, PlayerResources.Kind.ENERGY, "ENERGÍA %d" % int(_res.energy))
	y += BAR_H + GAP
	_bar(y, _res.mana / PlayerResources.MANA_MAX, MANA_COLOR, PlayerResources.Kind.MANA, "MANÁ %d" % int(_res.mana))
	y += BAR_H + GAP
	var weapon: int = _player.current_weapon() if _player and _player.has_method("current_weapon") else -1
	var max_ammo := _res.max_ammo_of(weapon)
	if max_ammo > 0:
		var a := _res.ammo_of(weapon)
		_bar(y, float(a) / float(max_ammo), AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS %d / %d" % [a, max_ammo])
	else:
		_bar(y, 0.0, AMMO_COLOR, PlayerResources.Kind.AMMO, "BALAS —")
