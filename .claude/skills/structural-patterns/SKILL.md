---
name: structural-patterns
description: Implementar patrones estructurales GoF (Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy) en GDScript/Godot 4 con roles de participantes explícitos. Úsalo para la Evaluación 3 (mínimo 3 estructurales) o al reorganizar la estructura de clases.
---

# Patrones estructurales GoF en GDScript

La entrega exige **mínimo 3 estructurales**. Facade ya existe en el proyecto; los candidatos naturales a añadir son Decorator, Flyweight, Composite, Adapter y Proxy. Elige solo donde resuelvan un problema real del código y documenta antes/después.

## Decorator
Participantes: `Component`, `ConcreteComponent`, `Decorator` (envuelve un Component), `ConcreteDecorator`.
```gdscript
class_name Weapon extends RefCounted              # Component
func damage() -> float: return 0.0
class_name PistolWeapon extends Weapon            # ConcreteComponent
func damage() -> float: return 10.0
class_name WeaponDecorator extends Weapon         # Decorator
var _inner: Weapon
func _init(w: Weapon) -> void: _inner = w
func damage() -> float: return _inner.damage()
class_name FireDamageDecorator extends WeaponDecorator  # ConcreteDecorator
func damage() -> float: return _inner.damage() + 5.0
```
Usar: mejoras/buffs apilables sin explosión de subclases.

## Flyweight
Participantes: `Flyweight` (estado intrínseco compartido), `FlyweightFactory` (caché), `Client` (estado extrínseco).
```gdscript
class_name EnemyTypeFlyweight extends Resource   # Flyweight (.tres compartido)
@export var mesh: Mesh; @export var max_health: float
class_name EnemyTypeFlyweightFactory extends RefCounted
static var _cache := {}
static func get_type(id: StringName) -> EnemyTypeFlyweight:
    if not _cache.has(id): _cache[id] = load("res://resources/enemies/%s.tres" % id)
    return _cache[id]
```
Usar: muchas instancias (enjambres) comparten mallas/materiales; encaja con la optimización móvil.

## Composite
Participantes: `Component`, `Leaf`, `Composite` (hijos + delegación).
```gdscript
class_name Skill extends RefCounted               # Component
func execute(ctx) -> void: pass
class_name SkillGroup extends Skill               # Composite
var _children: Array[Skill] = []
func add(s: Skill) -> void: _children.append(s)
func execute(ctx) -> void: for c in _children: c.execute(ctx)
```
Usar: jerarquías parte-todo (habilidades combinadas, menús, oleadas de oleadas).

## Adapter
Participantes: `Target`, `Adaptee`, `Adapter`, `Client`.
```gdscript
class_name InputAdapter extends InputSource       # Adapter hacia Target
var _touch: TouchControls                          # Adaptee
func get_move() -> Vector2: return _touch.joystick_vector()
```
Usar: unificar teclado/táctil/mando o envolver addons de terceros sin tocarlos.

## Proxy
Participantes: `Subject`, `RealSubject`, `Proxy` (mismo interfaz, controla acceso).
```gdscript
class_name TextureProxy extends TextureSource     # Proxy (carga perezosa)
var _real: Texture2D
func get_texture() -> Texture2D:
    if _real == null: _real = load(path)
    return _real
```
Usar: carga perezosa, caché, control de acceso, logging.

## Facade (ya presente)
Participantes: `Facade` + subsistemas. Revisar la existente y justificarla en el informe en lugar de duplicarla.

## Bridge
Participantes: `Abstraction`, `RefinedAbstraction`, `Implementor`, `ConcreteImplementor`. Usar para separar dos ejes de variación (p. ej. tipo de arma × tipo de proyectil).

## Checklist
- Mapear cada clase a un rol GoF; nombres con el rol (`FireDamageDecorator`).
- Reflejar en UML actualizado y en el Control de Cambios (skill `patterns-delivery`).
