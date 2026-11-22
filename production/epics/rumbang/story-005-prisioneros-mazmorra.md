# Story 005: Prisioneros de mazmorra que desbloquean el salón

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: [set by /dev-story when implementation begins]

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief MVP feature 5`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Core loop historia, Features item 5):*

- [ ] Cada mundo de mazmorra (Cavernas, Cloacas) genera un prisionero en una sala cerrada (puerta enrejada o jaula).
- [ ] La sala se abre al cumplir una condición simple (limpiar la sala o encontrar una llave); la condición queda anotada en el story al implementarse.
- [ ] Al liberarlo, el prisionero cuenta una frase de historia sobre el jefe del mundo.
- [ ] El prisionero liberado se guarda en el save y se muda al salón como NPC visible.
- [ ] Cada prisionero desbloquea una estación del salón. Propuesta: minero (Cavernas) abre el yunque de mejoras; ladrón (Cloacas) abre la tienda. Se confirma al implementar.
- [ ] Una estación bloqueada se ve apagada y muestra qué prisionero la desbloquea.
- [ ] El prisionero de un mundo no reaparece una vez liberado.
- [ ] Si no se libera, vuelve a aparecer en la siguiente partida de ese mundo.
- [ ] Los prisioneros existen solo con `mago_rescatado` en `true` (Mazmorra ya desbloqueada).
- [ ] Funciona en LAN: el host guarda el estado del prisionero.

---

## Implementation Notes

- Mundos y datos: `scripts/world/world_defs.gd` (añadir clave `prisoner`), `scripts/world/dungeon_map.gd`, `scripts/world/dungeon_encounter.gd`.
- Salas cerradas: reutilizar `scripts/world/dungeon_door.gd`.
- Estaciones del salón: `scripts/ui/dungeon_hub.gd`, `scripts/ui/hub_panels.gd`. Nuevo NPC = pieza Blender + modelo riva-base (ver memoria `dungeon-hub-intro`).
- Tienda Tatan: ver memoria `dungeon-equipment-system`.
- Primero construir el de Cavernas; el de Cloacas replica (Build order 3 y 4).

---

## Out of Scope

- Mercader errante, cronista del jefe, diálogos largos y voces (Out of scope del brief).
- Mago como guía por radio.

---

## Files

- `scripts/world/world_defs.gd`
- `scripts/world/dungeon_map.gd`
- `scripts/world/dungeon_encounter.gd`
- `scripts/ui/dungeon_hub.gd`
- `scripts/ui/hub_panels.gd`
- `scripts/core/save_manager.gd`
- `scripts/objects/prisoner.gd` (nuevo)
- `scenes/objects/prisoner.tscn` (nuevo)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: Test waived at qa.level minimal. Playtest: liberar uno, volver al salón y confirmar la estación.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-001-bloqueo-mazmorras-guardado.md`, `production/epics/rumbang/story-002-jaula-del-mago.md`
- Unlocks: None
