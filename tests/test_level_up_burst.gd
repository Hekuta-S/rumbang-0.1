extends Node

## Estallido de subida de nivel (visible con el juego en pausa) y alcance vertical del cuerpo a cuerpo.

func _ready() -> void:
	print("--- TEST: LEVEL UP BURST + ALCANCE VERTICAL ---")
	assert(EnemyBehavior.can_reach_vertically(0.0, 0.5), "Golpea a quien salta un poco")
	assert(not EnemyBehavior.can_reach_vertically(0.0, 2.6), "No golpea a quien está en una plataforma alta")
	assert(EnemyBehavior.can_reach_vertically(5.0, 0.0), "Sí golpea hacia abajo")
	var host := Control.new()
	add_child(host)
	get_tree().paused = true
	var b := LevelUpBurst.play(host, "¡NIVEL!")
	for i in 5:
		await get_tree().process_frame
	assert(is_instance_valid(b) and b.is_visible_in_tree(), "El estallido aparece con el juego en pausa")
	assert(b._t > 0.0, "Se anima en pausa (t=%.3f)" % b._t)
	var layer := b.get_parent() as CanvasLayer
	assert(layer != null and layer.layer > 100, "El cartel va por encima de las cartas (capa 100)")
	await get_tree().create_timer(LevelUpBurst.LIFE + 0.3, true, false, true).timeout
	assert(not is_instance_valid(b), "Se limpia solo")
	var edges := LevelUpEdges.play(host)
	for i in 5:
		await get_tree().process_frame
	assert(is_instance_valid(edges) and edges.is_visible_in_tree() and edges._t > 0.0, "Los triángulos de borde aparecen y se animan en pausa")
	assert((edges.get_parent() as CanvasLayer).layer < 100, "Los triángulos quedan bajo las cartas, enmarcándolas")
	await get_tree().create_timer(LevelUpEdges.LIFE + 0.3, true, false, true).timeout
	assert(not is_instance_valid(edges), "Los triángulos se limpian solos")
	get_tree().paused = false
	print("ALL BURST CHECKS PASSED")
	get_tree().quit(0)
