# Story 002: Jaula del mago en Supervivencia

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

- [ ] En Supervivencia, con `mago_rescatado` en `false`, aparece una jaula con el mago en el minuto 4 de la partida.
- [ ] La jaula está custodiada por una oleada élite.
- [ ] El jugador debe resistir unos segundos dentro de un radio de la jaula para abrirla, con barra de progreso visible.
- [ ] Al abrirse, el mago queda libre, `mago_rescatado` pasa a `true` y se guarda (Story 001).
- [ ] Si el jugador muere antes de abrirla, la jaula reaparece en la siguiente partida.
- [ ] Con `mago_rescatado` en `true`, la jaula no aparece más.
- [ ] La jaula y la oleada no rompen el aviso ni el jefe Nigromante (7:10).
- [ ] El rescate se anuncia con un mensaje o diálogo corto del mago.
- [ ] El mago tiene indicador visible en el mapa o brújula mientras la jaula existe.

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

- `scripts/core/wave_manager.gd`
- `scripts/core/run_events.gd`
- `resources/wave_config.json`
- `scripts/objects/mage_cage.gd` (nuevo)
- `scenes/objects/mage_cage.tscn` (nuevo)

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
