# Especificación de Diseño: Nivelación de Estadísticas, Spawn Perimetral, Slash y Orbes 2D

## 1. Contexto y Objetivos
El usuario solicitó los siguientes ajustes para el juego (especialmente en el modo supervivencia):
1. **Nivelación y balance de estadísticas** de personajes jugables y enemigos (roles diferenciados, daño de contacto enemigo relevante).
2. **Spawn perimetral continuo en 360°**: los enemigos deben aparecer alrededor del jugador cerrando el cerco en un rango de 16m a 24m.
3. **Ritmo en Supervivencia (-38% de velocidad)**: tanto el personaje del jugador como los enemigos se mueven de forma más pausada y táctica.
4. **Animación y VFX del Slash**: tajos más lentos (~0.35s vs 0.18s previo), estela/arco más amplio y largo, y anclado al desplazamiento del jugador para que no se quede atrás al caminar.
5. **Orbes de EXP en Gráficos Bajos en 2D**: en calidad baja (`Quality.Level.LOW`), los orbes usan un `Sprite3D` billboard 2D ligero sin mallas CSG ni partículas 3D.

---

## 2. Cambios por Subsistema

### 2.1. Velocidades en Modo Supervivencia y Estadísticas de Personajes (`GameData.gd`)
- Constantes añadidas:
  - `SURVIVAL_PLAYER_SPEED_MULT := 0.62` (~38% más lento en supervivencia).
  - `SURVIVAL_ENEMY_SPEED_MULT := 0.62`.
- `GameData.apply_to_player()`:
  - Si `game_mode == "survival"`, aplica `player.move_speed *= SURVIVAL_PLAYER_SPEED_MULT`.
- Rebalanceo de `CHARACTERS`:
  - **Mikeura (Tanque)**: HP base 20, Escudo 12, Speed 7.8 (Total HP con bono: 35).
  - **Heckler (Void Assassin)**: HP base 16, Escudo 0, Speed 8.2 (Total HP con bono: 31).
  - **Vangry (Bruiser)**: HP base 18, Escudo 6, Speed 7.5 (Total HP con bono: 33).
  - **Bronch (Químico)**: HP base 15, Escudo 5, Speed 7.6 (Total HP con bono: 30).
  - **Tatan (Ágil)**: HP base 12, Escudo 6, Speed 8.8 (Total HP con bono: 27).
  - **Joel (Druida)**: HP base 16, Escudo 6, Speed 8.0 (Total HP con bono: 31).
  - **Riva (Corredora)**: HP base 13, Escudo 4, Speed 9.0 (Total HP con bono: 28).
  - **Garri (Brawler)**: HP base 24, Escudo 4, Speed 7.2 (Total HP con bono: 39).
  - **Saimon (Glass Cannon)**: HP base 11, Escudo 7, Speed 8.0 (Total HP con bono: 26).

### 2.2. Estadísticas de Enemigos (`EnemyTypeFlyweightFactory.gd` y `EnemyData.gd`)
- Enemigos horda en `EnemyTypeFlyweightFactory`:
  - `NORMAL_GOBLIN`: HP 35.0, Speed 3.0, Range 1.1, Daño 2.5 (antes 0.5), Oro 8.
  - `GOBLIN_RANGED`: HP 28.0, Speed 2.2, Range 14.0, Daño 3.0 (antes 2.0), Oro 6.
  - `HEAVY_BRUTE`: HP 95.0, Speed 1.6, Range 1.5, Daño 5.0 (antes 0.5), Oro 16.
  - `SNIPER_GOBLIN`: HP 40.0, Speed 2.0, Range 16.0, Daño 6.0, Oro 20.
  - `ZOMBIE_GOBLIN`: HP 22.0, Speed 1.4, Range 1.2, Daño 2.0 (antes 1.0), Oro 4.
  - `MORTAR_GOBLIN`: HP 30.0, Speed 1.6, Range 30.0, Daño 5.0, Oro 14.
- En `EnemyData.gd`: al calcular `effective_speed`, si `GameData.game_mode == "survival"`, se multiplica por `GameData.SURVIVAL_ENEMY_SPEED_MULT`.

### 2.3. Spawn Perimetral 360° (`WaveManager.gd`)
- `_random_spawn_pos()`:
  - Genera un ángulo uniforme `theta = randf_range(0, TAU)`.
  - Radio uniforme dentro de anillo perimetral: `dist = randf_range(16.0, 24.0)`.
  - Calcula coordenadas `(px, pz)` abrazando al jugador en 360°.
  - Ajusta altura con `get_floor_y(px, pz)`.
  - Garantiza aparición constante alrededor sin bucles fallidos.

### 2.4. Animación y Anclaje del Slash (`SlashVFX.gd` y `weapon_strategy.gd`)
- `SlashVFX`:
  - `DURATION` base aumenta a `0.35` (el doble del anterior 0.18s).
  - Parámetro opcional `follow_node: Node3D = null` en `spawn()`.
  - En el tween, se actualiza la posición del tajo con `delta_move = follow_node.global_position - start_player_pos`. Así, si el jugador avanza o retrocede, el corte viaja con él y no se queda atrás.
  - En `weapon_strategy.gd`, se le pasa `c.player` como `follow_node`.

### 2.5. Orbes de EXP en 2D para Gráficos Bajos (`xp_orb.gd`)
- Si `Quality.level() == Quality.Level.LOW`:
  - Desactiva/oculta `CSGSphere3D` y no instancia `CPUParticles3D`.
  - Crea un `Sprite3D` billboard (`BaseMaterial3D.BILLBOARD_ENABLED`) con un gradiente radial circular brillante unshaded.
- Si `Quality.level() > Quality.Level.LOW`:
  - Mantiene el modelo 3D y sistema de partículas original.
