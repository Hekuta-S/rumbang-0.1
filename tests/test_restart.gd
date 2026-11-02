extends Node

## Reintentar: tras morir (con el jefe vivo) la escena se recarga limpia: jugador con vida y capaz de morir
## otra vez, sin jefe ni enemigos de la partida anterior y mazmorra en el nivel 1.

var _first: Node
var _done := false

func _ready() -> void:
	print("--- TEST: REINTENTAR ---")
	GameData.game_mode = "dungeon"
	_first = (load("res://scenes/core/main_dungeon.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_first)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _first
	await get_tree().create_timer(2.0).timeout
	var p = _first.get_node("Player")
	# Estado "sucio": jefe vivo, otro nivel, jugador muerto
	var enc := _first.get_node("DungeonEncounter") as DungeonEncounter
	var boss := DungeonNecromancer.new()
	boss.map = enc.map
	_first.add_child(boss)
	boss.global_position = p.global_position + Vector3(8, 0, 0)
	enc.level = 4
	p.health_comp.take_damage(100000.0)
	await get_tree().create_timer(2.0).timeout
	assert(p.is_playing_death_scan, "El jugador murió")
	var main = _first
	main.facade.restart_pressed.emit()
	await get_tree().create_timer(3.0).timeout
	var cur := get_tree().current_scene
	assert(cur != _first, "La escena se recargó")
	var p2 = cur.get_node("Player")
	assert(not p2.is_playing_death_scan, "El jugador nuevo no está en estado de muerte")
	assert(p2.hp == p2.max_hp and p2.hp > 0.0, "Vida completa (%.0f/%.0f)" % [p2.hp, p2.max_hp])
	var enemies := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.is_inside_tree() and not e.is_queued_for_deletion())
	assert(enemies.is_empty(), "No quedan enemigos ni jefe (%d)" % enemies.size())
	assert((cur.get_node("DungeonEncounter") as DungeonEncounter).level == 1, "Vuelve al nivel 1")
	# Puede volver a morir
	p2.health_comp.invincibility_time = 0.0
	p2.health_comp.take_damage(100000.0)
	await get_tree().create_timer(1.5).timeout
	assert(p2.is_playing_death_scan, "Puede volver a morir (no es inmortal)")
	print("ALL RESTART CHECKS PASSED")
	get_tree().quit(0)
