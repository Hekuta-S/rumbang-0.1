# Más oportunidades de optimización (con mediciones)

Medido en el PC de desarrollo (1280×720, vsync, calidad Alta, mapa procedural), con 220 enemigos de datos persiguiendo al jugador. No son números de Android: sirven para comparar partes entre sí.

## Lo que se midió
| Qué | Sin enemigos | Con 220 enemigos |
|---|---|---|
| Llamadas de dibujo | 112 | 119 (el MultiMesh funciona: +7) |
| Triángulos dibujados por frame | 0,31 M | **3,2 M** (incluye pasadas de sombra en PC) |
| Triángulos por enemigo | — | **8.750–9.850** (el bruto tiene 29.562 vértices) |
| `EnemyManager` (IA + movimiento) | — | 3,1 ms por tick de física |
| `EnemyVisuals` (buffer + culling) | — | **1,3 ms por frame** |
| Nodos en escena | 928 | 949 |
| Luces dinámicas encendidas | 16 | 16 |
| Sistemas de partículas emitiendo | 16 | 16 |
| Formas de colisión del mapa | 295 | 295 |
| Texturas VAT | 26 MB | 26 MB |

Lectura: las llamadas de dibujo ya no son el problema; **el problema pasó a ser la cantidad de triángulos de los enemigos** (≈ 2 M sin sombras) y el trabajo de CPU por enemigo (visual + IA), que en móvil cuesta varias veces más que en PC.

## Oportunidades, de mayor a menor beneficio esperado

| # | Idea | Beneficio esperado | Esfuerzo / riesgo |
|---|---|---|---|
| 1 | **LOD de enemigos por cubos de distancia**: cerca = malla completa; medio y lejos = mallas simplificadas (misma lista de vértices, otro buffer de índices, así la animación horneada sigue sirviendo). Godot elige un solo LOD por MultiMesh entero, por eso se separan en 2–3 MultiMesh por modelo y se reparten según la distancia. | Triángulos de enemigos −50 % a −75 %. La simplificación automática de Godot da ≈ −50 %; con `decimate` de Blender (tienes el MCP) se llega a ≈ −75 % | Medio. Cambia `bake_enemy_vat.gd` y `enemy_visuals.gd` |
| 2 | **Sombra solo a los enemigos cercanos** (PC calidad Alta): el cubo "cerca" proyecta sombra; medio y lejos no. Hoy proyectan todos o ninguno. | Quita 2 pasadas de sombra para ~80 % de los enemigos | Bajo (sale con la 1) |
| 3 | **Menos CPU en `EnemyVisuals`**: 6 comprobaciones de plano inline en vez de 3 llamadas a `is_position_in_frustum` por enemigo; reconstruir el buffer solo en cada tick de física e interpolar en el shader (posición anterior en el canal de color). | 1,3 ms → ≈ 0,4 ms por frame (en móvil ahorra varios ms) | Bajo–medio |
| 4 | **Luces y brasas del mapa por distancia**: las 15 luces de brasero y las 16 partículas están siempre activas. Con `distance_fade` en las luces y `emitting` solo a < 45 m. | Quita 10–14 luces y partículas de cada frame; en renderer móvil cada luz cuenta | Bajo |
| 5 | **Textura VAT más ligera**: pasar de RGBAH (8 B) a RGBH (6 B), bajar fps de animación del bruto y soldar vértices duplicados. | 26 MB → ≈ 12–15 MB de memoria de video | Bajo–medio |
| 6 | **`EnemyData.update` más barato**: los enemigos a > 28 m ya hacen la IA 1 de cada 3 ticks, pero se mueven en cada uno; moverlos cada 2 ticks con paso doble, copiar la rejilla de alturas dentro de `EnemyMotion` (evita llamar al mapa). | 3,1 ms → ≈ 1,8 ms por tick | Medio |
| 7 | **Props del mapa**: 98 `MultiMeshInstance3D` + 97 `MeshInstance3D` (≈ 195 envíos de dibujo). En móvil, chunks más grandes (80 → 120 m) y fusionar por tipo. | −30 % de llamadas de dibujo del mapa | Bajo |
| 8 | **Ajustes de proyecto para móvil**: filtrado anisotrópico 0, desactivar el culling por oclusión (no hay oclusores, es solo coste), límite opcional de FPS (30/45/60) y ticks de física 30 en calidad Baja. | Pequeño pero gratis | Muy bajo |
| 9 | **Pool para proyectiles que aún se instancian** (hacha, serpientes, brazo, polvos, esporas): solo las balas están en pool. Crear y borrar nodos con estelas y partículas da tirones. | Menos tirones al disparar | Medio |
| 10 | **Shaders pesados con variante móvil**: `orbe_elemental` (ruido de 4 octavas por vértice y fragmento), nube de esporas y polvos con fbm. Variante de 1–2 octavas en calidad Baja/Media. | GPU móvil | Medio |
| 11 | **Partículas de armas a GPUParticles en PC** (ahora todas `CPUParticles3D`, ya escaladas por calidad). | CPU en PC con muchos efectos | Medio |

## Orden que recomiendo
1. **4, 8, 3** (rápidos y seguros).
2. **1 + 2** (la mayor ganancia de GPU; en móvil es lo que más se nota).
3. **5, 7, 6**.
4. **9, 10, 11** si siguen apareciendo tirones o calor en móvil.

## Qué no vale la pena
- Más pasos hacia datos puros: ya está hecho.
- Bajar más el tope de enemigos: se puede ajustar por calidad, pero mejor reducir triángulos antes.
- Compresión de texturas de personajes: ya están a 1024/2048 con compresión de GPU.

## Estado
- **#3 HECHA:** `EnemyVisuals` pasó de 1,3 a 0,48 ms por frame con 58 enemigos dibujados de 220 (−63 %): índices en vez de diccionarios, matriz escrita directamente (sin `Transform3D`/`Basis`), una sola comprobación de cámara por enemigo y solo cada 3 frames.
- **#4 HECHA:** luces y brasas del mapa solo a < 55 m del jugador (38 m en móvil). Al empezar: 6 de 16 luces y 7 de 16 sistemas de partículas activos.
- **#8 HECHA:** culling por oclusión desactivado (no hay oclusores); en móvil, filtrado anisotrópico apagado y tope de 60 FPS; en calidad Baja, 30 ticks de física.
- Pendientes: #1 y #2 (LOD y sombra de enemigos), #5, #6, #7, #9, #10, #11.
- **#1 y #2 HECHAS:** LOD de enemigos por cubos de distancia. Cada modelo tiene 3 MultiMesh: malla completa (< 16 m; < 12 m en móvil), ≈ 45 % de triángulos (< 34 m; < 26 m en móvil) y ≈ 20 % (más lejos). La simplificación se hace con `Decimate` de Blender (`tools/blender_decimate_lods.py`); cada LOD tiene sus propias texturas VAT (la skin se hereda del vértice original más cercano). Solo el cubo cercano proyecta sombra. Medido con 220 enemigos: 3,1–3,2 M → **1,9 M triángulos** (−40 %) y +22 MB de memoria de video.
  Si cambia un modelo o animación: `export_enemy_rest_obj.gd` → script de Blender → `bake_enemy_vat.gd`.
- **Geometría base reducida (HECHA):** tras revisar capturas (`docs/img/lod_enemigos_*.png`) se bajó la malla base de ~9.100–9.850 a ~4.400–4.900 triángulos (50 %) y los LOD a 22 % y 9 %. Los bruto pasaron de 29.562 a 6.467 vértices. Con 220 enemigos: **1,0 M triángulos** (antes 3,1 M) y las texturas VAT bajaron de 42 MB a 23 MB (memoria de video 185 MB, igual que antes de los LOD).
- **#6 HECHA:** frecuencia de actualización de la IA según la distancia (`EnemyData.tick_span`): a menos de 14 m cada tick de física; de 14 a 40 m cada 2 ticks; a más de 40 m o sin alertar, cada 4. `EnemyManager` acumula el tiempo (el delta es proporcional, la velocidad no cambia: medido 4,6 m/s a 30 m con span 2) y `EnemyVisuals` interpola la posición sobre todo el intervalo. Medido con 220 enemigos: con radio de aparición de 30 m, 3,1–3,3 → **2,2 ms por tick** (−30 %); con radio de 45 m, 2,1 ms; si casi todos están cerca (< 18 m) sigue en ≈ 2,8 ms porque los cercanos se actualizan cada tick.
- **#7 HECHA:** props del mapa. Cada prop tenía 2–3 superficies (materiales de color plano), así que costaba 2–3 llamadas de dibujo por chunk. Ahora `ProceduralMap._flatten_mesh` fusiona las superficies en una (color del material en el color de vértice; alfa = emisión) con un material único (`prop_flat.gdshader`), y los chunks son de 120 m en PC y 240 m en móvil (un chunk). Superficies de props dibujadas: PC 98 → 48; móvil → **15** (una por tipo). Llamadas de dibujo totales medidas: PC 113 → 94; móvil (simulado con `RUMBANG_FORCE_MOBILE=1`) 71 → 56. Contrapartida: se envían más triángulos de props (móvil 73 k → 138 k; PC 227 k → 357 k) porque los chunks grandes se recortan menos por cámara; los props tienen 56–590 triángulos, así que cuesta menos que las llamadas ahorradas. Pierde el brillo metálico de los aros de hierro.
- Para probar el modo móvil en PC: variable de entorno `RUMBANG_FORCE_MOBILE=1`.
- **#9 PARCIAL:** pool de efectos de impacto (`bullet.gd`, 323 → ~70 µs por impacto) y de fogonazos del arma (`player_camera_aim_controller.gd`). Pendientes: nube de esporas (478 µs por disparo), hacha, lanza espectral, espora y hitboxes (40–210 µs cada uno), serpiente (4 ms, sin uso claro).
- **#9 CERRADA (decisión):** el resto de proyectiles NO se pasa al pool. Coste medido de crearlos × cadencia: hacha ≈ 1,0 ms por segundo de juego, brazo ≈ 0,6, lanza espectral (peor caso, 8 lanzas a 2/s) ≈ 3,2, nube de esporas ≈ 0,2, polvos ≈ 0,4. Es un 0,1–0,3 % del tiempo (no por frame) y cada pool exige reiniciar con cuidado estados internos (listas de golpeados, temporizadores, estelas, radio variable de la nube). El riesgo supera el beneficio. `serpent_projectile` (4 ms) no se instancia en ningún sitio: es código muerto.
- **#5 HECHA:** texturas VAT en RGBA8 con los límites de cada modelo/LOD (`pos_min` y `pos_size` en el shader) en vez de RGBAH: 4 bytes por vértice y fotograma en vez de 8. 23 MB → **12 MB** en disco y en memoria de video; sin diferencia visible (comprobado con `docs/img`/hoja de primer plano a 3 m: la cuantización es de ≈ 0,7–1 cm).
- **#10 HECHA:** variantes baratas de los shaders de efectos según la calidad. Uniforme global `vfx_quality` (0/1/2; declarado en `[shader_globals]` y fijado por `Quality._apply_vfx()` al cambiar o resolver el nivel). `spore_fbm_cloud` y `alchemical_clouds`: ruido fbm de 3/2/1 octavas (reescalado para conservar el brillo), y sin esporas grandes (Medio/Bajo) o sin granos de 2.ª/3.ª capa (Bajo/Medio). `orbe_elemental`: fbm de fuego 4/3/2 octavas, viento con 1 sola muestra de ruido en Bajo y destellos del hielo solo en Alto. PC (Alto) queda idéntico; Medio (móvil por defecto) casi igual a simple vista, Bajo más liso. Compila sin errores y las pruebas de armas pasan; comprobado con capturas de los 3 niveles. Sin medir FPS en un móvil real.
- **IMPOSTORES HECHOS (por petición del usuario):** los enemigos se dibujan como sprites que cambian según el ángulo de la cámara (8 vistas × 6 fotogramas de idle + hasta 16 de caminar, celdas de 128 px, elevación de cámara 20°). Se hornean con `tools/bake_enemy_impostors.gd` (necesita render, no `--headless`; hay que ejecutar antes el horneado VAT) a `assets/vat/<clave>_impostor.png/.json`; el atlas se importa como VRAM comprimido con mipmaps (≈ 3,7 MB en ETC2 por modelo). Shader `assets/shaders/enemy_impostor.gdshader` (cuadrado vertical que mira a la cámara, celda por ángulo y tiempo, sin iluminación: lleva la luz horneada y un `tint`). `EnemyVisuals` usa un único cubo por modelo en este modo. Se activa por defecto en móvil (`Quality.use_impostors()`); en PC con `RUMBANG_IMPOSTORS=1`. Con 220 enemigos (móvil simulado): triángulos 637 k → **122 k** (−81 %), llamadas de dibujo iguales (≈ 90). Límites: sin sombra de enemigos, 8 ángulos (se nota el salto al girar de cerca), menos detalle a corta distancia; no reduce el coste de CPU de la IA/movimiento. Sin medir FPS en un móvil real.
- **Impostores, 2.ª pasada:** un solo cubo (MultiMesh) por modelo en vez de tres, bucle de relleno propio que escribe solo lo que usa el shader (posición y escala; yaw, destello y ralentizado van en los datos de instancia, sin senos/cosenos ni la matriz completa) y no se vuelven a subir los cubos vacíos. Coste de `EnemyVisuals._process` con ~225 enemigos: ≈ 0,70 → ≈ 0,64 ms en PC (≈ 6–10 %); el grueso (≈ 2,8 µs por enemigo dibujado) es lectura de propiedades y escritura en GDScript. Siguiente paso posible, más arriesgado: casillas fijas por enemigo e interpolación de posición en el shader (escribir solo cuando el enemigo se actualiza, sin recorrido por frame).
- **Impostores, 3.ª pasada (casillas fijas):** cada enemigo ocupa una casilla fija del MultiMesh de su modelo (`EnemyData.vis_slot`; `EnemyVisuals.attach/detach/write/flash`, al liberar el último ocupa el hueco). `EnemyManager` reescribe la casilla solo cuando el enemigo se actualiza (cada 1, 2 o 4 ticks según la distancia) y el shader interpola la posición con el reloj global `enemy_ticks` (ticks de física + fracción; uniformes globales `enemy_ticks` y `enemy_tick_dt` en `project.godot`). El estado va empaquetado en la matriz de instancia (escala, yaw, posición anterior relativa, tick/duración, tick del último golpe) y la animación y el destello se calculan en el shader. Ya no hay recorrido por frame ni culling por CPU (la GPU recorta los cuadrados). Medido con ~225 enemigos (PC): `EnemyVisuals._process` 755 µs → **5 µs** por frame; `EnemyManager` +≈ 0,65 ms por tick (las escrituras). Neto por segundo a 30 ticks y 60 fps: ≈ 45 → ≈ 20 ms de CPU (≈ −55 %); a 40 ticks (PC) ≈ −35 %. Comprobado: casillas tras matar enemigos (los supervivientes siguen en su sitio), pruebas de armas 11/11 y de estrategias 11/11 con impostores. Sin medir en un móvil real.
