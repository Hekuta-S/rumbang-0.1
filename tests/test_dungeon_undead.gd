extends Node

## Zombi y jefe necromántico de mazmorra, y panel de vida. Carga la mazmorra real.

var _player: CharacterBody3D
var _hp_lost := 0.0

func _ready() -> void:
	print("--- TEST: ZOMBI, NIGROMANTE Y PANEL DE VITALES ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	_player = enc.player
	# Que no muera durante la prueba (la pantalla de derrota pausa el árbol)
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Zombi: contrato y clips propios
	var z := enc.spawn_zombie()
	await get_tree().physics_frame
	assert(z is DungeonZombie and EnemyRegistry.all().has(z), "spawn_zombie crea un DungeonZombie registrado")
	assert(is_equal_approx(z.max_hp, 50.0), "Vida del zombi 50 (es %s)" % z.max_hp)
	for clip in DungeonZombie.ZOMBIE_CLIPS:
		assert(z._anim.has_animation(clip), "El zombi no cargó el clip %s" % clip)
	print("CHECK 1 PASSED: zombi, 50 de vida, 9 clips")

	# 2. Se levanta si no se le remata; un golpe en el suelo lo remata
	var died := [0]
	z.died.connect(func(_g): died[0] += 1)
	z.take_damage(60.0, Vector3.ZERO)
	assert(z.is_downed() and z.state == DungeonGoblin.State.DEAD, "La primera muerte lo deja en el suelo")
	assert(EnemyRegistry.all().has(z) and died[0] == 0, "En el suelo sigue siendo un blanco y no cuenta como muerto")
	for i in 60 * 4:
		await get_tree().physics_frame
	assert(not z.is_downed() and not z.is_dead(), "Tras 3 s se levanta")
	assert(is_equal_approx(z.hp, 25.0), "Se levanta con la mitad de vida (tiene %s)" % z.hp)
	print("CHECK 2a PASSED: se levanta con 25 de vida")
	z.take_damage(60.0, Vector3.ZERO)
	assert(z.is_dead() and died[0] == 1, "La segunda muerte es definitiva")
	var z2 := enc.spawn_zombie()
	await get_tree().physics_frame
	z2.take_damage(60.0, Vector3.ZERO)
	assert(z2.is_downed(), "Otro zombi cae al suelo")
	z2.take_damage(1.0, Vector3.ZERO)
	assert(z2.is_dead() and not EnemyRegistry.all().has(z2), "Un golpe en el suelo lo remata")
	print("CHECK 2b PASSED: segunda muerte definitiva y remate en el suelo")

	# 3. Jefe: contrato, barra, clips
	var n := enc.spawn_necromancer()
	await get_tree().physics_frame
	assert(n is DungeonNecromancer and n.is_in_group("boss"), "spawn_necromancer crea al jefe")
	assert(is_equal_approx(n.max_hp, 600.0), "Vida del jefe 600 (es %s)" % n.max_hp)
	for clip in DungeonNecromancer.NECRO_CLIPS:
		assert(n._anim.has_animation(clip), "El jefe no cargó el clip %s" % clip)
	assert(n._bar != null and n._bar.is_inside_tree(), "El jefe tiene barra de vida")
	print("CHECK 3 PASSED: jefe, 600 de vida, 11 clips y barra")

	# 4. Armadura: no se inmuta con golpes normales
	n._set_state(DungeonGoblin.State.APPROACH)
	n.take_damage(25.0, Vector3(0, 0, 5))
	assert(n.state == DungeonGoblin.State.APPROACH, "Un golpe de 25 no interrumpe al jefe")
	print("CHECK 4 PASSED: armadura del jefe")

	# 5. Cambio de fase: ruge, es inmune y empuja
	n.hp = n.max_hp * 0.67
	n.take_damage(10.0, Vector3.ZERO)
	assert(n.phase == 1, "Al bajar del 66 % pasa a la fase 2 (fase %d)" % n.phase)
	await get_tree().physics_frame
	assert(n._atk_name == "roar" and n.is_immune(), "Al cambiar de fase ruge y es inmune")
	var hp_before: float = n.hp
	n.take_damage(50.0, Vector3.ZERO)
	assert(n.hp == hp_before, "Mientras ruge no recibe daño")
	assert(is_equal_approx(n.windup_scale, 0.85), "En la fase 2 las anticipaciones son más cortas")
	for i in 60 * 2:
		await get_tree().physics_frame
	assert(not n.is_immune(), "Tras el rugido vuelve a recibir daño")
	print("CHECK 5 PASSED: fase 2, rugido inmune y anticipaciones más cortas")

	# 6. Erupciones: varios círculos alrededor del jugador
	_player.global_position = n.global_position + Vector3(6, 0.1, 0)
	n._set_state(DungeonGoblin.State.APPROACH)
	n._start_attack("eruption")
	var blasts := 0
	for i in 60 * 2:
		await get_tree().physics_frame
		var count := 0
		for o in n.get_parent().get_children():
			if o is GroundBlast:
				count += 1
		blasts = maxi(blasts, count)
	print("  erupciones simultáneas: %d (fase 2: hasta %d)" % [blasts, DungeonNecromancer.PHASE_ERUPTIONS[1]])
	assert(blasts >= 2, "Las erupciones deben ser varias a la vez")
	print("CHECK 6 PASSED: erupciones múltiples")

	# 7. Invocación: zombis que no se reaniman y caen con el jefe
	n._set_state(DungeonGoblin.State.APPROACH)
	n._start_attack("summon")
	for i in 60 * 3:
		await get_tree().physics_frame
	var summoned: int = n.summon_count()
	print("  zombis invocados: %d" % summoned)
	assert(summoned >= 2, "Debe invocar al menos 2 zombis")
	for s in n._summons:
		assert(not s.can_revive, "Los zombis invocados no se reaniman")
	var list: Array = n._summons.duplicate()
	n.hp = 1.0
	n._set_state(DungeonGoblin.State.APPROACH)
	n.take_damage(10.0, Vector3.ZERO)
	assert(n.is_dead(), "El jefe muere")
	for s in list:
		assert(not is_instance_valid(s) or s.is_dead(), "Sus zombis caen con él")
	print("CHECK 7 PASSED: invocación y muerte del jefe con sus zombis")

	# 8. Panel de vida
	var hud := get_tree().current_scene.find_child("HUD", true, false)
	var vitals: VitalsPanel = hud.vitals if hud else null
	assert(vitals != null and vitals.is_inside_tree(), "El HUD debe tener el panel de vitales")
	assert(not hud.stats_panel.visible, "Las barras verticales antiguas quedan ocultas")
	# El del HUD recibe la vida real del jugador: el resto se prueba con un panel aparte
	vitals = VitalsPanel.new()
	hud.add_child(vitals)
	await get_tree().process_frame
	vitals.set_values(20.0, 20.0)
	vitals.set_values(12.0, 20.0)
	assert(is_equal_approx(vitals.hp_ratio(), 0.6) and vitals.trail_ratio() > 0.99, "Al recibir daño el rastro se queda atrás")
	var acc := 0.0
	while acc < 0.9:   # pausa de 0,45 s y luego baja (tiempo de juego, no fotogramas)
		await get_tree().process_frame
		acc += get_process_delta_time()
	assert(vitals.trail_ratio() < 0.99, "El rastro baja después de la pausa")
	vitals.set_values(4.0, 20.0)
	assert(vitals.is_low(), "Con el 20 % de vida avisa de vida baja")
	print("CHECK 8 PASSED: panel de vitales (rastro y vida baja)")

	print("ALL UNDEAD CHECKS PASSED")
	get_tree().quit(0)
