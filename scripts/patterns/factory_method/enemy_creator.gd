class_name EnemyCreator extends RefCounted

## PATRÓN FACTORY METHOD (creacional) — rol: Creator
## Problema previo: EnemyFactory.create_enemy(tipo) era un `match` sobre strings con preload de rutas;
## cada enemigo nuevo obligaba a modificar la fábrica (viola OCP).
## Ahora el Creator define la operación `create_enemy()` (plantilla) y delega la instanciación
## en el factory method `_create_product()`, que sobreescribe cada ConcreteCreator.

## Operación del Creator: usa el factory method y aplica la configuración común.
func create_enemy() -> Node3D:
	var enemy: Node3D = _create_product()
	if enemy == null:
		push_error("%s no pudo crear su producto" % get_script().get_global_name())
		return null
	_configure(enemy)
	return enemy

## FACTORY METHOD: lo sobreescriben los ConcreteCreator.
func _create_product() -> Node3D:
	return null

## Configuración común a todos los productos.
func _configure(enemy: Node3D) -> void:
	enemy.add_to_group("enemies_created_by_factory")
