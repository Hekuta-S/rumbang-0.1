class_name BossCreator extends EnemyCreator

## ConcreteCreator del Factory Method: produce el jefe estándar (Product: boss.tscn).

const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss.tscn")

func _create_product() -> Node3D:
	return BOSS_SCENE.instantiate() as Node3D
