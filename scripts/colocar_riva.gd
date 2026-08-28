@tool
extends EditorScript

# Script para colocar a Riva (Player) en el mundo de forma automática

func _run():
	print("Colocando a Riva en el mapa...")
	
	var scene = get_editor_interface().get_edited_scene_root()
	if not scene or scene.name != "world":
		print("Por favor, abre la escena 'world.tscn' antes de ejecutar este script.")
		return
		
	# Verificar si ya existe Riva
	if scene.has_node("Player") or scene.has_node("Riva"):
		print("¡Riva ya está en la escena!")
		return
		
	var player_scene = load("res://scenes/entities/player.tscn")
	if not player_scene:
		print("Error: No se encontró la escena res://scenes/entities/player.tscn")
		return
		
	var player_instance = player_scene.instantiate()
	player_instance.name = "Player"
	
	# Posicionarlo en un lugar alto para que caiga sobre el terreno o no quede atrapado
	if player_instance is Node3D:
		player_instance.position = Vector3(0, 150, 0) # Lo ponemos arriba para que caiga
		
	scene.add_child(player_instance)
	player_instance.owner = scene
	
	print("¡Riva (Player) colocada con éxito en la posición (0, 150, 0)!")
