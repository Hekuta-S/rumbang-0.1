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
