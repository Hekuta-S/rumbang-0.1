class_name UiJuice
extends RefCounted

## Fase 4 del plan de juice (docs/PLAN_JUICE.md): animaciones de interfaz reutilizables.
##   deal_in    — las cartas de una elección entran escalonadas con rebote (en vez de aparecer de golpe).
##   hover_pop  — un botón crece al pasar por encima / tener el foco y se hunde al pulsarlo.
##   punch      — un control da un salto de escala (contadores, etiquetas).
##   flash      — destello de pantalla completa (subida de nivel).
## Los tweens van en el propio nodo: siguen su process_mode (funcionan con el juego en pausa si la UI lo hace).

const DEAL_STAGGER := 0.07
const DEAL_TIME := 0.32
const HOVER_SCALE := 1.05
const PRESS_SCALE := 0.94
const HOVER_TIME := 0.09

## Hace entrar `nodes` uno detrás de otro: aparecen pequeños y transparentes y crecen con rebote.
## Además, los botones que contengan reaccionan al ratón (hover_pop).
static func deal_in(nodes: Array, stagger: float = DEAL_STAGGER) -> void:
	var i := 0
	for n in nodes:
		var c := n as Control
		if c == null or c.is_queued_for_deletion():
			continue
		_keep_pivot_centered(c)
		c.scale = Vector2.ONE * 0.6
		c.modulate.a = 0.0
		c.rotation = deg_to_rad(randf_range(-4.0, 4.0))
		var tw := c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
		var d := stagger * i
		tw.tween_property(c, "scale", Vector2.ONE, DEAL_TIME).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, DEAL_TIME * 0.6).set_delay(d)
		tw.tween_property(c, "rotation", 0.0, DEAL_TIME).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if c is Button:
			hover_pop(c as Button)
		for b in c.find_children("*", "Button", true, false):
			hover_pop(b as Button)
		i += 1

## El botón crece un poco con el ratón encima o con el foco (mando/teclado) y se hunde al pulsarlo.
static func hover_pop(b: Button) -> void:
	if b == null or b.has_meta(&"_uj_pop"):
		return
	b.set_meta(&"_uj_pop", true)
	_keep_pivot_centered(b)
	b.mouse_entered.connect(_to_scale.bind(b, HOVER_SCALE))
	b.focus_entered.connect(_to_scale.bind(b, HOVER_SCALE))
	b.mouse_exited.connect(_unhover.bind(b))
	b.focus_exited.connect(_unhover.bind(b))
	b.button_down.connect(_to_scale.bind(b, PRESS_SCALE))
	b.button_up.connect(_to_scale.bind(b, HOVER_SCALE))

static func _unhover(b: Button) -> void:
	if is_instance_valid(b) and not b.has_focus() and not b.is_hovered():
		_to_scale(b, 1.0)

static func _to_scale(b: Control, s: float) -> void:
	if not is_instance_valid(b):
		return
	if not b.is_inside_tree() or (b is BaseButton and (b as BaseButton).disabled):
		b.scale = Vector2.ONE
		return
	var old = b.get_meta(&"_uj_tw") if b.has_meta(&"_uj_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := b.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	b.set_meta(&"_uj_tw", tw)
	tw.tween_property(b, "scale", Vector2.ONE * s, HOVER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Salto de escala: crece a `amount` y vuelve con rebote.
static func punch(c: Control, amount: float = 1.3, time: float = 0.22) -> void:
	if not is_instance_valid(c):
		return
	_keep_pivot_centered(c)
	var old = c.get_meta(&"_uj_punch") if c.has_meta(&"_uj_punch") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	c.scale = Vector2.ONE * amount
	var tw := c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	c.set_meta(&"_uj_punch", tw)
	tw.tween_property(c, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Destello de pantalla completa del color `col` que se apaga en `time` s (por encima del HUD de `owner`).
static func flash(owner: Node, col: Color, strength: float = 0.45, time: float = 0.45) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(col.r, col.g, col.b, strength)
	layer.add_child(r)
	var tw := r.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(r, "color:a", 0.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)

static func _keep_pivot_centered(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	if not c.has_meta(&"_uj_pivot"):
		c.set_meta(&"_uj_pivot", true)
		c.resized.connect(func(): if is_instance_valid(c): c.pivot_offset = c.size * 0.5)
