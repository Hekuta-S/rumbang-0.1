# Story 004: Tutorial reajustado hacia Supervivencia

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-22 (implementada; pendiente playtest)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief MVP feature 2`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (First minute, Features item 2):*

- [x] El tutorial sigue enseñando mover, golpear, esquivar, parar y matar a un goblin.
- [x] Al terminar (o saltarlo), el jugador llega al salón, no a un portal de mazmorra.
- [x] Con `mago_rescatado` en `false`, los portales y el yunque del salón están apagados.
- [x] La puerta de la arena (Supervivencia) está resaltada como único destino disponible.
- [x] El rey explica en una frase corta que hay que salvar al mago en Supervivencia.
- [x] El tutorial completo no pasa de unos 3 minutos y se puede saltar.
- [x] `[tutorial] done` se sigue guardando y no se repite.
- [x] Los jugadores con save viejo no vuelven a ver el tutorial.

---

## Implementation Notes

- Archivos actuales: `scripts/world/tutorial_patio.gd`, `scripts/world/tutorial_director.gd`, `scenes/core/tutorial_patio.tscn`. Test: `tests/test_tutorial.tscn`.
- Estaciones del salón: `STATIONS` en `scripts/ui/dungeon_hub.gd:43`; la puerta de la arena es `STATIONS["arena"]`.
- Qué estaciones se apagan lo define Story 005 (prisioneros); aquí solo portales y yunque.

---

## Out of Scope

- Story 003: la intro.
- Story 005: desbloqueo de estaciones por prisioneros.

---

## Files

- `scripts/world/tutorial_patio.gd` (OUTRO: el rey pide rescatar al mago en la arena; hecho en la story 003)
- `scripts/ui/dungeon_hub.gd` (`station_locked()`: yunque apagado; rótulo de la arena "▼ ARENA: RESCATA AL MAGO ▼" late en dorado, más bajo y grande)
- `tests/test_dungeon_hub.gd` (CHECK 8a), `tests/shot_dungeon_hub.gd` (`-- <prefijo> raptado`)
- Sin cambios: pasos del tutorial, saltar, `[tutorial] done` y saves viejos ya funcionaban así.

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: Test waived at qa.level minimal. Playtest: primer arranque limpio hasta la puerta de la arena.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-001-bloqueo-mazmorras-guardado.md`, `production/epics/rumbang/story-003-intro-mago-raptado.md`
- Unlocks: None
