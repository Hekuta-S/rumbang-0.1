## Performance Profile v2: Supervivencia + Mazmorras (Android)
Generated: 2026-11-21 (después de los cambios del mismo día: resoluciones 1080p-540p, etiqueta FPS,
materiales de balas, preload). Comparar con `supervivencia-mazmorras-report-2026-11-21.md`.

Método: análisis estático (`/perf-profile`). No se ejecutó el juego ni se midió en el teléfono en esta pasada.
`performance.enforce: warn` (por defecto): las violaciones son hallazgos, no bloquean.

### Performance Budgets

`project.yaml` sigue sin `performance.*`. Presupuesto de frame tomado de la decisión del usuario
(2026-11-21, reporte v1): 60 FPS = 16.67 ms.

| Metric | Budget | Estimated Current | Status |
|--------|--------|-------------------|--------|
| Frame time (Baja, 420 enemigos) | 16.67 ms | ~22-24 ms (medido 2026-11-17, antes del suelo por trozos y de las resoluciones nuevas) | OVER, falta volver a medir |
| Frame time escena vacía (Baja) | 16.67 ms | 18.7 ms (medido 2026-11-17) | OVER, falta medir `r1`-`r5` |
| Memory | sin presupuesto | — | NOT ASSESSED — NO DATA |
| Load time | sin presupuesto | — | NOT ASSESSED — NO DATA |
| Draw calls | sin presupuesto | 69 sin enemigos (2026-11-16) + hasta 50 orbes de XP en Baja | NOT ASSESSED |

### Hotspots Identified

| # | Location | Issue | Estimated Impact | Fix Effort |
|---|----------|-------|------------------|------------|
| 1 | `scripts/core/loot_manager.gd:104`, `scripts/objects/xp_orb.gd` | Cada muerte instancia un orbe de XP y lo libera al recogerlo, sin pool. En Media/Alta cada orbe trae un `CSGSphere3D` (malla generada en CPU) y su propio `CPUParticles3D`; en Baja el CSG se crea y se borra al momento | Medio-alto con hordas (decenas de instancias por segundo) | M |
| 2 | Orbes de XP en Baja | Un `Sprite3D` transparente por orbe: hasta 50 dibujos ordenados por transparencia | Medio | M (MultiMesh) |
| 3 | `scripts/ui/resource_bars.gd:113` | `queue_redraw()` cada frame en mazmorra aunque nada cambie | Bajo | S |
| 4 | `scripts/ui/minimap.gd:146-147` | `_map_layer` y `_view` se redibujan cada frame (arcos, flecha, texto) | Bajo | S |
| 5 | `scripts/world/dungeon_encounter.gd` `_process` | `_pending.keys()` y `NetPlayers.alive()` por sala en cada frame | Bajo | S |
| 6 | `scripts/objects/foot_dust_vfx.gd:100` | Cada pisada crea `CPUParticles3D`, `Gradient` y `Curve` nuevos | Bajo (~3 por segundo) | S |
| 7 | `scripts/ui/equipment_hud.gd` `_process` | Con buffs activos reescribe un texto multilínea cada frame | Bajo | S |

Revisado y descartado: `FloatingVitals` está oculto en móvil (`hud.gd:97`); el minimapa está oculto en
Supervivencia (`minimap.gd:50`); `xp_orb` consulta al jugador cada 0.1 s; los materiales de las pisadas
están cacheados; `vitals_panel` ya no redibuja en reposo en móvil; `combo_counter` y `crosshair` solo
redibujan cuando cambian.

### Optimization Recommendations (Priority Order)

1. **Medir en el teléfono** el suelo por trozos y `r1`-`r5` contra nativa (`bench.txt`). Ningún cambio de
   código de esta lista baja de 18.7 ms la escena vacía. Risk: nulo.
2. **Pool de orbes de XP (#1)**
   - Location: `loot_manager.gd:95-108`, `xp_orb.gd`, `scenes/objects/xp_orb.tscn`
   - Expected gain: quitar una instanciación y un `queue_free` por muerte, y el CSG/partículas por orbe.
   - Risk: Medio (fusión de gemas por tope, magnetismo, grupo `xp_orbs` que usa `map_pickup.gd:191`).
   - Approach: reciclar orbes ocultos en vez de liberarlos; malla simple compartida en vez de `CSGSphere3D`.
3. **Orbes con MultiMesh (#2)** si el bench muestra que los dibujos transparentes pesan.
4. **Quick wins #3-#7.**

### Quick Wins (< 1 hour each)
- `resource_bars.gd`: redibujar solo cuando cambien el valor, el arma o el aviso de recurso.
- `minimap.gd`: redibujar la vista a ~15 Hz.
- `dungeon_encounter.gd`: comprobar las salas cada 0.1 s.
- `foot_dust_vfx.gd`: cachear `Gradient`/`Curve` por color.
- `equipment_hud.gd`: reescribir el texto de buffs a ~10 Hz.

### Requires Investigation
- Ganancia real de las resoluciones nuevas y del suelo por trozos en el móvil.
- Coste de los orbes de XP en una horda real (instancias por segundo, dibujos).
- Mazmorras en el dispositivo (fase 0 pendiente) y bug de la niebla.
- Memoria y tiempos de carga: sin presupuesto ni datos.

### Hecho (2026-11-21, sin medir en el móvil)
- #1: gemas de XP recicladas (`LootManager.recycle_xp_orb`, `XPOrb.deactivate/reactivate`); `CSGSphere3D`
  cambiado por `MeshInstance3D` "Body" con malla compartida. `tests/test_xp_orb_pool.tscn`.
- #3: `resource_bars.gd` redibuja solo si cambia lo que se ve (firma redondeada) o hay aviso; en escritorio nunca.
- #4: `minimap.gd` redibuja la vista a 20 Hz en móvil (siempre al ampliarse/encogerse).
- #5: `dungeon_encounter.gd` comprueba las salas pendientes cada 0.1 s.
- #6: `foot_dust_vfx.gd` cachea rampas y curvas (tope 32).
- #7: `equipment_hud.gd` reescribe el texto de buffs a 10 Hz (un buff nuevo sale al momento).
- Sin hacer: #2 (orbes con MultiMesh), pendiente de medir.

### Decisiones (Phase 5)
- #1 (M): **Implementar** (usuario, 2026-11-21), junto con los quick wins #3-#7.

Verdict: **COMPLETE** — performance profile generated.
