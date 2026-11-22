# Story 001: Bloqueo de mazmorras guardado en el save

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
**Requirement**: `Brief MVP feature 4`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Goal & fail state, Features item 4):*

- [ ] Una bandera persistente `mago_rescatado` vive en el save (`SaveManager`), con valor inicial `false`.
- [ ] Con la bandera en `false`, los portales de mazmorra del salón no se abren y el mago no los conjura.
- [ ] Con la bandera en `false`, Mazmorra no se puede iniciar desde el lobby ni por red (LAN).
- [ ] Con la bandera en `false`, el jugador ve un mensaje claro de por qué está bloqueado y qué hacer (rescatar al mago en Supervivencia).
- [ ] Con la bandera en `true`, el flujo actual de portales funciona sin cambios.
- [ ] La bandera sobrevive a cerrar y reabrir el juego.
- [ ] Supervivencia sigue jugable sin límite con la bandera en `false` (Avoid del brief).
- [ ] Saves existentes sin la bandera cargan sin error, con el valor por defecto que se decida y se anote en el story (propuesta: `true` para no bloquear a quien ya jugó).

---

## Implementation Notes

- `DungeonHub.portals_open` es una `static var` de sesión (`scripts/ui/dungeon_hub.gd:93`); la apertura está en `dungeon_hub.gd:780-804`. La bandera persistente debe controlarla, no reemplazarla.
- Guardado: `scripts/core/save_manager.gd`; datos de partida en `scripts/core/game_data.gd`.
- Tocar `Net._begin` si hay que rechazar Mazmorra en red (ver memoria de multijugador LAN).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: la jaula que pone la bandera en `true`.
- Story 004: el tutorial que deja los portales bloqueados al inicio.

---

## Files

- `scripts/core/save_manager.gd`
- `scripts/core/game_data.gd`
- `scripts/ui/dungeon_hub.gd`
- Pruebas: `tests/test_dungeon_hub.gd` (ampliar; opcional, `qa.level` minimal)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: Test waived at qa.level minimal. Un playtest breve basta (bloquear, rescatar, reabrir).

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: `production/epics/rumbang/story-002-jaula-del-mago.md`, `production/epics/rumbang/story-004-tutorial-reajustado.md`, `production/epics/rumbang/story-005-prisioneros-mazmorra.md`
