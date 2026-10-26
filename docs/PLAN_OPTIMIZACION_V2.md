# Plan de optimización v2 — evaluación de las 5 técnicas (PC y móvil)

Versión de Godot: **4.7** (renderer `mobile`). Los enemigos son `CharacterBody3D` con modelo FBX esquelético, `AnimationTree` y `move_and_slide()`. No usan NavMesh: persiguen en línea recta con una IA propia.

## 0. Hecho ahora: magos más raros y menos agresivos
- **Cadencia:** el mago pasó de disparar cada 1,6 s a cada **4,5 s**; el francotirador, de 2,0 s a **5,5 s** (`RANGED_COOLDOWN`, `SNIPER_COOLDOWN` en `enemy_behavior.gd`). No disparan nada más aparecer: el primer disparo llega tras un retraso aleatorio.
- **Tope global:** entre disparos de *cualquier* mago debe pasar al menos 0,4 s (`GLOBAL_SHOT_GAP_MS`). También limita las balas enemigas simultáneas.
- **Aparición:** en `wave_config.json` el mago (tipo 0) bajó de 30 %–12 % a **5 %–3 %**, y el francotirador (tipo 3) de 8 % a **0–1 %** (no aparece hasta el minuto 3). El peso liberado pasó a goblins normales y brutos (los brutos suben a 20–39 %, son lentos y cuerpo a cuerpo).

## 1. Qué hace cada técnica en ESTE proyecto

| # | Técnica | Estado actual | Veredicto | Impacto | Riesgo |
|---|---|---|---|---|---|
| 1 | **Pool de objetos** | Balas y números de daño ya tienen pool. Los enemigos usan `instantiate()` + `queue_free()` (hasta 220 vivos, ~6 por lote). | **Aplicar, pero un pool POR TIPO** de enemigo (así se conserva el modelo, el `AnimationTree` y el material; solo se reinician vida, estado, color y efectos). | Alto: quita los tirones al aparecer/morir | Medio |
| 2 | **MultiMesh** | Solo el mapa lo usa. | **No para los enemigos animados**: MultiMesh no dibuja mallas con esqueleto; haría falta hornear la animación en texturas (VAT), un trabajo grande. **Sí para**: balas enemigas, orbes de XP, partículas de suelo y *impostores* de enemigos muy lejanos. | Medio | Bajo (en objetos simples) |
| 3 | **Servidores (Physics/RenderingServer)** | Cada enemigo es un nodo pesado con colisión. | **Versión intermedia, no la reescritura total**: (a) cuerpos de enemigos lejanos pasan a movimiento "matemático" sin `move_and_slide` (el juego ya calcula la altura con `get_floor_y`); (b) separación entre enemigos con una rejilla espacial. Los servidores puros solo si, tras todo lo demás, se miden FPS bajos. | Alto | Alto (es la parte más invasiva) |
| 4 | **Física y navegación** | **No hay NavMesh** (nada que optimizar ahí). La IA ya se evalúa a 5 Hz y 1 de cada 3 frames lejos. Ticks de física: 60 (por defecto). | **Bajar a 40 ticks/s con interpolación de física** (`physics/common/physics_interpolation`, nativa en Godot 4.4+); en móvil se nota y el movimiento sigue suave. No bajar a 30: la cámara y los proyectiles se sentirían a saltos. | Medio | Bajo |
| 5 | **LOD y visibilidad** | `meshes/generate_lods=true` ya está activo en los FBX (LOD automático de Godot). Sin `VisibleOnScreenNotifier3D`. | **Aplicar**: notificador en el enemigo; fuera de pantalla se pausan `AnimationTree` y partículas y se salta el `look_at`. El LOD de mallas ya está. | Medio | Bajo |

## 2. Plan por fases (cada fase se prueba sola)

### Fase 1 — Gratis y seguro (PC + móvil)
1. **Visibilidad (técnica 5):** `VisibleOnScreenNotifier3D` en `enemy.tscn`; al salir de pantalla `anim_tree.active = false`, sin `_update_animation_state`, sin flash/partículas. Se reactiva al volver.
2. **Ticks a 40 + interpolación (técnica 4):** `physics/common/physics_ticks_per_second=40` y `physics/common/physics_interpolation=true`; revisar cámara y movimiento del jugador.
3. **Balas enemigas en MultiMesh (técnica 2, parte simple):** con el tope de 0,4 s ya hay pocas, así que esto es opcional; se deja para la fase 3.

### Fase 2 — Pool de enemigos por tipo (técnica 1)
1. `EnemyPool` (autoload o hijo de `WaveManager`) con listas por tipo y precalentado (5 de cada tipo en la carga, ya existe el precalentado de modelos).
2. `Enemy.reset_for_pool()`: hp/max_hp según el tipo, `is_alerted`, `slow_*`, `knockback_velocity`, `attack_cooldown`, color, escala y tweens pendientes.
3. Al morir: `hide()`, `process_mode = DISABLED`, quitar de `EnemyRegistry`, devolver al pool, **sin** `queue_free`. Al aparecer: sacar del pool, reubicar, `show()`, reactivar.
4. Cuidado: el escalado de vida por minuto debe reaplicarse en cada reutilización, y el Nigromante NO entra en el pool.

### Fase 3 — Movimiento ligero para lejanos y rejilla espacial (técnica 3, versión media)
1. Enemigos a más de ~28 m: movimiento sin `move_and_slide` (posición += dirección × velocidad, altura con `get_floor_y`); se reactiva la colisión real al acercarse.
2. Rejilla espacial (`SpatialHash`) para separar enemigos y para las consultas de armas/orbes, en vez de recorrer la lista completa.
3. MultiMesh para orbes de XP y balas enemigas.

### Fase 4 — Solo si aún hace falta
- Impostores (MultiMesh de siluetas) para enemigos a más de 40 m.
- Servidores puros de física/render para los enemigos básicos (la opción de "5.000 enemigos"); requiere reescribir la IA y los golpes de las armas, que hoy dependen de `Area3D`/`body_entered`.

## 3. Móvil vs PC
| Fase | PC | Móvil |
|---|---|---|
| 1 | Sí | Sí (la que más ayuda a gama baja) |
| 2 | Sí | Sí (menos tirones al aparecer) |
| 3 | Opcional | Sí (tope de enemigos 120 ya aplicado) |
| 4 | No necesaria | Solo si no se llega a 30 FPS en gama baja |

## 4. Honestidad sobre los números
Todavía **no hay mediciones**. Las "mejoras de impacto" son estimaciones por lectura de código. Recomiendo medir (FPS, ms de frame, nº de enemigos) antes y después de cada fase para confirmar que valen la pena, sobre todo la Fase 3.

## 5. Decisiones abiertas
- ¿Empiezo por la Fase 1 y 2 (las más seguras y con más efecto)?
- ¿Aceptas que los brutos (lentos, cuerpo a cuerpo) sean ahora la mayor parte de la horda mientras los magos son raros?
- ¿Bajamos a 40 ticks de física? Cambia levemente la sensación del movimiento.

## 6. Fase 4, etapa 1 — HECHA: enemigos con MultiMesh y animación horneada
- `tools/bake_enemy_vat.gd` hornea idle y caminar de los 4 modelos (magoblin, normal, bruto, zombie) en texturas dentro de `assets/vat/` (≈26 MB; idle a 8 fps y caminar a 15 fps, el shader interpola). Se vuelve a ejecutar con:
  `godot --headless --path . -s tools/bake_enemy_vat.gd` cada vez que cambie un modelo o animación de enemigo.
- `assets/shaders/enemy_vat.gdshader` + `scripts/core/enemy_visuals.gd`: una llamada de dibujo por modelo. Los enemigos siguen siendo `CharacterBody3D` (lógica y colisión) pero ya no llevan esqueleto, `AnimationTree` ni mallas propias.
- Si faltan los archivos de `assets/vat/`, el enemigo usa su modelo animado de siempre (`EnemyVisuals.is_available()`).
- Pendientes (etapas 2 y 3): lógica de enemigos como arrays (sin nodos) y migración de los golpes de las armas a la rejilla espacial.

## 7. Fase 4, etapa 2 (versión ligera) — HECHA: enemigos sin `move_and_slide`
- `scripts/core/enemy_motion.gd` mueve a los enemigos integrando la posición a mano: altura bilineal del mapa procedural, pendientes máximas (~50°), empuje fuera de los 289 props con colisión (cilindros y cajas orientadas, vía rejilla de obstáculos) y fuera del jugador. El `CharacterBody3D` sigue existiendo como objetivo de golpes; solo se mueve por asignación de posición.
- `ProceduralMap.get_colliders()` expone los colisionadores como datos 2D. Si no hay mapa procedural, el enemigo vuelve a `move_and_slide()`.
- Verificado: 40 de 40 enemigos colocados dentro de props salen fuera; la altura coincide con el suelo; la velocidad medida es 4,5 m/s (0,111 m por tick a 40 Hz).

## 8. Lo que NO se hizo y por qué (etapa 3: enemigos como datos puros)
Quitar el nodo `CharacterBody3D` de cada enemigo obliga a reescribir la detección de golpes de unas 20 armas y proyectiles (`body_entered`, rayos con máscara de enemigos, `is_in_group("enemies")`). Con el movimiento manual y el dibujo por MultiMesh ya hechos, el nodo restante cuesta poco (un cuerpo cinemático sin `move_and_slide`) y reescribir todo el combate sin poder probar cada arma a mano tiene más riesgo que beneficio. Se retoma solo si, al medir en el celular, aún no se llega a la meta.

## 9. Fase 4, etapa 3 — HECHA: enemigos como datos y golpes por geometría
(Sustituye a la sección 8: finalmente sí se migró.)
- **`EnemyData`** (`scripts/entities/enemy_data.gd`): el enemigo normal es un objeto ligero sin nodo (posición, vida, IA, estado). Expone la misma interfaz que el nodo anterior (`global_position`, `take_damage`, `apply_slow`, `apply_status`, `is_in_group`...), así que las armas no distinguen.
- **`EnemyManager`** (`scripts/core/enemy_manager.gd`): un único bucle de física para todos, y el pool por tipo. Cuelga del `WaveManager`.
- **`EnemyVisuals`**: dibuja desde los datos (interpolando entre ticks) y descarta los que están fuera de cámara.
- **`EnemyQuery`** (`scripts/core/enemy_query.gd`): `overlapping(area)`, `segment_hit(from, to)`, `any_overlapping`, `nearest`. Sustituye a `get_overlapping_bodies`, `body_entered` y a los rayos con máscara de enemigos. Migradas: melee/espada/lanza (hitbox), zona de radiación, nube de esporas, brazo bumerán, hacha giratoria, balas, serpientes, lanza espectral, esporas, polvos y combate automático.
- **Regla para armas nuevas:** para golpear enemigos NO usar física; usar `EnemyQuery`/`EnemyRegistry.query_radius`.
- Eliminados: `scripts/entities/enemy.gd`, `scenes/entities/enemy.tscn`, `scripts/core/enemy_pool.gd`.
- Los jefes (`boss.gd`, `necromancer_boss.gd`) siguen siendo nodos y entran en el mismo registro (con `hit_radius`/`hit_height`).
- Sin `assets/vat/` los enemigos se dibujan como cápsulas verdes (jugable pero feo): ejecutar `tools/bake_enemy_vat.gd`.
- Pruebas hechas (Godot headless): 11/11 armas por escena (daño al objetivo y 0 al lejano), 11/11 estrategias del jugador, veneno/lentitud, muerte y reutilización del pool, zombis del jefe, partida completa con jefe.
