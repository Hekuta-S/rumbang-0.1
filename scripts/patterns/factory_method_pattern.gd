class_name EnemyFactory extends RefCounted

## FALENCIA DETECTADA EN EL PROYECTO (RESUELTA):
## Alto acoplamiento con las rutas de archivos. En scripts como main.gd o 
## wave_manager.gd, se hace preload("ruta").instantiate() directamente,
## atando la lógica de negocio a ubicaciones físicas y dificultando cambios.

## Factory Method
## Encapsula la lógica de creación de objetos. En lugar de hacer preload y new() 
## directamente en todo el código, el Factory Method centraliza la instanciación.

static func create_enemy(type: String) -> Node3D:
	var enemy_scene: PackedScene
	
	match type:
		"basic":
			enemy_scene = preload("res://scenes/entities/enemy.tscn")
		"boss":
			enemy_scene = preload("res://scenes/entities/boss.tscn")
		"necromancer":
			enemy_scene = preload("res://scenes/entities/necromancer_boss.tscn")
		_:
			push_error("Tipo de enemigo desconocido: " + type)
			return null
			
	var enemy_instance = enemy_scene.instantiate() as Node3D
	# Aquí se puede agregar configuración adicional en común para todos los enemigos
	enemy_instance.add_to_group("enemies_created_by_factory")
	return enemy_instance
