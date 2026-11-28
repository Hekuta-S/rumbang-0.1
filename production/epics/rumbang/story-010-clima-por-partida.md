# Story 010: Clima por partida, solo visual

> **Epic**: rumbang
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: [set by /dev-story when implementation begins]

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief MVP feature 9`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Features: clima por partida, solo visual; Avoid: que el clima gaste rendimiento innecesario; Build order de mapas vivos, paso 3):*

- [ ] Cada partida de Supervivencia sortea un clima: lluvia, niebla, polvo o despejado (por semilla, igual para todos los jugadores LAN).
- [ ] El clima usa un solo emisor de unas 300 partículas pegado a la cámara, más niebla y color del cielo por tween. No añade luces nuevas.
- [ ] El clima es solo visual: no cambia daño, elementos, visión de enemigos ni ninguna regla.
- [ ] En calidad baja el emisor se apaga solo (`scripts/core/quality.gd`); la niebla y el cielo siguen.
- [ ] Coste medido en el Mali-G57: menos de 0,5 ms por frame; se anota la medición en esta historia.
- [ ] El clima convive con el ciclo día/noche de Supervivencia (`DayNightCycle`) sin pelear por la niebla ni el cielo.
- [ ] Mantiene el estilo cómic con tinta (partículas como sprites con tinta, no puntos suaves).
- [ ] Sin clima (despejado), el juego se ve y rinde como hoy.

---

## Implementation Notes

- Usar `GPUParticles3D` con prewarm para el emisor único; es el caso reservado para sistemas de cientos de partículas.
- Trampa conocida: los errores de compilación de shaders solo se ven en una ejecución con ventana.
- Trampa conocida: emisión en modo ADD lava los colores (ver notas de legibilidad y día/noche).
- Pensar la API para que la fase siguiente pueda leer el clima activo, aunque ahora no lo use nadie.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 008: el mapa grande.
- Story 009: huellas del jugador.
- Efectos del clima en el juego (lluvia que debilita el fuego, niebla que acorta la vista): fuera de alcance del brief.

---

## Files

- `scripts/world/map_ambience.gd` o un `scripts/world/map_weather.gd` nuevo
- `scripts/world/game_start_facade.gd` (`_setup_map_life`)
- `scripts/core/quality.gd`
- [test path: ninguno; tests waived at qa.level minimal]

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

*Governed by `qa.level`: at `qa.level: minimal` tests are **waived** (advisory), but a Visual/Feel story's retained screenshot is not.*

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot of each weather in `production/qa/evidence/` + sign-off in `production/qa/evidence/clima-por-partida-evidence.md`

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-008-mapa-grande-barrio-desague.md`
- Unlocks: None
