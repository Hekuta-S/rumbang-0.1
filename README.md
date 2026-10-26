# Local Keep AI for Godot 4

Local-first AI coding assistant for Godot 4 game development — explain GDScript,
generate state machines, write GUT tests, and run agentic tasks against 200+ free
models.

## Install

Not yet in the Godot Asset Library. Install manually:

```bash
git clone https://github.com/laynef/localkeep-godot
cp -r sage-godot/addons/local_keep_ai /path/to/your/project/addons/
```

Then enable it: **Project → Project Settings → Plugins → Local Keep AI → Enable**.

## Requires

Godot **4.x** and the sage CLI:

```bash
pip install local-keep-ai-cli
sage login
```

## Features

- **Local Keep AI dock**, bottom-right — chat, run tasks, view output
- **Project → Tools → Local Keep AI: Explain Script** — explains the script open in the editor
- **Project → Tools → Local Keep AI: Generate GUT Tests** — GUT tests for the current script
- **Project → Tools → Local Keep AI: List Models** — shows every available model

## Layout

```
addons/local_keep_ai/plugin.cfg      addon manifest (name, version, script entry point)
addons/local_keep_ai/plugin.gd       EditorPlugin — docks and Tools menu items
addons/local_keep_ai/lk_dock.tscn  dock scene
addons/local_keep_ai/lk_dock.gd    dock logic
addons/local_keep_ai/lk_client.gd  sage binary discovery + threaded OS.execute
```

The addon must stay at `addons/local_keep_ai/` — the Asset Library extracts archives
relative to the project root, and `plugin.gd` preloads
`res://addons/local_keep_ai/lk_dock.tscn` by absolute resource path.

## Notes

`lk_client.gd` runs `sage` on a `Thread` and marshals the result back with
`call_deferred`, so the editor stays responsive during long agentic tasks.

Publishing to the Asset Library requires an account there — see
[`../PUBLISH.md`](../PUBLISH.md) § 3.7.

## License

MIT — [localkeep.ai](https://localkeep.ai)
"# rumbang" 
"# rumbang-0.1" 
"# rumbang-0.1" 

## Historial de Refactorización y Control de Cambios

### Tarea 3 - Refactorización de Arquitectura (SOLID)

- **[CC-01] PlayerCombatController (SRP / OCP):** 
  - **Qué se cambió:** Se eliminaron los métodos gigantes `attack_*` y los bloques `match` dentro del `PlayerCombatController`. En su lugar, se implementó el **Patrón Strategy**. Se creó el archivo `weapon_strategy.gd` con una clase base `WeaponStrategy` y subclases para cada tipo de arma (ej: `EnergySwordStrategy`). 
  - **Por qué:** El controlador era un "God Object" que acoplaba toda la lógica de combate de todas las armas en un solo archivo, lo que volvía inviable el mantenimiento y violaba el Principio Abierto/Cerrado (OCP). Ahora, el controlador solo delega la ejecución (`_strategies[arma].attack()`), permitiendo agregar nuevas armas sin tocar su código.


### Tercera entrega - Patrones de diseño creacionales y estructurales

Tecnologías: Godot 4.7 (Forward Plus), GDScript. Ejecución: abrir la carpeta en Godot 4.7+ y pulsar F5 (escena principal `scenes/ui/main_menu.tscn`).
Documentación completa en [`docs/entrega3/`](docs/entrega3/): control de cambios (PE-01..PE-09), informe con código antes/después, diagramas UML y guion de sustentación.

| ID | Patrón | Tipo | Clases principales |
|----|--------|------|--------------------|
| PE-01 | Factory Method | Creacional | `EnemyCreator`, `BossCreator`, `NecromancerBossCreator` |
| PE-02 | Abstract Factory | Creacional | `PlatformFactory` + `Mobile/DesktopPlatformFactory` |
| PE-03 | Builder + Director | Creacional | `WeaponBuilder`, `WeaponDirector` |
| PE-04 | Prototype | Creacional | `WeaponData.clone()`, `WeaponPrototypeRegistry` |
| PE-05 | Singleton | Creacional | `GameState` (se elimina el duplicado `GameManagerSingleton`) |
| PE-06 | Decorator | Estructural | `DamageSource` + decoradores de daño (`Player._damage_chain`) |
| PE-07 | Flyweight | Estructural | `EnemyTypeFlyweight`, `EnemyTypeFlyweightFactory` |
| PE-08 | Adapter | Estructural | `MovementSource` + adaptadores táctil/teclado/mando |
| PE-09 | Facade | Estructural | `GameStartFacade` (existente) |

Además se corrigió `PoolManager` para no reutilizar balas aún en vuelo. El comportamiento del juego no cambia.
