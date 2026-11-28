extends Node

## Mando en los menús (GamepadUI): letras según el mando, izquierda/derecha sin saltar a la fila de abajo y
## foco visible en las cartas de DungeonChoiceUI (runas, forja). Headless:
##   godot --headless --path . res://tests/test_gamepad_nav.tscn

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASSED: " if ok else "FAILED: ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	print("--- TEST: MANDO EN MENÚS ---")
	_labels()
	await _row_nav()
	await _choice_ui()
	print("ALL GAMEPAD NAV CHECKS PASSED" if _fails == 0 else "FAILS: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _labels() -> void:
	_check(GamepadUI.family_of("Nintendo Switch Pro Controller") == "nintendo", "Pro Controller = nintendo")
	_check(GamepadUI.family_of("PS5 Controller") == "playstation", "PS5 = playstation")
	_check(GamepadUI.family_of("XInput Gamepad") == "xbox", "XInput = xbox")
	_check(GamepadUI.pad_text("A: usar   B: título", "nintendo") == "B: usar   A: título", "Nintendo cambia A y B sin pisarse")
	_check(GamepadUI.pad_text("Stick: andar   A: usar", "playstation") == "Stick: andar   CRUZ: usar", "PlayStation: A = CRUZ, Stick intacto")
	_check(GamepadUI.pad_text("A: usar", "xbox") == "A: usar", "Xbox sin cambios")
	_check(GamepadUI.label_for("RT", "nintendo") == "ZR", "RT = ZR en Nintendo")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Fila de 3 cartas y un botón SALIR debajo a la derecha: en el extremo derecho no baja a SALIR.
func _row_nav() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var cards: Array[Button] = []
	for i in 3:
		var b := Button.new()
		b.position = Vector2(100 + i * 250, 100)
		b.size = Vector2(230, 250)
		layer.add_child(b)
		cards.append(b)
	var exit := Button.new()
	exit.position = Vector2(700, 380)
	exit.size = Vector2(200, 40)
	layer.add_child(exit)
	# Lista vertical con un botón al lado (yunque): la derecha sí lleva al panel
	var list := Button.new()
	list.position = Vector2(100, 450)
	list.size = Vector2(300, 40)
	layer.add_child(list)
	var equip := Button.new()
	equip.position = Vector2(500, 560)
	equip.size = Vector2(200, 40)
	layer.add_child(equip)
	await _frames(2)
	_check(GamepadUI.row_neighbor(cards[0], 1) == cards[1], "derecha: carta 1 -> carta 2")
	_check(GamepadUI.row_neighbor(cards[1], -1) == cards[0], "izquierda: carta 2 -> carta 1")
	_check(GamepadUI.row_neighbor(cards[2], 1) == null, "derecha en la última carta: se queda (no baja a SALIR)")
	_check(GamepadUI.row_neighbor(cards[0], -1) == null, "izquierda en la primera carta: se queda")
	_check(GamepadUI.row_neighbor(list, 1) == equip, "botón solo en su fila: derecha va al panel de al lado")
	layer.queue_free()
	await _frames(1)

## DungeonChoiceUI: el foco de la carta no repite el borde normal (antes no se veía cuál estaba marcada).
func _choice_ui() -> void:
	var opts := []
	for i in 3:
		opts.append({"id": "r%d" % i, "icon": "*", "title": "RUNA %d" % i, "desc": "x"})
	var ui := DungeonChoiceUI.present(self, "RUNAS", "", opts)
	await _frames(3)
	var focused := get_viewport().gui_get_focus_owner()
	_check(focused is Button, "la primera runa tiene el foco")
	if focused is Button:
		var f := (focused as Button).get_theme_stylebox("focus") as StyleBoxFlat
		var n := (focused as Button).get_theme_stylebox("normal") as StyleBoxFlat
		_check(f != null and n != null and f.border_color != n.border_color and f.bg_color.a < 0.01, "foco = anillo distinto del borde normal")
		var next := GamepadUI.row_neighbor(focused, 1)
		_check(next != null and next.get_parent() == focused.get_parent(), "derecha va a la siguiente runa")
	ui.queue_free()
	get_tree().paused = false
	await _frames(1)
