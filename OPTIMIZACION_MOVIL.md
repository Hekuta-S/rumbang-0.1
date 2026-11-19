# Optimización para móvil: cientos de enemigos en pantalla

Plan de optimización de Rumbang (Godot 4.7, renderizador `mobile`) para que el modo supervivencia
aguante muchos enemigos en Android/iOS. Todo lo de aquí está medido con el banco de pruebas del juego.

## Cómo medir

```
RUMBANG_FORCE_MOBILE=1 RUMBANG_BENCH=600 RUMBANG_BENCH_SECONDS=25 godot --path . --resolution 1280x720 res://scenes/core/main_procedural.tscn
```

- `RUMBANG_FORCE_MOBILE=1` simula el móvil en PC (impostores, física a 30 Hz, topes de móvil).
- `RUMBANG_BENCH=N` mantiene N enemigos vivos alrededor del jugador (invulnerable durante el banco).
- `RUMBANG_PROFILE=1` añade el desglose por secciones (`PerfProbe`) y cuántos enemigos se actualizan por tick.
- En partida, F9 alterna el banco con 300 enemigos.

## Diagnóstico (antes)

El cuello de botella era la **CPU (lógica de los enemigos)**, no la GPU: los enemigos ya eran datos
(sin nodos), dibujados con MultiMesh e impostores, con menos de 200 llamadas de dibujo.

1. **Espiral de la muerte**: con un frame lento Godot repetía la física hasta 8 veces para ponerse al
   día (se veían 4-7 pasos de física por frame) y el siguiente frame era aún más lento.
2. **Movimiento** (`EnemyMotion.move`): ~11 µs por enemigo. Cada uno recorría los obstáculos de una
   celda de 8 m como diccionarios con claves de texto, y la consulta creaba un Array vacío nuevo.
3. **Casi todos se actualizaban en cada tick**: el enjambre se pega al jugador y el reparto por
   distancia (cada 1, 2 o 4 ticks) no servía.
4. **Separación**: la rejilla espacial se reconstruía con claves `Vector2i`, y en un enjambre denso
   cada enemigo miraba decenas de vecinos.

## Qué se hizo

| Cambio | Dónde | Efecto |
|---|---|---|
| Máximo 2 pasos de física por frame en móvil (4 en PC) | `PerformanceGovernor` | Sin espiral: un frame lento ya no arrastra a los siguientes |
| Reparto de la IA según la multitud (×1 a ×5 con 120-600 enemigos; a menos de 3 m siempre cada tick) | `EnemyManager.CROWD_*`, `EnemyData.crowd_scale` | ~40 % menos actualizaciones por tick con 600 enemigos; el shader interpola el movimiento |
| Obstáculos en `PackedFloat32Array` por celda de 4 m, con descarte rápido por distancia | `EnemyMotion` | El movimiento deja de recorrer diccionarios |
| Rejilla de enemigos con claves enteras | `EnemyRegistry` | Reconstrucción por tick más barata |
| Separación con un máximo de 6 vecinos | `EnemyRegistry.SEP_MAX_NEIGHBORS` | El coste ya no crece con el cuadrado del enjambre |
| `EnemyQuery.overlapping` sin Array nuevo por llamada | `EnemyQuery` | Menos basura en las hitboxes cuerpo a cuerpo |
| Velocidad del modo de juego cacheada al aparecer | `EnemyData` | Sin comparar textos en cada actualización |
| Tope de enemigos dinámico según la CPU | `PerformanceGovernor`, `Quality.crowd_factor`, `WaveManager` | Un móvil caliente quita enemigos (hasta un 60 %) en vez de ir a tirones |
| 30 FPS en calidad Baja en móvil | `Quality.mobile_max_fps` | Batería y temperatura |
| 24 números de daño a la vez en móvil (50 en PC) | `Quality.floating_numbers_max`, `PoolManager` | Menos dibujos transparentes sin prueba de profundidad |
| 50 orbes de experiencia en móvil (90 en PC) y sin Array nuevo por muerte | `Quality.xp_orbs_max`, `LootManager` | Menos nodos y partículas |
| Topes de enemigos vivos: móvil 120/220/320, PC 150/300/500 (Bajo/Medio/Alto) | `Quality.alive_cap_end` | Más enemigos en pantalla |
| Perfilador por secciones | `PerfProbe`, `EnemyBenchmark` | Medir antes de optimizar |
| Controles táctiles horneados en un atlas (SubViewport, una vez) y pintados como recortes | `mobile_controls.gd` | Llamadas de dibujo en supervivencia sin enemigos: 221 → 69 (los controles eran 152; en mazmorra, 9 botones = 2 llamadas). Cada arco, círculo o polígono de `_draw` es una llamada |
| Fauna ambiental sin interpolación de física | `ambient_critters.gd` | Sin el aviso de MultiMesh ni el doble búfer de transformaciones |

## Resultados (PC simulando móvil, 1280×720)

Medido el 2026-11-03 en un portátil que pudo estar con poca batería (CPU limitada): tómese como
orientativo y repítase enchufado para comparar.

| Enemigos | FPS medio | FPS mínimo | Pico de física |
|---|---|---|---|
| 300, antes | 47 | 11.6 | 83 ms |
| 300, después | 58 | 38 | 48 ms |
| 600, antes | 37 | 18 | 103 ms |
| 600, después | ~58.5 | ~52 | 38-47 ms |

Con 600 enemigos se actualizan ~255 por tick (antes ~600) y el bucle de enemigos baja a ~4 ms por frame.

## Pendiente (necesita un móvil real o es un cambio grande)

1. **Validar en dispositivo** (Android de gama media con Mali/Adreno): medir con el banco y ajustar
   `Quality.alive_cap_end` y `CROWD_*`. El gobernador de multitud protege mientras tanto.
2. **Simulación de enemigos en C++ (GDExtension)**: el bucle de IA en GDScript cuesta unos 15-30 µs
   por enemigo actualizado; en C++ sería 10-30 veces menos y permitiría 1000+ enemigos en móvil.
3. **Animación de impostores**: ahora son sprites estáticos (lo más barato). Si se anima, hacerlo en
   el shader con `INSTANCE_CUSTOM` (ya se envía la fase y si camina) sin tocar la CPU.
4. **Texturas**: revisar tamaños de los atlas de impostores y de los props (ASTC 4×4 en Android).
5. **Instancias de props del mapa** con MultiMesh si el perfil de GPU en el dispositivo lo pide.

## Perfil en dispositivo real (2026-11-16)

Black_3 (MediaTek MT6789 / Helio G99, Mali-G57 MC2, 2460×1080), batería 13-17 % y por USB (puede limitar).
En Android no hay variables de entorno: el banco se activa con un archivo `user://bench.txt`
(`adb shell run-as com.example.rumbang sh -c 'echo "300 20 u s=1.0 h=ground" > files/bench.txt'`, APK de debug).
Opciones: `p` perfilador, `u` sin tope de FPS ni vsync, `s=X` escala 3D fija sin gobernador,
`h=a,b` oculta partes (`env`, `env_fog`, `env_adj`, `env_tone`, `env_sky`, `aa`, `lights`, `sun`, `ground`,
`props`, `enemies`, `player`, `hud`, `critters`). Borrar el archivo al terminar.

Bisección de GPU (300 enemigos, sin tope, escala 1.0; base 20.0 FPS = 50 ms):

| Apagado | FPS | Coste aprox. |
|---|---|---|
| suelo | 29.0 | ~15.5 ms |
| FXAA + debanding | 24.7 | ~9.5 ms |
| sol (luz direccional) | 23.3 | ~7 ms |
| entorno (niebla, ajustes, tonemap, cielo) | 23.2 | ~7 ms |
| HUD | 23.0 | ~6.5 ms |
| omnis, props, enemigos, jugador, fauna | ~20 | ≈0 |

Cambios: FXAA solo en Alta en móvil y sin debanding (`Quality.mobile_aa`), y suelo con
`toon_ground_mobile.gdshader` (luz por vértice, sin anisotrópico, losa solo en la cripta).
Resultado: escala 1.0 20.0 → ~26 FPS; con el gobernador (partida real, sin tope) 33.3 → 39.5 FPS.
Tras el cambio, el suelo aún cuesta ~10 ms a escala 1.0, el sol ~1.3 ms, tonemap filmic ~2.5 ms, cielo ~3 ms,
niebla y ajustes ≈0, HUD ~3 ms. CPU: `enemigos.bucle` ~10.7 ms por tick con 165 actualizados.

## Movimiento de enemigos en C++ (GDExtension, 2026-11-17)

`EnemyMotion.move` (relieve, mesetas, puentes, obstáculos, empuje del jugador) tiene una copia en C++:
`native/src/enemy_motion_native.cpp`, cargada por `bin/rumbang_native.gdextension`. EnemyMotion le pasa los
mismos arrays empaquetados al construir el mapa y llama a `move()` por enemigo; sin la extensión (Web, sin
compilar) sigue el GDScript. `RUMBANG_NATIVE=0` (o `nn` en `bench.txt`) lo desactiva para comparar.
`tests/test_native_motion.tscn` comprueba que da lo mismo que el GDScript (16000 pasos, peor diferencia
0.0003 m) y mide: en PC 15.6 → 6.0 µs por paso (la llamada GDScript → C++ cuesta ~1 µs).

Compilar (desde `native/`; herramientas: scons por pip, llvm-mingw en `C:/Users/cabeu/tools`, NDK r28b
28.1.13356709 en el Android SDK, godot-cpp clonado en `native/godot-cpp`, no versionado):

```
python -m SCons platform=windows use_mingw=yes use_llvm=yes target=template_debug     (y template_release)
python -m SCons platform=android arch=arm64 target=template_debug ANDROID_HOME=<sdk>  (y template_release)
```

Con llvm-mingw en el PATH para Windows. Si se cambia el algoritmo de `enemy_motion.gd`, cambiar también el C++.

### Simulación completa de enemigos en C++ (EnemySimNative)

`native/src/enemy_sim_native.cpp` hace todo el bucle de `EnemyManager` en una llamada por tick: temporizadores,
frecuencia de actualización (tick_span), IA de los 6 tipos (persecución, magos, francotirador, mortero,
embestida, golpe al suelo, furia del zombi), tokens y densidad de `HiveMind`, separación, movimiento
(`EnemyMotionNative`) y el búfer del MultiMesh en modo impostor. El estado vive en C++; tras cada actualización
escribe de vuelta en el `EnemyData` lo que lee el resto del juego (global_position, prev_position, velocity, yaw,
tick_span, is_alerted, empujón y ralentización), así armas, `EnemyQuery` y efectos no cambian. Disparos, golpes
al jugador, mortero y golpe al suelo vuelven como eventos y los ejecuta GDScript (`EnemyBehavior.fire_*`/`hit_player`).

- Lo que el juego cambia de un enemigo debe pasar por métodos: `take_damage`, `apply_knockback`, `set_knockback`,
  `apply_slow`, `alert()`; si se tocan atributos a mano (vida, velocidad, escala) llamar a `EnemyManager.mark_dirty(e)`
  (al crear no hace falta: el spawn ya lo marca).
- Se decide en el primer spawn (hace falta relieve en C++). `RUMBANG_NATIVE_SIM=0` o `ns` en `bench.txt` lo
  desactivan (queda solo el movimiento en C++); `nn` desactiva todo el C++.
- Diferencia conocida: fuera de la ventana de densidad (más de 64 m del jugador) no hay separación.
- `tests/test_native_sim.tscn`: misma horda con los dos caminos. En PC, 300 enemigos: 1.66 → 0.30 ms por tick.
- Si se cambia la IA en `enemy_data.gd`, `enemy_behavior.gd` o `hive_mind.gd`, cambiar también el C++.

## Perfil con 420 enemigos en calidad Baja (celular, 2026-11-17)

`bench.txt` con `420 20 u pc`: el banco imprime `[FRAME]` con el reparto del frame (scripts de física por tick,
scripts de `_process` y el resto: render, motor, espera del vsync). `tools/bench_render_phone.sh` hace la bisección.

- Simulación de enemigos en C++ (`ns` la apaga): scripts de física 8.1 → 3.5 ms por tick.
- Render en Baja (escala 3D 0.5): bajar a 0.25 no cambia nada y apagar suelo, tonemap, luces, props o enemigos
  tampoco (≈0). Lo único medible es el HUD: ~3.5 ms (el panel de vida eran 21 llamadas: ahora `HudBatch` lo junta
  en una malla, 4 llamadas; queda ~3 ms por las etiquetas con contorno y la barra de armas).
- Con TODO apagado el frame sigue en ~18.7 ms (52 FPS): hay ~12 ms fijos del motor (render del Godot, copia
  final a pantalla a 2460×1080, vsync que no se puede desactivar en este móvil). Con 420 enemigos: ~41-45 FPS sin tope.
- Hilo de render separado (`thread_model=2`): no lo admite Android en Godot 4.7 ("Rendering thread not
  supported by this display server") y fue peor. Descartado.
- `force_lambert_over_burley.mobile=true` activado (difuso más barato, sin diferencia visible).
