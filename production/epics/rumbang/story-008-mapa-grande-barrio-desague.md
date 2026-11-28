# Story 008: Mapa de Supervivencia grande con el Barrio del Desagüe

> **Epic**: rumbang
> **Status**: In Progress (falta la medición en el móvil)
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-23 (implementada; sin medir en el Mali-G57)

## Context

**GDD**: `design/game-brief.md`
**Requirement**: `Brief MVP feature 7`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Features: mapa de Supervivencia más grande con el Barrio del Desagüe; Build order de mapas vivos, paso 1):*

- [x] El mapa de Supervivencia pasa de 230 m a 320 m de lado (`half_size` 115 → 160 en `scripts/world/procedural_map.gd`) y la partida sigue funcionando entera: oleadas, jaula del mago, Nigromante, minimapa, mesetas y rampas.
- [x] Una franja del borde es el Barrio del Desagüe: canales abiertos hundidos unos 1,5 m con agua sucia, pasarelas, puentes, rejillas y tuberías gigantes, hechos con las piezas de `SewerMap`.
- [x] El agua reutiliza las ondas de `map_reactions` y frena un poco al jugador que la pisa.
- [x] Los enemigos de enjambre cruzan los canales por los puentes (mismo enrutado que las rampas en `EnemyMotion`) y no se atascan ni caen al agua sin salida.
  - Cambio respecto al texto: el enrutado por rampas se quitó el 2026-11-15 a petición del usuario, así que no se añadió enrutado. Los enemigos van en línea recta: si el camino pasa por un puente lo cruzan por encima (capa de puente de `EnemyMotion`); si no, bajan al canal y trepan la otra pared despacio (`CLIMB_MULT`). Nunca quedan atrapados en el agua.
- [x] Los canales actúan de embudo para las hordas, sin dejar zonas inalcanzables para el jugador ni para sus objetivos (jaula, cofres, pickups).
- [x] El mapa se genera con semilla y es igual para los jugadores de una partida LAN.
- [ ] Medido en el Mali-G57 del usuario (bench.txt): el mapa grande mantiene la meta de 60 FPS en la calidad actual; si no, se anotan los ajustes (chunks, distancia de dibujo) en esta historia.
  - Pendiente: el móvil no estaba conectado (`adb devices` vacío) el 2026-11-23.
  - En PC (GTX 1050, 1280×720, portátil con batería al 44-55 %, 300 enemigos, 20 s), con 2 pasadas por variante, el resultado no es concluyente. Nuevo: 46,5 y 37,5 FPS (204 y 355 draws). Antes: 40,8 y 38,2 FPS (234 y 144 draws). Las llamadas de dibujo dependen mucho del mapa y de la cámara.
  - Generar el mapa en PC pasó de ~360 ms a ~420-460 ms. Antes de optimizar llegaba a 1,2 s.
- [x] Sin el barrio, el resto del mapa funciona como hoy.

---

## Implementation Notes

- Suelo ya troceado en chunks (11-19): comprobar que crecer el lado no multiplica draw calls.
- Heightfield: las mesetas, rampas y el enrutado tienen trampas conocidas (ver notas del proyecto sobre mesetas y rampas de Supervivencia).
- La simulación nativa C++ (`EnemySimNative`) usa los límites del mapa: revisarlos al crecer.
- Medir con el móvil enchufado y la batería cargada.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 009: destruir compuertas, tuberías y muros; cráteres y tinta persistentes.
- Story 010: el clima.
- Cloacas subterráneas bajo Supervivencia y unir Cavernas con Cloacas: fuera de alcance del brief.

---

## Files

- `scripts/world/sewer_district.gd` (nuevo, `SewerDistrict`): distribución, tallado del terreno (pasada sobre la malla de `TerrainNative` o del GDScript), agua, frenado, props, tuberías en MultiMesh, colisión.
- `scripts/world/procedural_map.gd`:
  - Tamaño: `half_size` 160, `play_half` 143, `district_enabled`, `is_water()`, `DISTRICT_PROPS`.
  - Escala de props y mesetas por área (`_area_k`).
  - Base de zigurat 18,5-20,5 y `CHUTE_MIN_DROP`: dos fallos latentes que el nuevo azar destapó.
  - `PropColliders` entra al árbol con las formas ya puestas: 127→12 ms.
  - Bosque: filtro de ruido antes de `_is_surface`.
  - `CHUNK_PC` 160 y `CHUNK_MOBILE` 320.
  - `max_lights` 24.
- `scripts/core/wave_manager.gd` (`PLAYABLE_*` ±140; `LootManager` y `RunEvents` los heredan).
- `scripts/core/run_events.gd` (la jaula del mago no aparece dentro de un canal).
- `scripts/world/map_ambience.gd` (cama `amb_sewer` en modo "canal" en Supervivencia).
- `scripts/ui/menu_background.gd` (el fondo del menú sigue con el mapa pequeño y sin barrio).
- `tests/test_survival_district.tscn` (12 comprobaciones), `tests/shot_district.tscn` (capturas, con ventana), `tests/test_survival_mesas.gd` (salta los puentes de canal).

Notas:
- `tests/test_jump_slam.tscn` falla el 2026-11-23 en "un salto normal no hace golpe de caída", también con el mapa pequeño. El goblin muere en el aire, en la plaza (3, 0, -3), que el barrio no toca. Ajeno a esta historia, sin investigar.
- En móvil (celdas de 2,5 m) los canales miden 3,5 m de hondo, en vez de 2,2 m, para que la pared siga siendo de más de 52°.

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

*Governed by `qa.level`: at `qa.level: minimal` tests are **waived** (advisory, never "must exist and pass").*

**Story Type**: Integration
**Required evidence**: Test: waived at qa.level minimal

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/rumbang/story-002-jaula-del-mago.md`
- Unlocks: `production/epics/rumbang/story-009-huellas-del-jugador.md`, `production/epics/rumbang/story-010-clima-por-partida.md`
