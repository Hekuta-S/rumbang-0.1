# Story 006: Sinergia entre modos, versión mínima

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: S
> **Build step**: thin — sinergia entre modos
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-22 (implementada)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief Your systems: sinergia entre modos`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Intent: modos sin armas compartidas pero con sinergia entre ellos):*

- [x] Existe un solo vínculo entre modos, el más simple posible: un logro, recurso o desbloqueo ganado en un modo da una ventaja pequeña en el otro.
- [x] El vínculo concreto se elige y se anota en este story antes de implementarlo (el brief no lo define). Decidido (usuario): el vínculo es el que ya existía: élites y jefes de Supervivencia dan almas que suben el nivel del personaje de la Mazmorra (yunque, pestaña NIVEL). Faltaba el jefe: el Nigromante de Supervivencia no daba almas; ahora da `SoulStats.survival_boss_souls()` (580 a los 7:10).
- [x] La ventaja se guarda en el save y sobrevive a cerrar el juego.
- [x] La ventaja se muestra al jugador (texto en el salón o en el HUD).
- [x] Los dos modos siguen sin compartir armas.
- [x] Sin la ventaja, ambos modos funcionan como hoy.

---

## Implementation Notes

- Las historias 001 a 005 ya enlazan los modos por historia (mago y prisioneros). Esta historia añade una ventaja mecánica; puede apoyarse en `scripts/core/soul_stats.gd` o `scripts/core/save_manager.gd`.
- Posible mínimo: oro o almas ganados en Supervivencia aplican un bono pequeño inicial en Mazmorra.

---

## Out of Scope

- Story 007: la sinergia completa.

---

## Files

- `scripts/core/soul_stats.gd` (`survival_boss_souls()`)
- `scripts/core/run_events.gd` (`award_boss_souls()`, `_grant_souls()` común con los élites)
- `scripts/core/wave_manager.gd` (`_on_boss_died_internal` da las almas en Supervivencia)
- `tests/test_survival_merchant.gd` (check 2b)
- Visible: "+N ALMAS" sobre el jefe, la pantalla de fin ("sube de nivel en el yunque del Salón") y la pestaña NIVEL.

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: Test: waived at qa.level minimal

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-001-bloqueo-mazmorras-guardado.md`
- Unlocks: `production/epics/rumbang/story-007-sinergia-entre-modos-completa.md`
