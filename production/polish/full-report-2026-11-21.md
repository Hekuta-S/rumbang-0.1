## Performance Profile v3: Full (Rumbang)
Generated: 2026-11-21

Método: análisis estático (`/perf-profile full`) + datos medidos ya registrados en `OPTIMIZACION_MOVIL.md`.
No se ejecutó el juego ni se midió en el dispositivo en esta pasada. `performance.enforce: warn` (por defecto):
las violaciones son hallazgos, no bloquean. Compara con
`supervivencia-mazmorras-report-2026-11-21.md` (v1) y `...-v2.md`.

### Inputs

| Input | Estado |
|-------|--------|
| `performance.target_framerate / frame_budget_ms / draw_call_limit / memory_ceiling_mb` (config) | ABSENT, ninguno definido |
| Presupuesto de frame | Referencia de usuario en esta sesión: 60 FPS = 16.67 ms (no comprometida en config) |
| `OPTIMIZACION_MOVIL.md` (mediciones PC-móvil simulado y Mali-G57) | FOUND |
| Reportes v1 y v2 | FOUND |
| `bench.txt` / salida de profiler de esta pasada | ABSENT |
| Código `scripts/` (110 archivos con `_process`/`_physics_process`) | FOUND |

### Performance Budgets

Nota: los números medidos son de 2026-11-17 a 11-19; el suelo por trozos, las resoluciones 1080p-540p y el
pool de XP son posteriores y no se han medido en el móvil.

| Metric | Budget | Estimated Current | Status |
|--------|--------|-------------------|--------|
| Frame time, Baja, 420 enemigos (móvil) | 16.67 ms (ref. usuario) | ~22-24 ms (41-45 FPS sin tope) | OVER vs ref., falta remedir |
| Frame time, escena vacía (móvil, Baja) | 16.67 ms (ref. usuario) | 18.7 ms (~12 ms fijos del motor) | OVER vs ref., falta remedir |
| Memory | sin presupuesto | sin datos | NOT ASSESSED — NO DATA |
| Load time | sin presupuesto | sin datos | NOT ASSESSED — NO DATA |
| Draw calls | sin presupuesto | 69 en Supervivencia sin enemigos (11-16); +hasta 50 orbes XP en Baja | NOT ASSESSED — no budget |

Presupuesto no comprometido: fijarlo con `/project-settings performance.frame_budget_ms=16.67` (y los demás).
Hasta entonces los OVER de arriba son contra una referencia verbal, no contra config.

### Hotspots Identified

| # | Location | Issue | Estimated Impact | Fix Effort |
|---|----------|-------|------------------|------------|
| 1 | Coste fijo del motor en móvil (render Godot, copia final a 2460×1080, vsync) | ~12 ms de 18.7 ms con la escena vacía | Alto: domina el frame en gama baja | L |
| 2 | HUD en móvil (etiquetas con contorno, barra de armas) | ~3 ms medidos | Medio | M |
| 3 | Orbes de XP en Baja: un `Sprite3D` transparente por orbe | hasta 50 dibujos ordenados por transparencia | Medio, sin medir | M (MultiMesh) |
| 4 | Suelo en móvil | ~10 ms a escala 1.0 antes del troceado; troceado sin medir en móvil | Medio-alto, sin confirmar | S (solo medir) |
| 5 | `get_nodes_in_group` en `player_equipment.gd:286`, `loot_hits.gd:182,207`, `weapon_strategy.gd:950`, `map_pickup.gd:191` | Recorren grupos completos, pero solo por evento (nova, esquiva, explosión, imán) | Bajo; subiría con hordas en mazmorra | S |
| 6 | 66 `.instantiate()` en `scripts/` | Algunos en rutas de combate sin pool (el de XP ya tiene) | Bajo-medio, sin perfilar | M |

Revisado y descartado esta pasada: los grupos de `loot_manager.gd:22`, `run_events.gd:146`, `settings_menu.gd:325`
son puntuales (cambio de piso, ajustes). Los `queue_redraw()` de `scripts/ui` ya están limitados (v2).

### Optimization Recommendations (Priority Order)

1. **Remedir en el teléfono** (`bench.txt` con `420 20 u pc`, enchufado y cargado) tras suelo por trozos, resoluciones
   nuevas y pool de XP. Nada más se puede priorizar sin esto. Risk: nulo.
2. **Bajar el coste fijo del motor** (plan en `OPTIMIZACION_MOVIL.md`, sección "coste fijo"): es ~65 % del frame vacío.
   - Expected gain: no estimable sin medir; el techo es ~12 ms.
   - Risk: Medio.
3. **Orbes de XP con MultiMesh (#3)** solo si la remedición muestra dibujos transparentes pesados.
4. **Agrupar recorridos de grupos (#5)** en un índice (como `EnemyRegistry`) si aparecen picos en mazmorra.

### Quick Wins (< 1 hour each)
- Fijar los cuatro `performance.*` en config (sin esto no hay gate posible).
- Remedir `r1`-`r5` y el suelo por trozos con `tools/bench_render_phone.sh`.
- Cambiar `get_nodes_in_group("enemies")` por `EnemyRegistry` en `player_equipment.gd:286` (ya existe y evita el recorrido del árbol).

### Requires Investigation
- Memoria y tiempos de carga: sin presupuesto ni datos.
- Mazmorras en el dispositivo (fase 0 pendiente) y bug de la niebla.
- Ganancia real de resoluciones nuevas, suelo por trozos y pool de XP en el Mali-G57.
- Conflicto de objetivo: 60 FPS (16.67 ms) vs 30 FPS estables en gama baja-media (plan del brief). Decidir uno y comprometerlo.

### Deferred to Polish
Ninguno nuevo (el único ítem M/L abierto, #1 coste fijo, ya está en el plan de `OPTIMIZACION_MOVIL.md`).

Verdict: **COMPLETE** — performance profile generated.

### Decisiones (Phase 5)
- #1 coste fijo del motor (L): **Implementar** (usuario, 2026-11-21), tras remedir en el telefono. Añadir al orden de build del brief.

### Hecho (2026-11-21, sin medir en el móvil)
- #2 HUD: la tinta de la tira de armas y de los iconos se hornea una vez (`InkBake`) en vez de 14 lecturas de
  textura por píxel cada frame; fuera los 5 pases de `clip_children`. PC: mismo aspecto, 25 → 24 llamadas.
- #1 coste fijo: las instalaciones viejas guardaban `"resolution": 0` y nunca recibían la resolución reducida
  automática; ahora sin marca `res_v` se lee como automática. El resto del #1 (desglose con perfilador de GPU,
  renderer Compatibility) necesita el teléfono conectado.
- Tests: `test_settings_resolution_migration` (visto fallar antes del arreglo), `test_low_end_defaults`,
  `test_resolution_modes`, `test_hud_layout` y los de UI pasan. `test_settings_speed` (espalanza) y
  `test_equipment` (parry) fallan por causas de combate ajenas a este cambio.
