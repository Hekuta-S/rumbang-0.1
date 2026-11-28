# Story 009: Huellas del jugador

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
**Requirement**: `Brief MVP feature 8`

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot (version unset) | **Risk**: NOT ASSESSED (no VERSION.md risk rating)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From `design/game-brief.md` (Features: huellas del jugador; Build order de mapas vivos, paso 2):*

- [x] Las compuertas del Barrio del Desagüe se pueden romper: inundan o vacían un canal, y el cambio se ve y afecta al movimiento (agua que frena, canal seco que se cruza).
  - Cada desagüe empieza seco tras su compuerta. Al romperla, el agua lo llena en 1,4 s con una ola que daña y empuja hacia el acantilado a los enemigos de dentro: una trampa.
- [x] Al menos una tubería rota y un tipo de muro de ladrillo rompible abren un atajo nuevo; el enrutado de enemigos (`EnemyMotion`) se actualiza y no se atasca.
  - Hay 2 tuberías gigantes atravesadas en la calle de dentro y 2 muros de ladrillo en la de fuera. Al romperlos se quitan su colisión y su obstáculo (`EnemyMotion.remove_obstacles_near`, que también actualiza el C++).
- [x] Cráteres y manchas de tinta quedan en el suelo durante toda la partida, con un tope fijo de instancias (memoria acotada); al llegar al tope se reciclan las más antiguas.
- [x] Las zonas o salas limpiadas cambian de aspecto (por ejemplo antorchas apagadas); al menos un cambio visible.
  - Interpretación: en Supervivencia no hay salas. Las zonas donde se pelea se llenan de manchas de tinta (35 % de las muertes, sin amontonarse) y de cráteres, y los árboles quedan talados.
- [ ] Las huellas no cuestan rendimiento apreciable: una sola MultiMesh o decal pool, medido en el Mali-G57 (60 FPS de meta).
  - Diseño barato: todas las marcas van en 1 MultiMesh (128 como tope) y los árboles en una MultiMesh por trozo de 80 m. Los cuerpos de los árboles se crean solo a menos de 45 m del jugador. Pendiente de medir en el móvil, que no estaba conectado.
- [x] En LAN, las huellas se replican a los clientes o, si no se pueden replicar, se limitan a efectos visuales locales sin romper el enrutado (anotar la decisión en esta historia).
  - Decisión: el multijugador LAN solo existe en la Mazmorra (NetWorld); Supervivencia no es online. No hay nada que replicar. Si algún día lo es, habría que enviar las roturas desde el anfitrión.
- [x] Sin romper nada, el mapa funciona como hoy.

---

## Implementation Notes

- Apoyarse en `map_reactions.gd` (pulsos y uniforms globales) y en los barriles explosivos ya existentes como fuente de daño de área.
- Trampa conocida: `(dict[k] as PackedVector3Array).append()` añade a una copia.
- Las huellas viven solo durante la partida; no se guardan en el save.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 008: el mapa grande y el Barrio del Desagüe.
- Story 010: el clima.
- Mutaciones programadas y colapso de mazmorra: no elegidos en el brainstorm.

---

## Extra (pedido el 2026-11-23): árboles 2D horneados y destructibles

- `tools/make_map_sprites.py` dibuja con el lienzo entintado de los iconos:
  - `assets/textures/toon/props/arboles.png`: 4 variantes × (entero, tocón, parte de arriba).
  - `assets/textures/toon/fx/marcas.png`: 2 cráteres y 2 manchas de tinta.
  - Las dos texturas se importan comprimidas en VRAM y con mipmaps.
- `TreeField` sustituye los modelos 3D `tree_dead_*` en Supervivencia (y en el fondo del menú):
  - Los árboles son sprites con billboard vertical, con variante y espejo fijos por posición.
  - Cada árbol tiene un cuerpo `TreeTrunk` en el grupo `destructibles`, así que los golpean tajos, balas, flechas y explosiones.
  - Al golpearlo tiembla. Al romperlo (55 de vida), la parte de arriba cae de lado y queda el tocón, que sigue estorbando. Los obstáculos de los enemigos no cambian.
  - Al caer un árbol se espantan los cuervos.

## Files

- Nuevos:
  - `scripts/world/tree_field.gd`, `tree_trunk.gd`, `spatial_prop_tree_sprite.gdshader`
  - `scripts/world/map_marks.gd`, `spatial_fx_map_mark.gdshader`
  - `scripts/world/sewer_breakable.gd`
  - `tools/make_map_sprites.py`
- `scripts/world/sewer_district.gd`: compuertas, tuberías de través, muros de ladrillo, inundación con ola, desagües secos (`wet`).
- `scripts/world/procedural_map.gd`: `tree_sprites`, `TREE_KINDS`, `_build_trees()`; los árboles ya no van en `Props` ni en `PropColliders`.
- `scripts/core/enemy_motion.gd`: `remove_obstacles_near()`.
- Cráteres:
  - `scripts/objects/explosive_barrel.gd`: además, ahora daña lo rompible que tiene alrededor.
  - `scripts/components/player_movement_controller.gd` (golpe de caída).
  - `scripts/objects/giant_mace_slam.gd`.
  - `scripts/objects/mortar_shell.gd`.
  - `scripts/components/weapon_strategy.gd` (explosión).
- `scripts/core/game_start_facade.gd`: crea `MapMarks`, le pasa las muertes y conecta los árboles con los cuervos.
- `tests/test_player_marks.tscn` (12 comprobaciones), `tests/shot_district.tscn` (capturas nuevas: `_compuerta`, `_ola`, `_muro`, `_arboles`, `_talando`, `_talado`).
- `tests/test_ground_chunks.gd`: talla el barrio como el juego real y tolera 1 mm de diferencia entre `TerrainNative` y el GDScript.

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

- Depends on: `production/epics/rumbang/story-008-mapa-grande-barrio-desague.md`
- Unlocks: None
