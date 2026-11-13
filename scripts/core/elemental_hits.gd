class_name ElementalHits
extends RefCounted

## Efecto elemental de cada golpe del jugador en la mazmorra (Fase 2 del plan de equipo).
## DungeonGoblin.take_damage() llama a on_hit() con el daño recibido; el elemento activo lo decide
## PlayerEquipment.active_element() (el del arma en la mano, reforzado por la armadura del mismo elemento).
##   fuego   : quemadura (StatusEffects "burn")
##   natural : veneno (StatusEffects "poison", se acumula)
##   frio    : ralentiza al enemigo (DungeonGoblin.apply_chill)
##   sombra  : roba vida del daño hecho
## Los golpes de estados (DoT) no vuelven a provocar efectos: DungeonGoblin._force_dot.

const DRAIN_MAX_PER_HIT := 2.0
## Aviso flotante sobre el enemigo cuando el elemento se aplica (mayúsculas y sin tildes: la fuente pixel no las tiene).
const POP_TEXT := {"fuego": "QUEMADO", "natural": "VENENO", "frio": "ESCARCHA"}
const POP_COOLDOWN_MS := 600

static func _pop(enemy: Node, text: String, color: Color) -> void:
	if text == "" or not enemy is Node3D or not enemy.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - int(enemy.get_meta("_elem_pop_ms", -10000)) < POP_COOLDOWN_MS:
		return   # un aviso por enemigo cada poco: los golpes rápidos no llenan la pantalla
	enemy.set_meta("_elem_pop_ms", now)
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 20
	l.outline_size = 8
	l.modulate = color
	l.no_depth_test = true
	enemy.add_child(l)
	l.position = Vector3(0, 2.4, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 3.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

static func on_hit(enemy: Node, amount: float) -> void:
	if GameData.game_mode != "dungeon" or amount <= 0.0 or not is_instance_valid(enemy):
		return
	if enemy.get("_force_dot") == true or enemy.get("puppet") == true or not enemy.is_inside_tree():
		return
	var p := enemy.get_tree().get_first_node_in_group("player")
	var eq: PlayerEquipment = p.get("equipment") as PlayerEquipment if p else null
	if eq == null:
		return
	var el := eq.active_element()
	if el.is_empty():
		return
	apply(String(el["id"]), float(el["power"]), enemy, amount, p, eq.current_weapon())

## Aplica el elemento `id` con fuerza `power` (1.0 = base) al enemigo. Separado para poder probarlo.
static func apply(id: String, power: float, enemy: Node, amount: float, player: Node, weapon: int) -> void:
	var cfg: Dictionary = EquipmentDB.ELEMENTS.get(id, {})
	if cfg.is_empty():
		return
	if cfg.has("drain"):
		if player.has_method("heal") and float(player.get("hp")) < float(player.get("max_hp")):
			player.heal(minf(amount * float(cfg["drain"]) * power, DRAIN_MAX_PER_HIT))
		return
	if float(enemy.get("hp")) <= 0.0:
		return
	if randf() >= minf(float(cfg["chance"]) * power, 1.0):
		return
	var dur := float(cfg["dur"])
	_pop(enemy, String(POP_TEXT.get(id, "")), cfg["color"])
	match id:
		"fuego":
			StatusEffects.apply_to(enemy, "burn", amount * float(cfg["dps"]) * power, dur, player, weapon)
		"natural":
			StatusEffects.apply_to(enemy, "poison", amount * float(cfg["dps"]) * power, dur, player, weapon)
		"frio":
			if enemy.has_method("apply_chill"):
				# más fuerza = más frío (mínimo 25 % de velocidad)
				var factor := clampf(1.0 - (1.0 - float(cfg["slow"])) * power, 0.25, 1.0)
				enemy.apply_chill(factor, dur)
