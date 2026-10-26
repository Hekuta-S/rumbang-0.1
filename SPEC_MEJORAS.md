# SPEC — Puntos de mejora de RUNBANG (tesis)

Fecha: 2026-10-19 · Rama: `developer` · Motor: Godot 4.7 (Forward Plus)

> Alcance del análisis: `scripts/`, `scenes/`, `assets/shaders/`, estructura del repo y `project.godot`.
> No se ejecutó una partida completa; los hallazgos de rendimiento están marcados con su nivel de confianza.
> Prioridad: **P0** hacer ya · **P1** próximo sprint · **P2** deseable.

---

## 1. Shaders de ataques (HECHO en esta entrega)

Todos conservan los nombres de uniforms que ya usa el código GDScript; los uniforms nuevos tienen valor por defecto, así que **no hay que tocar ningún script** para ver la mejora. Los 6 shaders compilan y cargan en Godot 4.7.1 (probado con el renderer de compatibilidad; falta una pasada visual en partida con Forward+).

| Shader | Usado por | Problemas detectados | Mejora aplicada |
|---|---|---|---|
| `slash_2_optimized` | Espada de energía, Espalanza (tajo) | `blend_mix` con emisión: se veía opaco/apagado. El "ruido" `hash_noise` generaba valores correlacionados (solo cambiaba `n` con `fract`, no había ruido real). Desaparecía de golpe al terminar el tween (`queue_free` con alpha aún alto). | `blend_add` (suma luz, aprovecha glow). Hash/value-noise real. Capas: halo exterior, filo, núcleo caliente, estrías de velocidad, destello de punta y chispas que quedan atrás. Borde irregular que se desgasta hacia la cola. Fade de entrada/salida (sin pop). Nuevos uniforms: `halo_strength`, `streak_strength`, `spark_strength`, `edge_noise`, `tail_length`. |
| `spear_thrust` | Modelo de la Espalanza | Runas con senos que producían un shimmer borroso. Sin sensación de velocidad. Fade abrupto. | Runas como bandas discretas que viajan por el asta. Líneas de velocidad paralelas, anillo de choque en la punta, chispas, halo y núcleo blanco. Fade final. Nuevos: `halo_strength`, `streak_strength`, `shock_strength`. |
| `sword_slash` | Variante de media luna | Filo liso, sin halo ni dinamismo. | Ruido en el filo, halo, núcleo, estrías, destello de punta, fade-out. Nuevos: `halo_strength`, `streak_strength`, `edge_noise`. |
| `ribbon_mesh` | Hacha giratoria (2 estelas), brazo zombi | Cinta plana con `blend_mix`, sin energía interna. | Aditivo, línea caliente central, flujo de energía animado por la cinta, bordes deshilachados que se erosionan con la edad. Nuevos: `intensity`, `flow_speed`, `flow_strength`, `fray`. |
| `shotgun_distortion` | Escopeta (onda de choque) | Anillo sin variación ni fade con el progreso; quedaba un círculo perfecto. | Frente de onda con ruido angular, aberración cromática, brillo en el frente y fade con `progress`. Nuevos: `chroma`, `rim_glow`, `glow_color`. |
| `alchemical_clouds` | Polvos alquímicos (vuelo + explosión + puff) | `weapon_strategy.gd:969` enviaba `explosion_expand_strength`, uniform que **no existía** (parámetro silenciosamente ignorado). Interior plano. | Uniform añadido (sin efecto visual por ahora, evita el desajuste). Fresnel + brillo interior dependiente de la densidad. Nuevos: `inner_glow`, `fresnel_power`. |

**Pendiente de shaders (no tocado a propósito):**
- `orbe_elemental`, `spore_fbm_cloud`, `depth_scan_spawn`: funcionan, pero tienen coste alto (ver §2.2). Se recomienda reducir octavas antes de embellecerlos más.
- `particle_ribbon_trail.gdshader` no lo referencia ningún script ni escena → candidato a borrar (P2).

---

## 2. Rendimiento

### 2.1 Materiales y nodos creados en cada ataque — **P0** (confianza alta) — ✅ aplicado parcialmente
> Hecho: `scripts/objects/slash_vfx.gd` (pool + shader precargado) usado por espada y Espalanza; `preload` de shaders en `weapon_strategy.gd`, `player_weapon_visuals.gd`, `spinning_axe_projectile.gd`. Pendiente: pool de los VFX de polvo/fuego y precalentado en el loading screen.
- `weapon_strategy.gd:62`, `:457`, `:958` y `player_weapon_visuals.gd:506,773` hacen `load("res://...gdshader")` y `ShaderMaterial.new()` + `MeshInstance3D.new()` + `QuadMesh.new()` **en cada golpe**. `load()` está cacheado por el motor, pero se asignan decenas de uniforms por golpe y se crean/destruyen nodos y recursos continuamente (GC de recursos + compilación de pipeline la primera vez → *stutter* en el primer ataque).
- **Mejora:** `static var` con `preload` del shader (como ya hacen `dust_projectile.gd:35` y `spore_cloud.gd:17`) y un pool pequeño de `MeshInstance3D` de slash dentro de `PoolManager` (que ya existe para balas y números flotantes). Precalentar materiales en el loading screen (instanciar una vez cada VFX fuera de cámara) para evitar el hitch del primer uso.
- Existen **tres copias** casi idénticas de "crear quad de slash + orientar + tween progress + queue_free" (espada, lanza, y variantes). Extraer `SlashVFX.spawn(pos, dir, side, params: SlashPreset)`.

### 2.2 Coste de GPU en móvil — **P0/P1** (confianza media, falta perfilar en el dispositivo)
El proyecto tiene `Plan_Optimizacion_Android.txt` y `tesis.apk`, por lo que Android es objetivo real.
- `alchemical_clouds` (fragment): 3 fBm × 4 octavas × interpolación cúbica de 16 lecturas hash = ~190 hashes por píxel, en esferas que ocupan buena parte de la pantalla. → Sustituir por una textura de ruido 128² tileable (el shader ya tiene `noise_texture` / `use_custom_texture`; basta con activarlo en móvil) o reducir a 1 fBm de 2 octavas con value-noise.
- `spore_fbm_cloud` (vertex): 3 fBm × 5 octavas **por vértice** cada frame. → 2 octavas en móvil o mover la deformación a una textura de ruido.
- `orbe_elemental` (vertex): fBm de 4 octavas + ramas `if (element == …)` por vértice; el `element` es uniform así que no diverge, pero el ruido 3D es caro. Usar 2 octavas y menos segmentos (`radial_segments=24, rings=16` → 16/8).
- Varios efectos agregan un `OmniLight3D` por golpe (`weapon_strategy.gd` shockwave de fuego, puff de polvos, etc.). Con muchos enemigos, las luces dinámicas son lo más caro en Forward+/móvil. → Limitar luces simultáneas (contador global) o simularlas con un quad aditivo.
- Añadir una calidad de efectos (`SettingsManager`) con 2-3 presets que conmuten octavas/luces/partículas vía `#define`-like uniform (`quality`) o shaders alternos.

### 2.3 Búsquedas por grupo en bucles — **P1** (confianza media: verificar frecuencia)
`get_tree().get_nodes_in_group("enemies")` aparece en `dust_projectile.gd:101`, `elemental_orbs.gd:194`, `weapon_strategy.gd:308,400`, `smoke_trail_zone.gd:35`, `passive_shield_warrior.gd:73`, `wave_manager.gd:43,162`, `player.gd:639`. Cada llamada reserva un array nuevo. Si alguna se ejecuta por frame o por proyectil, sustituir por: `Area3D` con la forma del efecto (física ya lo filtra) o una lista de enemigos mantenida por `WaveManager` (señales `enemy_spawned/died`).

### 2.4 IA de enemigos — **P1**
`enemy.gd:_physics_process` hace `look_at` y `move_and_slide` cada frame en todos los enemigos; la lógica pesada ya está escalonada (`_logic_timer`, bien). Mejoras: LOD de IA por distancia (no animar/`move_and_slide` a >N m si no están alertados, ya hay un early-out parcial), y `set_physics_process(false)` para enemigos lejanos no alertados.

---

## 3. Arquitectura y calidad de código

### 3.1 Archivos monolíticos — **P1**
| Archivo | Líneas | Problema |
|---|---|---|
| `player_weapon_visuals.gd` | 1291 | Construye **todos** los modelos de arma proceduralmente en código (cientos de líneas de `MeshInstance3D.new()` + materiales). Difícil de iterar y sin previsualización en editor. |
| `weapon_strategy.gd` | 1109 | Una clase por arma (bien: patrón Strategy), pero todas en un único archivo, con VFX mezclado con lógica de daño. |
| `player.gd` | 865 | Aún concentra spawn-scan, debug, armas, energía. Ya se extrajeron controladores (buen camino); falta mover el *depth scan* a un componente `SpawnVFXComponent`. |

**Mejora:** un archivo por estrategia (`scripts/components/weapons/*.gd`) + `WeaponVFX` separado de `WeaponStrategy`; los modelos de arma como escenas `.tscn` editables (o al menos un script por arma). Reduce conflictos de merge (hay 14 archivos modificados sin commit en este momento).

### 3.2 Datos en código vs. recursos — **P1**
Estadísticas de enemigos hardcodeadas en `enemy_behavior.gd` (`enemy.max_hp = 40.0`, `speed`, `gold_reward`…), colores/uniforms de VFX dispersos como números mágicos en cada `.gd`. → `EnemyConfig` / `VFXPreset` como `Resource` (`.tres`) editables en el inspector; `resources/wave_config.json` ya demuestra la dirección (migrarlo a `Resource` tipado y validarlo: `_load_wave_config` ignora silenciosamente un JSON inválido).

### 3.3 Código duplicado y muerto — **P2**
- `scripts/core/main_ready_god_method_ejemplo.gd` (209 líneas, ejemplo didáctico) vive en el código de juego.
- `scripts/patterns/*` (Singleton, Abstract Factory, Builder…) coexisten con autoloads reales; confirmar cuáles se usan (`EnemyFactory` sí) y mover lo demostrativo a `docs/`.
- `scripts/entities/recover_player.py`, `refactor_player.py`: scripts de migración, fuera del árbol del juego.
- `particle_ribbon_trail.gdshader` sin referencias.
- Mezcla de `load()` y `preload()` para lo mismo; unificar (preload para constantes de ruta).

### 3.4 Tipado y robustez — **P2**
- Muchos `var x = ...` sin tipo y `has_method("take_damage")` por duck-typing. Activar en Project Settings: `debug/gdscript/warnings/untyped_declaration` = Warn y definir una interfaz (`class_name Damageable`) para daño.
- `enemy.gd`: `player` se busca por grupo en cada frame en que es inválido; cachear una vez vía señal de `GameState`.
- Valores de `look_at` hacia un punto horizontal pueden fallar si el enemigo está exactamente sobre el jugador (vector cero) → ya hay chequeo `length_squared() > 0.01`, bien.

---

## 4. Repositorio y pipeline — **P0**

| Hallazgo | Detalle | Acción |
|---|---|---|
| Binarios pesados versionados | `tesis.apk` (314 MB), `facade-ejemplo.rar`, `backup/` (15 MB), `run_log.txt` (UTF-16) | Mover APK a *Releases*; añadir al `.gitignore`; Git LFS para assets grandes. |
| `.gitignore` ignora `*.uid` e `*.import` | Godot 4.4+ **recomienda versionar los `.uid`**. Hoy hay avisos `invalid UID … using text path instead` (`bullet.tscn`, `radiation_zone.tscn`) y los UID de los shaders no son estables entre máquinas. | Quitar `*.uid` del `.gitignore` y commitear los `.uid`. |
| Addons enormes | `addons/` = **1.5 GB** (`godot_mcp_toolkit`, `terrain_3d`, `ziva_agent`). `addons/ziva_agent/` aparece sin trackear. | Los de tooling (`godot_mcp_toolkit`, `ziva_*`, `local_keep_ai`) deben ser dev-only y excluirse del export (`export_presets.cfg` → exclude filter) y del repo si es posible. |
| Grafo de conocimiento contaminado | `GRAPH_REPORT.md`: 2315 nodos, las comunidades dominantes son de addons de terceros. | Hacer que `graphify-out/build_graph.py` excluya `addons/` y `assets/`; el grafo de *tu* código quedaría en ~100 nodos útiles. |
| Documentación dispersa | ~15 `.txt`/`.md`/`.puml` en la raíz (UML, SOLID, C4, facade…) | Mover a `docs/` con un índice. |
| Metadatos inconsistentes | `project.godot` dice "Godot 4.3", features `4.7`, `run_log` muestra 4.4. | Fijar versión en README/`config/description`. |
| Cambios sin commit | 14 archivos de gameplay + grafo modificados; el grafo (`graph.html`, `graph.json`) genera diffs enormes. | Commitear por feature; no versionar artefactos regenerables del grafo (o ignorar `graph.html`). |

---

## 5. Pruebas — **P1**
Solo existe `tests/test_map.gd`. Lógica pura y barata de testear: `WaveManager` (escalado por piso/boss cada 3), `StatsComponent`/`HealthComponent`, `WeaponData`, `GameData`/`SaveManager` (serialización), cálculo de daño por arma. Adoptar **GUT** y correr en CI (GitHub Actions con `godot --headless`). Añadir un test de humo que cargue cada `.gdshader` y cada escena de `scenes/objects/` para detectar errores de compilación (el script usado en esta revisión sirve de base).

---

## 6. Plan sugerido

1. **Sprint 1 (P0, ~1-2 días):** limpieza de repo (§4), cachear shaders/materiales y pool de slashes (§2.1), perfilar en Android con los nuevos shaders (§2.2).
2. **Sprint 2 (P1):** modo de calidad de VFX, reemplazar fBm por textura de ruido en móvil, tests GUT básicos y CI (§5), división de `weapon_strategy.gd` y `player_weapon_visuals.gd` (§3.1).
3. **Sprint 3 (P1/P2):** `Resource`s para enemigos/VFX (§3.2), tipado estricto y `Damageable` (§3.4), limpieza de código muerto (§3.3).

## 7. Cómo validar los shaders nuevos
Abrir el proyecto, lanzar partida y probar: Espada de energía, Espalanza (tajo y modelo), Hacha giratoria y brazo zombi (estelas), Escopeta (distorsión) y Polvos alquímicos. Para iterar sin jugar, instanciar un `MeshInstance3D` con `QuadMesh` y animar `progress` de 0→1 desde el inspector. Ajustar `emission_strength`/`energy` si con glow de entorno se ve sobreexpuesto (ahora los efectos son aditivos y se verán más brillantes que antes).
