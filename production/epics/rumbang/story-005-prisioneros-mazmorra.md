# Story 005: Prisioneros de mazmorra que desbloquean el salón

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-22 (implementada; pendiente playtest)

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

- [x] Cada mundo de mazmorra (Cavernas, Cloacas) genera un prisionero en una sala cerrada (puerta enrejada o jaula).
- [x] La sala se abre al cumplir una condición simple (limpiar la sala o encontrar una llave); Decidido (usuario): limpiar la sala.
- [x] Al liberarlo, el prisionero cuenta una frase de historia sobre el jefe del mundo.
- [x] El prisionero liberado se guarda en el save y se muda al salón como NPC visible.
- [x] Cada prisionero desbloquea una estación del salón. Decidido (usuario): El Minero (Cavernas, modelo garri) abre el cofre de mejoras; La Ladrona (Cloacas, modelo joel) abre la pestaña NIVEL del yunque.
- [x] Una estación bloqueada se ve apagada y muestra qué prisionero la desbloquea.
- [x] El prisionero de un mundo no reaparece una vez liberado.
- [x] Si no se libera, vuelve a aparecer en la siguiente partida de ese mundo.
- [x] Los prisioneros existen solo con `mago_rescatado` en `true` (Mazmorra ya desbloqueada).
- [ ] Funciona en LAN: el host guarda el estado del prisionero. (NO hecho: como el pergamino y los dados, el prisionero solo sale en partidas locales, `structure_enabled()`.)

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

- `scripts/objects/dungeon_prisoner.gd` (nuevo: jaula, modelo, unlock al limpiar, liberar con E, frases, se va)
- `scripts/world/world_defs.gd` (clave `prisoner` por mundo)
- `scripts/world/dungeon_encounter.gd` (`_place_prisoner`, `prisoner_room`; los dados no caen en su sala)
- `scripts/world/dungeon_shop.gd` (`make_npc(char_id)`, respaldo de escala por la caja de la malla: Garri medía 1 cm)
- `scripts/core/save_manager.gd` (`prisoners`, `prisoner_free()`, `free_prisoner()`; save viejo sin clave = todos libres)
- `scripts/ui/dungeon_hub.gd` (`station_locked()` general, `prisoner_world_for()`, `locked_hint()`, NPCs liberados en `PRISONER_SPOTS`)
- `scripts/ui/hub_panels.gd` (pestaña NIVEL con aviso mientras falte la ladrona)
- `tests/test_dungeon_prisoner.gd` / `.tscn`, `tests/shot_dungeon_prisoner.gd` / `.tscn`

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
