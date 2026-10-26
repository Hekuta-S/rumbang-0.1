---
name: design-patterns
description: Aplicar, revisar o refactorizar con patrones de diseño (GoF y específicos de juegos) en GDScript/Godot 4. Úsalo cuando se pida un patrón (Factory, Builder, Singleton/Autoload, Facade, Observer/Signals, State, Strategy, Command, Object Pool, Component, Decorator), al refactorizar código acoplado o al revisar la arquitectura.
---

# Patrones de diseño en GDScript / Godot 4

## Flujo
1. Consulta `graphify-out/GRAPH_REPORT.md` (o `graphify query`) para ubicar dependencias antes de leer código.
2. Identifica el problema real (acoplamiento, duplicación, creación compleja, estados enredados). No apliques un patrón sin un dolor concreto.
3. Elige el patrón más simple que lo resuelva; reutiliza los que el proyecto ya tiene (Facade, Factory, Builder, Singleton).
4. Implementa en `scripts/` respetando la estructura (core, entities, objects, ui) y regenera el grafo: `python graphify-out/build_graph.py`.

## Guía rápida: problema → patrón → idioma Godot
| Problema | Patrón | En Godot |
|---|---|---|
| Creación variada de enemigos/objetos | **Factory** | `static func create(tipo) -> Node` con `preload` de escenas |
| Configuración con muchos parámetros | **Builder** | clase `RefCounted` con métodos encadenables que devuelven `self` y `build()` |
| Servicio global único | **Singleton** | Autoload (Project Settings); evitar abusar, preferir inyección |
| API simple sobre subsistemas | **Facade** | un nodo/clase que expone pocos métodos y oculta el resto |
| Comunicación desacoplada | **Observer** | `signal` + `connect`; bus de eventos como Autoload |
| Comportamiento según estado | **State** | nodos hijos por estado o `enum` + `match`; `StateMachine` con `change_state()` |
| Algoritmo intercambiable (IA, ataque) | **Strategy** | `Resource` o `RefCounted` con método común, asignado por `@export` |
| Acciones deshacibles/encoladas | **Command** | objetos con `execute()`/`undo()` |
| Muchas instancias efímeras (balas, enjambres) | **Object Pool** | arreglo de nodos inactivos; reciclar con `process_mode`/`visible` en vez de `queue_free` |
| Composición de capacidades | **Component** | nodos hijos (Health, Hitbox) en vez de herencia profunda |
| Añadir comportamiento dinámico | **Decorator** | envolver `Resource`/nodo, o modificadores de stats apilables |
| Datos pasivos compartidos | **Flyweight** | `Resource` (.tres) compartido entre instancias |

## Reglas
- Composición sobre herencia; "call down, signal up" (los padres llaman métodos de hijos, los hijos emiten señales).
- Tipado estático (`: int`, `-> void`, `class_name`) en todo código nuevo.
- Un patrón por archivo/responsabilidad; nombres que declaren el patrón (`EnemyFactory`, `WaveBuilder`).
- Rendimiento móvil: favorece pools y recursos compartidos; evita instanciar en `_process`.
- Al refactorizar, mantén el comportamiento: cambios pequeños y verificables, sin renombrar API pública sin revisar usos.

## Revisión de arquitectura
Al auditar, reporta: patrones presentes, anti-patrones (God object, Autoloads con demasiado estado, `get_node` con rutas largas, ciclos de import), y una recomendación priorizada con el archivo afectado.
