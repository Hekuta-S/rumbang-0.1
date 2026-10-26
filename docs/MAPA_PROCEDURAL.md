# Mapa procedural dark fantasy

**Escena:** `scenes/core/main_procedural.tscn` (nodo `ProceduralMap`, script `scripts/world/procedural_map.gd`).
`character_select.gd` la usa por defecto (`USE_PROCEDURAL_MAP := true`). Pon `false` para volver al mapa Terrain3D.

## Qué genera (según la semilla)
- Arena de ~196 m con colinas suaves, **plaza plana de inicio** (círculo ritual con 4 braseros) y **acantilados** perimetrales.
- **Cuenca hundida (cripta)** de 9 m de profundidad: suelo de losas con venas arcanas púrpura, altar central, 8 pilares, braseros, lápidas, huesos, hongos. Se entra por una **rampa** desde la plaza.
- Bosque de árboles muertos, 3 cementerios (lápidas en filas + verja), 3 ruinas (pilares, muros, barriles, cajas), rocas, hongos luminosos, huesos, barriles/cajas sueltos y bloques de roca en el borde.
- Iluminación: luz de luna, niebla azulada, luces de brasero parpadeantes (máx. 16; 6 en móvil).

## Uso
- `map_seed = 0` → mapa distinto en cada partida (la semilla se imprime en consola: `[ProceduralMap] semilla=...`). Pon un número para repetir un mapa.
- Exports: `prop_density`, `basin_depth`, `basin_distance`, `hill_amplitude`, `cell_size`, `max_lights`.
- En móvil reduce resolución (2.5 m), densidad (~55 %), luces y partículas automáticamente.
- `EnvironmentManager.get_floor_y()` consulta `ProceduralMap.get_height_at()` (grupo `procedural_map`), así que enemigos, loot y boss se colocan sobre el terreno sin más cambios.

## Assets
`assets/models/mapa/*.glb` (15 props low-poly) generados desde Blender con `tools/blender/make_map_props.py`
(pegar en la consola de scripting de Blender; edita colores/formas y vuelve a exportar).
Shader del suelo: `assets/shaders/dark_ground.gdshader` (sin texturas externas).

## Límites conocidos
- Los enemigos usan spawn en ±95 m; pueden aparecer sobre la rampa o en la cuenca (intencional).
- No probado en Android; vigilar el coste de las luces y del `dark_ground` (3 octavas de ruido por píxel).
- Los árboles tienen colisión de tronco simple; si algún enemigo se atasca, quita `shape` de `tree_*` en `PROPS`.
