---
name: creational-patterns
description: Implementar los 5 patrones creacionales GoF (Abstract Factory, Builder, Factory Method, Prototype, Singleton) en GDScript/Godot 4 con roles de participantes explícitos y nombres que reflejen el rol. Úsalo para la Evaluación 3 de Patrones de Diseño o al resolver problemas de creación de objetos.
---

# Patrones creacionales GoF en GDScript

Regla de la entrega: seguir la **estructura de participantes GoF** (no solo el espíritu) y nombrar las clases por su rol (`EnemyFactory`, `WaveBuilder`). Antes de implementar, localiza el problema real en el código existente (`graphify query`), y guarda el código ANTES para la sustentación.

## Factory Method
Participantes: `Creator` (declara `create_product()`), `ConcreteCreator` (lo sobreescribe), `Product`, `ConcreteProduct`.
```gdscript
class_name EnemySpawner extends Node          # Creator
func create_enemy() -> Enemy: return null     # factory method
func spawn(parent: Node, pos: Vector3) -> void:
    var e := create_enemy(); parent.add_child(e); e.global_position = pos

class_name ZombieSpawner extends EnemySpawner # ConcreteCreator
func create_enemy() -> Enemy: return ZombieEnemy.new()  # ConcreteProduct
```
Usar cuando: el `match tipo:` de creación crece o el código cliente conoce clases concretas.

## Abstract Factory
Participantes: `AbstractFactory` (varios `create_*`), `ConcreteFactory` por familia, `AbstractProduct`s, `ConcreteProduct`s.
```gdscript
class_name BiomeFactory extends RefCounted    # AbstractFactory
func create_enemy() -> Enemy: return null
func create_pickup() -> Pickup: return null
class_name DesertBiomeFactory extends BiomeFactory   # ConcreteFactory
func create_enemy() -> Enemy: return ScorpionEnemy.new()
func create_pickup() -> Pickup: return WaterPickup.new()
```
Usar cuando: hay **familias** de objetos que deben ser coherentes (bioma, dificultad, tema).

## Builder
Participantes: `Builder` (pasos `set_*`), `ConcreteBuilder` (guarda estado, `get_result()`), `Director` (orden de pasos opcional), `Product`.
```gdscript
class_name WaveBuilder extends RefCounted
var _wave := Wave.new()
func with_enemy(kind: StringName, count: int) -> WaveBuilder: _wave.add(kind, count); return self
func with_delay(s: float) -> WaveBuilder: _wave.delay = s; return self
func build() -> Wave: return _wave
```
Usar cuando: constructores con muchos parámetros opcionales o configuración por pasos.

## Prototype
Participantes: `Prototype` (`clone()`), `ConcretePrototype`, `Client` (registro de prototipos).
```gdscript
class_name EnemyPrototype extends Enemy
func clone() -> EnemyPrototype:
    var c: EnemyPrototype = duplicate(); c.health = health; return c
```
En Godot: `Node.duplicate()` / `Resource.duplicate(true)` + un `PrototypeRegistry` (`Dictionary` nombre → prototipo). Usar cuando crear desde cero es caro o hay variantes preconfiguradas.

## Singleton
Participantes: `Singleton` con instancia única y acceso global. En Godot: **Autoload** (preferido) o `static var _instance`.
```gdscript
class_name GameConfig extends Node           # registrar como Autoload "GameConfig"
static var instance: GameConfig
func _enter_tree() -> void: instance = self
```
Justificar: estado verdaderamente global y único. Desventajas: acoplamiento oculto y pruebas difíciles.

## Checklist
- Mapear cada clase a un rol GoF en el informe.
- El proyecto debe seguir ejecutándose sin errores (probar en Godot).
- Registrar cada uno en el Control de Cambios (ver skill `patterns-delivery`).
