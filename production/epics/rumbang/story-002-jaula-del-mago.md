# Story 002: Jaula del mago en Supervivencia

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
**Requirement**: `Brief MVP feature 3`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Core loop historia, Goal & fail state, Features item 3):*

- [x] En Supervivencia, con `mago_rescatado` en `false`, aparece una jaula con el mago en el minuto 4 de la partida.
- [x] La jaula está custodiada por una oleada élite.
- [x] El jugador debe resistir unos segundos dentro de un radio de la jaula para abrirla, con barra de progreso visible.
- [x] Al abrirse, el mago queda libre, `mago_rescatado` pasa a `true` y se guarda (Story 001).
- [x] Si el jugador muere antes de abrirla, la jaula reaparece en la siguiente partida.
- [x] Con `mago_rescatado` en `true`, la jaula no aparece más.
- [x] La jaula y la oleada no rompen el aviso ni el jefe Nigromante (7:10).
- [x] El rescate se anuncia con un mensaje o diálogo corto del mago.
- [x] El mago tiene indicador visible en el mapa o brújula mientras la jaula existe. (Supervivencia no tiene minimapa: flecha en el borde de la pantalla con la distancia + columna de luz.)

---

## Implementation Notes

- Director de oleadas: `scripts/core/wave_manager.gd`, config en `resources/wave_config.json`. Eventos de partida: `scripts/core/run_events.gd`.
- Usar el modelo del mago ya existente del salón (`mago_idle`).
- Multijugador LAN: decidir si cualquier jugador puede abrir la jaula (propuesta: sí, y la bandera se guarda en el host).

---

## Out of Scope

- Story 001: guardado y bloqueo de la bandera.
- Story 003: la intro que rapta al mago.

---

## Files

- `scripts/objects/mage_cage.gd` (nuevo: jaula, mago, círculo, barra, flecha, rescate)
- `scripts/core/run_events.gd` (`CAGE_TIME` 240 s, `spawn_mage_cage()`: 2 élites + 8 goblins, emboscada de 10 al entrar)
- `scripts/ui/dungeon_hub.gd` (`DungeonHub.mage_look()` estático)
- `tests/test_mage_cage.gd` / `.tscn`, `tests/shot_mage_cage.gd` / `.tscn` (`-- <png> [behind]`)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: Test waived at qa.level minimal. Playtest de una partida completa.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-001-bloqueo-mazmorras-guardado.md`
- Unlocks: `production/epics/rumbang/story-004-tutorial-reajustado.md`, `production/epics/rumbang/story-005-prisioneros-mazmorra.md`
