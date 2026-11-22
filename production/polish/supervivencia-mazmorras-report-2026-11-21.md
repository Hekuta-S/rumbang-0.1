## Performance Profile: Supervivencia + Mazmorras (Android)
Generated: 2026-11-21 (commit 4c4feeb + cambios sin commitear)

Método: análisis estático del código (`/perf-profile`) más las mediciones previas en el
teléfono de pruebas (Black_3, Helio G99, Mali-G57 MC2, 2460×1080, calidad Baja guardada),
recogidas en `OPTIMIZACION_MOVIL.md`. No se ejecutó el juego en esta pasada.

`performance.enforce: warn` (por defecto): las violaciones son hallazgos, no bloquean.

### Performance Budgets

`project.yaml` no tiene presupuestos (`performance.*` vacío). Decisión del usuario 2026-11-21:
**objetivo 60 FPS en móvil (16.67 ms por frame)**. Aún no está escrito en `project.yaml`.

| Metric | Budget | Estimated Current | Status |
|--------|--------|-------------------|--------|
| Frame time (Baja, 420 enemigos, sin tope) | 16.67 ms (60 FPS, decisión 2026-11-21) | ~22-24 ms (41-45 FPS), medido 2026-11-17 | OVER |
| Frame time escena vacía (Baja) | 16.67 ms | 18.7 ms (~12 ms fijos de motor/copia/vsync) | OVER |
| Memory | sin presupuesto | — | NOT ASSESSED — NO DATA |
| Load time | sin presupuesto | regeneración de nivel ~150-200 ms en PC (bajo fundido) | NOT ASSESSED |
| Draw calls | sin presupuesto | 69 en supervivencia sin enemigos (tras atlas táctil) | NOT ASSESSED |

Nota: con 18.7 ms en escena vacía, 60 FPS no se alcanza recortando contenido en este teléfono.
Solo es posible si el coste fijo depende de la resolución (copia final a 2460×1080), y eso
está sin medir.

### Hotspots Identified

| # | Location | Issue | Estimated Impact | Fix Effort |
|---|----------|-------|------------------|------------|
| 1 | Motor: render, copia final a 2460×1080, vsync | ~12 ms fijos aunque la escena esté vacía | Alto: solo esto supera 16.67 ms | L |
| 2 | `scripts/ui/hud.gd:163` y HUD en general | HUD ~3 ms en el teléfono; la etiqueta de FPS con contorno se reescribe cada frame y siempre es visible | Medio (~0.3-1 ms) | S |
| 3 | `scripts/objects/bullet.gd:73`, `:134` | `setup()` de la bala (del pool) crea un `StandardMaterial3D` y duplica el material del rastro en cada disparo: basura por disparo y un material único por bala | Medio con muchos magos/francotiradores | S |
| 4 | Suelo de supervivencia en 64 trozos (`ProceduralMap.GROUND_CHUNK_CELLS`) | Antes ~10 ms a escala 1.0 en el teléfono; el cambio no se ha medido en el móvil | Posiblemente alto | — (medir) |
| 5 | `load()` en funciones: `weapon_strategy.gd:393`, `serpent_projectile.gd:82`, `spear_projectile.gd:179`, `boss.gd:148`, `necromancer_boss.gd:522`, `fate_dice.gd:119`, `:442` | Búsqueda en la caché de recursos en cada llamada | Bajo | S |
| 6 | `scripts/objects/toon_fx.gd` (`sheet_sprite`, `ring_material`; 55 llamadas) | `Sprite3D`/material nuevo por efecto, sin pool | Por confirmar | M |
| 7 | Mazmorra: `DungeonGoblin` `move_and_slide` | ~55 µs/goblin en PC (Jolt −45 %); 14 goblins ≈ 1.2 ms/tick | Bajo | — |
| 8 | `scripts/core/loot_hits.gd:207` | `_enemies_near` recorre el grupo `enemies` (solo mazmorra, pocos enemigos) | Bajo | S |

### Optimization Recommendations (Priority Order)

1. **Más opciones de resolución (decisión del usuario para #1)**
   - Location: `scripts/core/quality.gd:149-167` (`RES_NATIVE`, `RES_REDUCED`), `scripts/core/settings_manager.gd:17-18`, `:59-60`, selector en el menú de ajustes.
   - Ahora hay solo 2 modos (nativa / reducida). Propuesta: varias escalas de salida (p. ej. nativa, 1080p, 900p, 720p, 540p) para que el jugador elija y para que la gama baja arranque en la más baja.
   - Expected gain: desconocida hasta medir; ataca la copia final a 2460×1080, la parte del coste fijo que depende de la resolución.
   - Risk: Medio (UI pixelada o texto borroso a resoluciones bajas; guardado viejo con `"resolution": 0`).
   - Approach: primero medir `r1` contra nativa en el teléfono con `bench.txt` vacío y con 420 enemigos. Si baja ≥ 2 ms, añadir los modos; si no, el coste está en vsync/composición y la resolución no basta para 60 FPS.
2. **Medir el suelo por trozos en el teléfono (#4)**
   - Expected gain: hasta varios ms si el suelo seguía pesando en el móvil. Risk: nulo (solo medir).
3. **Desglose del coste fijo con perfilador de GPU (#1)**
   - Approach: escena vacía con Android GPU Inspector o Arm Performance Studio. Si es render de Godot, probar `gl_compatibility` solo en móvil (riesgo alto: auras, niebla, `fwidth`, `hint_screen_texture`).
4. **Cachear materiales de balas (#3)**
   - Approach: diccionario estático por color, como `CACHED_SPARK_MATS` (`bullet.gd:231`), para el material base y el del rastro.
5. **Pool o caché en ToonFX (#6)** si la medición muestra muchos efectos por segundo.

### Quick Wins (< 1 hour each)
- `hud.gd:163`: actualizar la etiqueta de FPS solo cuando cambie el valor y ocultarla fuera de debug.
- `bullet.gd:73`, `:134`: materiales cacheados por color.
- Cambiar los `load()` del hotspot #5 por `preload` en una const.

### Requires Investigation
- #1: de qué están hechos los ~12 ms fijos (render, copia final, vsync, composición).
- #4: ganancia real del suelo por trozos en el móvil.
- #6: número de `Sprite3D`/materiales que crea ToonFX por segundo en una horda de magos.
- Mazmorras en el dispositivo (fase 0 del plan de Android, pendiente).
- Bug de la niebla de mazmorra (a veces falta o sale a medias): sin reproducir.
- Memoria y tiempos de carga: sin presupuesto ni datos.

### Hecho (2026-11-21, sin medir en el móvil)
- Selector de resoluciones: Nativa, Reducida, 1080p, 900p, 720p, 540p (`Quality.RES_*`, `bench.txt` `r2`-`r5`).
- `hud.gd`: la etiqueta de FPS solo se reescribe cuando cambia el valor (ganancia pequeña: `Label` ya ignoraba el
  mismo texto; se ahorra el formateo por frame).
- `bullet.gd`: material del cuerpo, material y degradado del rastro y malla de partícula cacheados por color.
- `preload` en lugar de `load()` por golpe: `serpent_projectile.gd`, `spear_projectile.gd`, `boss.gd`,
  `necromancer_boss.gd`, `weapon_strategy.gd` (los de `fate_dice.gd` se quedan: solo corren al crear el dado).

### Decisiones (Phase 5)
- #1 (L): **Implementar.** Selector con más resoluciones y objetivo de 60 FPS (decisión del usuario 2026-11-21).

Verdict: **COMPLETE** — performance profile generated.
