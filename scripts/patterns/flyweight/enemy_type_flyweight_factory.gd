class_name EnemyTypeFlyweightFactory extends RefCounted

## PATRÓN FLYWEIGHT (estructural) — rol: FlyweightFactory
## Entrega siempre el MISMO EnemyTypeFlyweight para un tipo dado (se crea la primera vez que se pide).
## Con cientos de enemigos en pantalla, solo existen 6 flyweights en memoria.
## Cliente: EnemyBehavior.apply_config() de cada tipo.

static var _pool: Dictionary = {}

static func get_flyweight(type: int) -> EnemyTypeFlyweight:
	if not _pool.has(type):
		_pool[type] = _create(type)
	return _pool[type]

## Nº de flyweights distintos creados (evidencia para la sustentación).
static func pool_size() -> int:
	return _pool.size()

static func _create(type: int) -> EnemyTypeFlyweight:
	match type:
		EnemyData.EnemyType.GOBLIN_RANGED:
			return EnemyTypeFlyweight.new(30.0, 2.0, 14.0, 2.0, 6)
		EnemyData.EnemyType.NORMAL_GOBLIN:
			return EnemyTypeFlyweight.new(40.0, 4.5, 1.0, 0.5, 8)
		EnemyData.EnemyType.HEAVY_BRUTE:
			return EnemyTypeFlyweight.new(90.0, 2.0, 1.4, 0.5, 15, Vector3(1.5, 1.5, 1.5))
		EnemyData.EnemyType.SNIPER_GOBLIN:
			return EnemyTypeFlyweight.new(45.0, 2.3, 9.0, 6.0, 20, Vector3(1.1, 1.25, 1.1))
		EnemyData.EnemyType.ZOMBIE_GOBLIN:
			return EnemyTypeFlyweight.new(25.0, 1.5, 1.2, 1.0, 3, Vector3(0.9, 0.9, 0.9))
		EnemyData.EnemyType.MORTAR_GOBLIN:
			return EnemyTypeFlyweight.new(35.0, 1.8, 30.0, 5.0, 14, Vector3(1.05, 1.1, 1.05))
	push_error("Tipo de enemigo sin flyweight: %d" % type)
	return EnemyTypeFlyweight.new(30.0, 2.0, 12.0, 2.0, 6)
