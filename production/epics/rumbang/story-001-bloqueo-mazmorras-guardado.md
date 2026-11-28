# Story 001: Bloqueo de mazmorras guardado en el save

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

- [x] Una bandera persistente `mago_rescatado` vive en el save (`SaveManager`), con valor inicial `false`.
- [x] Con la bandera en `false`, los portales de mazmorra del salón no se abren y el mago no los conjura.
- [x] Con la bandera en `false`, Mazmorra no se puede iniciar desde el lobby ni por red (LAN).
- [x] Con la bandera en `false`, el jugador ve un mensaje claro de por qué está bloqueado y qué hacer (rescatar al mago en Supervivencia).
- [x] Con la bandera en `true`, el flujo actual de portales funciona sin cambios.
- [x] La bandera sobrevive a cerrar y reabrir el juego.
- [x] Supervivencia sigue jugable sin límite con la bandera en `false` (Avoid del brief).
- [x] Saves existentes sin la bandera cargan sin error, con el valor por defecto que se decida y se anote en el story Decidido: `true` para no bloquear a quien ya jugó; sin archivo de save = `false`.

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

- `scripts/core/save_manager.gd` (bandera `mago_rescatado`, `dungeon_unlocked()`, `set_mago_rescatado()`)
- `scripts/ui/dungeon_hub.gd` (mago oculto, rótulo y aviso, `open_portals` bloqueado)
- `scripts/ui/lobby_menu.gd` (botón "Mazmorra cerrada")
- `scripts/net/net_manager.gd` (`start_game` rechaza sin el mago, salvo servidor dedicado)
- `scripts/ui/main_menu.gd` (`_on_play_dungeon` bloqueado)
- `tests/test_dungeon_hub.gd` (CHECK 8a); `tests/net/test_net_game.gd`, `tests/net/test_net_idle.gd`, `tests/reel_shot.gd`, `tests/shot_dungeon_hub.gd` marcan al mago rescatado

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
