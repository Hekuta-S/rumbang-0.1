# Story 003: Intro nueva: el mago es raptado

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-22 (implementada; pendiente playtest)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief MVP feature 1`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (First minute, Features item 1):*

- [x] La intro dura unos 24 s o menos y se muestra una sola vez, en el primer arranque.
- [x] El rey y el mago invocan al héroe (conserva la secuencia actual de invocación).
- [x] El Nigromante irrumpe y se lleva al mago; el rey queda en escena.
- [x] Hay subtítulos legibles para cada frase.
- [x] El jugador puede saltar la intro con una tecla o toque.
- [x] Al terminar o saltarla, pasa al tutorial del patio (Story 004).
- [x] El flag de "intro vista" se guarda y la intro no se repite (se puede repetir con `force_intro`).
- [x] La intro corre sin errores en móvil y en escritorio.

---

## Implementation Notes

- La intro de la memoria `dungeon-hub-intro` usa `DungeonHub.force_intro`, `Murmur` para voces y `user://dungeon_hub.cfg`. El tutorial actual tiene `scripts/world/tutorial_cinematic.gd`.
- Rey y mago: modelo riva-base; los clips se hornean con `tools/blender_salon_invocacion.py`. El Nigromante necesita un clip de entrada (reutiliza el modelo de jefe si existe).
- Decidir si la intro vive en el salón o en el patio; la versión actual del rey solo aparece en el patio.

---

## Out of Scope

- Story 004: el tutorial.
- Voces reales o doblaje (Out of scope del brief).

---

## Files

- `scripts/world/tutorial_cinematic.gd` (guion nuevo, `NECRO_AT`/`GRAB_AT`/`VANISH_AT`, `apply_kidnap_end()`)
- `scripts/world/tutorial_patio.gd` (orador "necro", OUTRO sin el mago, saltar = mago raptado)
- `scripts/core/murmur.gd` (voz "necro")
- `tests/test_tutorial.gd` (CHECK 3a), `tests/shot_patio.gd` (capturas del rapto)
- Decisión: la intro vive en el patio (TutorialCinematic); la del salón (`force_intro`) queda solo para repetir y no tiene el rapto. Sin clip nuevo: se reutiliza el FBX del Nigromante (idle + invocar).

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: capturas retenidas en `production/qa/evidence/` y firma en `production/qa/evidence/story-003-intro-mago-raptado-evidence.md`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: `production/epics/rumbang/story-004-tutorial-reajustado.md`
