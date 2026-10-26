class_name NecromancerBossCreator extends EnemyCreator

## ConcreteCreator del Factory Method: produce el Nigromante (Product: necromancer_boss.tscn).

const NECROMANCER_SCENE: PackedScene = preload("res://scenes/entities/necromancer_boss.tscn")

func _create_product() -> Node3D:
	return NECROMANCER_SCENE.instantiate() as Node3D
