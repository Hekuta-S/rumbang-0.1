# Story 004: Tutorial reajustado hacia Supervivencia

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: [set by /dev-story when implementation begins]

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

- [ ] El tutorial sigue enseñando mover, golpear, esquivar, parar y matar a un goblin.
- [ ] Al terminar (o saltarlo), el jugador llega al salón, no a un portal de mazmorra.
- [ ] Con `mago_rescatado` en `false`, los portales y el yunque del salón están apagados.
- [ ] La puerta de la arena (Supervivencia) está resaltada como único destino disponible.
- [ ] El rey explica en una frase corta que hay que salvar al mago en Supervivencia.
- [ ] El tutorial completo no pasa de unos 3 minutos y se puede saltar.
- [ ] `[tutorial] done` se sigue guardando y no se repite.
- [ ] Los jugadores con save viejo no vuelven a ver el tutorial.

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

- `scripts/world/tutorial_patio.gd`
- `scripts/world/tutorial_director.gd`
- `scripts/ui/dungeon_hub.gd`
- `tests/test_tutorial.gd` (ampliar; opcional)

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
