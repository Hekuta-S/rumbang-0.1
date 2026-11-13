class_name LootHits
extends RefCounted

## Fase 2 del plan de loot (Dead Cells + Borderlands): lo que hace el equipo en cada golpe, baja, remate,
## esquiva y aturdimiento, más allá de sumar stats. Solo en la mazmorra (EquipmentDB es de la mazmorra).
##  - Rasgos condicionales (EquipmentDB.CONDITIONALS): más daño si el enemigo está aturdido, ardiendo...
##  - Fabricantes de arma (EquipmentDB.MAKERS): Tatán (aturde), Arriero (cadena), Conquistador (ejecuta), Mohán (eco)
##  - Reglas de las legendarias (EquipmentDB.RULES)
## DungeonGoblin.take_damage llama a outgoing() antes de restar la vida y a after_hit() (diferido) después.
## Los ticks de estados (_force_dot), las copias de red y los golpes de los propios efectos (meta "_loot_fx")
## no disparan nada para que no haya cadenas infinitas.

const POP_COOLDOWN_MS := 450
const TERREMOTO_RADIUS := 5.0
const DRAGON_EVERY := 3
const DRAGON_RADIUS := 3.0
const DRAGON_DPS := 6.0
const DRAGON_DUR := 3.0
const OBSIDIANA_RADIUS := 4.0
const OBSIDIANA_DAMAGE := 6.0
const OBSIDIANA_HEAL := 1.5           ## vida por enemigo alcanzado
const VACIO_COOLDOWN := 8.0
const CAZADOR_RADIUS := 3.0
const CAZADOR_SLOWMO := 0.6

static func equipment_of(node: Node) -> PlayerEquipment:
	if GameData.game_mode != "dungeon" or node == null or not node.is_inside_tree():
		return null
	var p := node.get_tree().get_first_node_in_group("player")
	return p.get("equipment") as PlayerEquipment if p else null

static func _skip(enemy: Node) -> bool:
	return enemy.get("_force_dot") == true or enemy.get("puppet") == true or enemy.has_meta("_loot_fx")

## Daño final de un golpe del jugador a `enemy` (rasgos condicionales y cadena del Arriero).
static func outgoing(enemy: DungeonGoblin, amount: float) -> float:
	if amount <= 0.0 or _skip(enemy):
		return amount
	var eq := equipment_of(enemy)
	if eq == null:
		return amount
	var mult := 1.0
	var shown := ""
	for it in eq.active_items():
		var c := EquipmentDB.cond_of(it)
		if not c.is_empty() and cond_met(String(c["when"]), enemy, eq):
			mult += float(c["mult"])
			RunLog.proc("cond:" + String(it["cond"]))
			shown = String(c["name"])
	mult += eq.chain_bonus() + DungeonRun.perk_bonus(eq)
	if shown != "":
		_pop(enemy, shown.to_upper(), Color(1.0, 0.9, 0.4))
	return amount * mult

## ¿Se cumple la condición `when` de un rasgo contra este enemigo?
static func cond_met(when: String, enemy: DungeonGoblin, eq: PlayerEquipment) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	match when:
		"stunned": return enemy.state == DungeonGoblin.State.STUNNED
		"recovering": return enemy.state == DungeonGoblin.State.RECOVER
		"burning", "poisoned":
			var fx := StatusEffects.get_for(enemy)
			return fx != null and fx.has("burn" if when == "burning" else "poison")
		"chilled": return enemy.chill_mult() < 1.0
		"big": return enemy.elite != "" or enemy is DungeonNecromancer
		"full_hp": return enemy.hp >= enemy.max_hp - 0.01
		"low_hp": return enemy.hp < enemy.max_hp * 0.3
		"after_parry": return eq != null and now - eq.last_parry_t <= EquipmentDB.AFTER_PARRY_WINDOW
		"after_dodge": return eq != null and now - eq.last_dodge_t <= EquipmentDB.AFTER_DODGE_WINDOW
	return false

## Después de un golpe del jugador (llamada diferida: puede volver a dañar al enemigo sin reentrar en take_damage).
static func after_hit(enemy: DungeonGoblin, amount: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	var eq := equipment_of(enemy)
	if eq == null:
		return
	var weapon := eq.weapon_in_hand()
	var maker := String(weapon.get("maker", ""))
	var alive := not enemy.is_dead()
	var m := EquipmentDB.maker_of(weapon)
	match maker:
		"tatan":
			if alive:
				enemy.add_stun_fraction(float(m["stun"]))
				RunLog.proc("maker:tatan")
		"arriero":
			eq.add_chain()
			RunLog.proc("maker:arriero")
		"conquistador":
			if alive and not enemy is DungeonNecromancer and enemy.hp < enemy.max_hp * float(m["exec"]):
				_pop(enemy, "EJECUTADO", EquipmentDB.MAKER_COLOR)
				RunLog.proc("maker:conquistador")
				_fx_damage(enemy, enemy.hp + 1.0)
				alive = false
		"mohan":
			if alive and randf() < float(m["chance"]):
				var echo := amount * float(m["echo"])
				enemy.get_tree().create_timer(float(m["delay"])).timeout.connect(func():
					if is_instance_valid(enemy) and not enemy.is_dead():
						_pop(enemy, "ECO", Color(0.7, 0.5, 1.0))
						RunLog.proc("maker:mohan")
						_fx_damage(enemy, echo))
	if eq.cazador_armed and alive:
		eq.cazador_armed = false
		RunLog.proc("rule:cazador")
		enemy.add_stun_fraction(1.0)
	if alive and eq.has_rule("dragon"):
		var hits := int(enemy.get_meta("_dragon_hits", 0)) + 1
		enemy.set_meta("_dragon_hits", hits)
		if hits % DRAGON_EVERY == 0:
			_pop(enemy, "LLAMARADA", Color(1.0, 0.5, 0.15))
			RunLog.proc("rule:dragon")
			for e in _enemies_near(enemy, enemy.global_position, DRAGON_RADIUS, true):
				StatusEffects.apply_to(e, "burn", DRAGON_DPS, DRAGON_DUR, eq.player, eq.current_weapon())

## Una baja (DungeonEncounter, al morir cualquier enemigo de una caverna).
static func on_kill(dead: Node) -> void:
	if not (dead is DungeonGoblin) or not dead.is_inside_tree():
		return
	DungeonRun.on_kill()
	var eq := equipment_of(dead)
	if eq == null:
		return
	var res: Node = eq.player.get("resources")
	if eq.has_rule("hambre"):
		RunLog.proc("rule:hambre")
		var mc = eq.player.get("movement_controller")
		if mc:
			mc._dodge_cooldown_timer = 0.0
		if res:
			res.add_energy(PlayerResources.DODGE_COST)
	if eq.has_rule("corona") and (dead as DungeonGoblin).elite != "" and res:
		res.add_energy(res.energy_max())
		res.add_mana(res.mana_max())
		_pop(dead, "CORONA", EquipmentDB.RULE_COLOR)
		RunLog.proc("rule:corona")
	if eq.has_rule("obsidiana"):
		var pos: Vector3 = (dead as Node3D).global_position
		var hit := 0
		for e in _enemies_near(dead, pos, OBSIDIANA_RADIUS, false):
			_fx_damage(e, OBSIDIANA_DAMAGE)
			hit += 1
		if hit > 0:
			RunLog.proc("rule:obsidiana")
		if hit > 0 and eq.player.has_method("heal"):
			eq.player.heal(OBSIDIANA_HEAL * hit)
		var root := dead.get_tree().current_scene
		if root:
			NecroVFX.shockwave(root, pos + Vector3(0, 0.1, 0), OBSIDIANA_RADIUS, Color(0.7, 0.4, 1.0))

## Remate del jugador a `enemy` (DungeonGoblin.receive_finisher).
static func on_finisher(enemy: DungeonGoblin) -> void:
	var eq := equipment_of(enemy)
	if eq == null or not eq.has_rule("terremoto"):
		return
	RunLog.proc("rule:terremoto")
	var pos := enemy.global_position
	for e in _enemies_near(enemy, pos, TERREMOTO_RADIUS, false):
		e.add_stun_fraction(1.0)
	HitFeedback.shake(0.5)
	AudioManager.play_at("slam_boom", pos, 0.0, 0.9)
	var root := enemy.get_tree().current_scene
	if root:
		NecroVFX.shockwave(root, pos + Vector3(0, 0.1, 0), TERREMOTO_RADIUS, Color(1.0, 0.6, 0.2))

## Un enemigo quedó aturdido (regla "ancestral": suelta maná).
static func on_stunned(enemy: DungeonGoblin) -> void:
	if enemy.puppet:
		return
	var eq := equipment_of(enemy)
	if eq and eq.has_rule("ancestral") and enemy.get_parent():
		RunLog.proc("rule:ancestral")
		ResourcePickup.spawn(enemy.get_parent(), enemy.global_position + Vector3(0.5, 0, 0), ResourcePickup.Kind.MANA)

## La esquiva del jugador (regla "cazador": esquivar un ataque en curso cerca ralentiza y arma un golpe que aturde).
static func on_dodge(eq: PlayerEquipment) -> void:
	if not eq.has_rule("cazador") or not (eq.player is Node3D):
		return
	var pos: Vector3 = (eq.player as Node3D).global_position
	for e in eq.player.get_tree().get_nodes_in_group("enemies"):
		if e is DungeonGoblin and not e.is_dead() and e.global_position.distance_to(pos) <= CAZADOR_RADIUS \
				and (e.state == DungeonGoblin.State.WINDUP or e.state == DungeonGoblin.State.ATTACK):
			eq.cazador_armed = true
			HitFeedback.slowmo(CAZADOR_SLOWMO, 0.35)
			return

## Regla "ancestral": los élites sueltan una pieza más.
static func extra_elite_drops(node: Node) -> int:
	var eq := equipment_of(node)
	return 1 if eq and eq.has_rule("ancestral") else 0

# ───────────────────────────── Utilidades ─────────────────────────────

## Daño de un efecto (eco, ejecución, onda): no vuelve a disparar rasgos.
static func _fx_damage(enemy: Node, amount: float) -> void:
	if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
		return
	enemy.set_meta("_loot_fx", true)
	enemy.take_damage(amount)
	if is_instance_valid(enemy):
		enemy.remove_meta("_loot_fx")

static func _enemies_near(from: Node, pos: Vector3, radius: float, include_self: bool) -> Array:
	var out: Array = []
	for e in from.get_tree().get_nodes_in_group("enemies"):
		if not (e is DungeonGoblin) or e.is_dead() or e.puppet or (e == from and not include_self):
			continue
		if (e as Node3D).global_position.distance_to(pos) <= radius:
			out.append(e)
	return out

static func _pop(enemy: Node, text: String, color: Color) -> void:
	if not enemy is Node3D or not enemy.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - int(enemy.get_meta("_loot_pop_ms", -10000)) < POP_COOLDOWN_MS:
		return
	enemy.set_meta("_loot_pop_ms", now)
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
	l.position = Vector3(0, 2.7, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 3.3, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
