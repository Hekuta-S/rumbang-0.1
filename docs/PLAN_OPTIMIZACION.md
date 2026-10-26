# Plan de optimización — Android y PC

Objetivo: FPS estables en la fase final (≈7 min, hasta 220 enemigos vivos + jefe + armas con muchos efectos). El juego ya usa el renderer `mobile`, MultiMesh en el mapa procedural, culling por oclusión, pool de balas y de números de daño, y caché de modelos/texturas/animaciones de enemigos; la base es buena. Los problemas están en lo que escala con la cantidad de enemigos y de efectos.

> Este plan sale de leer el código. **No hay mediciones todavía**: el primer paso (0) es medir, para no optimizar a ciegas.

## 0. Medir primero (1 sesión)
| Qué | Cómo |
|---|---|
| FPS/ms por fase de partida | Pantalla de depuración (tecla) con FPS, ms de frame, nº de enemigos vivos, draw calls, primitivas, memoria. Se registra al minuto 1, 3, 5 y 7. |
| Dónde se va el tiempo | Profiler de Godot (script vs física vs render). Hacerlo en PC y **en un Android de gama baja real**; los números de PC no se trasladan. |
| Picos vs caída sostenida | Diferenciar tirones (shaders compilando, instanciar escenas) de FPS bajos constantes: tienen causas distintas. |
| Escenarios de prueba | Los 9 personajes no hace falta: probar Saimon (orbes + muchos nodos), Vangry (lanzallamas), Tatan (nubes) y el jefe. |

## 1. Hallazgos por impacto estimado

### A. Alto — escalan con enemigos
1. **Orbes de Saimon: O(orbes × enemigos) cada frame** (`elemental_orbs.gd`, `_tick_contact_damage`). Con "Nuevo orbe" ilimitado y hasta 220 enemigos son miles de distancias por frame, y además crea un `String` por par (`"%d:%d"`) para el cooldown. Es la mayor amenaza porque crece por diseño.
2. **`get_nodes_in_group("enemies")` en bucles por frame**: lo llaman las armas (`weapon_strategy.gd` ×5), `player.gd`, espíritus de Joel, polvos, esporas, humo y el escudo. Cada llamada crea un Array nuevo de hasta 220 nodos. Hay ~19 sitios.
3. **Cada enemigo con IA, física y AnimationTree propios**: `CharacterBody3D` + `move_and_slide()` + `AnimationTree` + `look_at` por frame para ~200 enemigos. Es el coste base más grande en móvil.
4. **`xp_orb.gd`**: cada orbe llama `get_nodes_in_group("player")` y mide distancia en cada `_physics_process`. Con muchos orbes en el suelo suma.
5. **Spawn con coste**: cada enemigo nuevo hace `instantiate()` del modelo FBX, crea `StandardMaterial3D` y un `AnimationTree` (`enemy.gd` `_setup_model`/`_setup_animations`). A 6 enemigos por lote el tirón se nota.

### B. Medio — efectos y render
6. **Luces `OmniLight3D` dinámicas**: balas, lanzallamas, polvos, escudo, onda del jugador y ahora el aura del jefe. En el renderer `mobile` el número de luces por objeto es limitado y cada una cuesta; varias a la vez en móvil bajan FPS.
7. **Partículas (CPU) y estelas**: `CPUParticles3D` en armas, orbes (10 partículas **por orbe**), erupciones y el jefe; `RibbonTrail3D` recalcula mallas cada frame (hachas, lanza). Android sin GPU particles es más caro en CPU.
8. **Sombras y post-proceso**: en PC la luz direccional proyecta sombras hasta 80 m con glow, ajustes de color y niebla activos; en móvil ya están apagadas las sombras y el glow, pero la resolución está fija en 0.65 sin adaptarse.
9. **Shaders pesados**: `orbe_elemental.gdshader` hace `fbm`/ruido en `vertex()` y `fragment()` por orbe (hasta 4 octavas); fuego/nubes de esporas y polvos usan ruido volumétrico. El prewarm existe solo para esporas y polvos.
10. **Texturas grandes**: varias texturas de personajes/enemigos y el modelo del jefe pesan > 4 MB. En móvil cuestan memoria y ancho de banda (hay compresión ETC2/ASTC activa, falta revisar mipmaps y tamaños).

### C. Bajo / mantenimiento
11. Etiqueta de FPS creada siempre; `Label3D` de daño: se activan hasta 50 a la vez.
12. Archivos de ejemplo (`main_ready_god_method_ejemplo.gd`, patrones) no se cargan; sin impacto.

## 2. Acciones propuestas

### Fase 1 — Ganancias rápidas y seguras (código, bajo riesgo)
| # | Acción | Archivos |
|---|---|---|
| O1 | **Registro central de enemigos**: un único `EnemyRegistry` (autoload o dentro de `WaveManager`) con un array propio y actualización al nacer/morir; todas las armas lo consultan en vez de `get_nodes_in_group`. Evita crear Arrays por llamada. | `wave_manager.gd`, armas, espíritus, proyectiles |
| O2 | **Orbes: golpe por rejilla espacial** — consultar solo enemigos cercanos al jugador (radio de órbita + margen) y usar clave entera (`orb_idx * 1000003 + id`) en vez de `String`. Limitar a ~N comprobaciones por frame repartiendo orbes entre frames. | `elemental_orbs.gd` |
| O3 | **XP orbs**: guardar la referencia del jugador una vez; comprobar la atracción cada 0.1 s (no cada frame); fusionar orbes lejanos del mismo tipo. | `xp_orb.gd`, `loot_manager.gd` |
| O4 | **IA de enemigos por niveles de detalle**: lejos del jugador (>30 m) actualizar IA a 5–10 Hz y sin animación; fuera de pantalla pausar el `AnimationTree`. | `enemy.gd` |
| O5 | **Pool de enemigos**: reciclar nodos en vez de `instantiate`/`queue_free`; precalentar 40–60 enemigos en la carga. | `wave_manager.gd`, `enemy_factory` |
| O6 | **Límite de luces dinámicas**: balas sin luz propia (usar emisión/glow falso), una sola luz por arma activa, aura del jefe a 1 luz sin sombras. | `bullet.gd`, armas, `necromancer_vfx.gd` |
| O7 | **Prewarm ampliado**: compilar los shaders de orbes, fuego, haz del jefe y estelas durante la pantalla de carga. | `game_start_facade.gd` |

### Fase 2 — Calidad adaptativa por plataforma
| # | Acción | Detalle |
|---|---|---|
| Q1 | **Niveles de calidad (Bajo/Medio/Alto)** en `SettingsManager`: sombras, resolución 3D, nº de partículas, luces, glow, distancia de dibujado. Android arranca en Medio; PC en Alto. | `settings_manager.gd`, fábrica de plataformas |
| Q2 | **Resolución dinámica en móvil**: bajar `scaling_3d_scale` (0.65 → 0.5) si el frame supera 22 ms durante 2 s y subir cuando sobra; en PC FSR/`scaling_3d_mode` opcional. | `abstract_factory_pattern.gd` |
| Q3 | **Tope de enemigos por plataforma**: `ALIVE_CAP_END` 220 en PC, ~120 en Android (sigue pareciendo multitud con enemigos más gordos); el cap actual del spawn lo permite. | `wave_manager.gd` |
| Q4 | **Partículas escalables**: cantidad de partículas × factor de calidad; en móvil desactivar la niebla de la aura y las motas decorativas. | `necromancer_vfx.gd`, `elemental_orbs.gd`, armas |
| Q5 | **Sombras**: en PC reducir `directional_shadow_max_distance` (80 → 45) y usar 2 cascadas; en móvil se mantienen apagadas. | `main_procedural.tscn`, fábrica |

### Fase 3 — Contenido y assets
| # | Acción | Detalle |
|---|---|---|
| A1 | **Texturas**: reducir las > 2048 px a 1024/512 para enemigos y personajes, activar mipmaps y compresión VRAM para móvil. | `assets/textures` |
| A2 | **Modelos**: revisar polígonos del jefe y enemigos; LOD o versión simple para > 25 m. | FBX de enemigos |
| A3 | **Instanciado por MultiMesh** para enemigos básicos lejanos (solo si la Fase 1–2 no alcanza; es el cambio más invasivo). | `enemy.gd` |
| A4 | **Audio**: limitar voces simultáneas del mismo sonido (balas, golpes) para no saturar el mezclador en móvil. | `audio_manager.gd` |

## 3. Orden de ejecución sugerido
1. **Paso 0** (medir) → fija la línea base y confirma el cuello de botella real.
2. **O1 + O2 + O3**: eliminan el coste que crece con enemigos y orbes; poco riesgo.
3. **O5 + O7**: quitan tirones de spawn y compilación.
4. **O4 + O6**: IA por niveles de detalle y menos luces.
5. **Q1–Q4**: calidad adaptativa (lo que más ayuda en Android de gama baja).
6. **A1–A2**: assets.
7. **Q5, A3, A4** si todavía hace falta.

Después de cada fase, repetir las mediciones del paso 0 y comparar con la línea base.

## 4. Metas sugeridas
| Plataforma | Meta | Condición |
|---|---|---|
| PC | 60 FPS estables | 220 enemigos + jefe |
| Android gama media | 45–60 FPS | tope de ~120 enemigos |
| Android gama baja | ≥ 30 FPS | calidad Baja, resolución dinámica |

## 5. Decisiones abiertas
- ¿Qué dispositivos Android tienes para medir (modelo y chip)? Es lo que fija las metas reales.
- ¿Aceptas un tope de enemigos menor en móvil (≈120) o prefieres mantener la cantidad bajando detalle visual?
- ¿Añadimos un menú de calidad visible al jugador o solo automático por plataforma?
