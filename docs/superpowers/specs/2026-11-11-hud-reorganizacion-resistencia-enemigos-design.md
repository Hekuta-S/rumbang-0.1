# Especificación de Diseño: Reorganización del HUD y Resistencia de los Enemigos

## 1. Contexto y Objetivos

Dos peticiones del usuario, en un solo cambio:

1. **HUD**: reordenar el HUD de la mazmorra para que la vida siga donde está, el minimenu de objetos
   equipados pase a la derecha de la vida, el oro y el botón de pausa formen una fila bajo el bloque de
   vida, y el mapa pase a la esquina superior derecha. Tocar el minimenu de objetos equipados abre el
   inventario y tocar el mapa abre el mapa.
2. **Enemigos**: más resistencia, entendida como **más armadura física y más aguante** (más costosos de
   aturdir y de empujar). **No se toca su vida ni su daño.**

### Objetivos
- La barra de vida **no se mueve**: en escritorio sigue abajo a la izquierda; en móvil, arriba a la izquierda.
- El HUD queda igual en **móvil y escritorio**, con la misma disposición relativa (la vida manda; el resto
  se coloca respecto a ella).
- El cambio de enemigos es solo de **aguante y empuje**: `max_hp` y `damage` de ningún enemigo se modifican.

### Decisiones tomadas (aprobadas por el usuario)
- Alcance del HUD: **móvil y escritorio**.
- Resistencia: **más armadura física y aguante**; la vida y el daño enemigo se quedan como están.
- Oro y pausa: **filera abajo del bloque de vida** (vida + energía/maná/balas).
- Mapa: se **reutiliza la vista ampliada** que ya tiene el minimapa (zona explorada con niebla, cofres,
  altar y portal). Tocar el minimapa la abre y volver a tocarla la cierra; en escritorio la tecla **M**
  hace lo mismo (el ratón está capturado, no hay clic).

---

## 2. HUD: Disposición por Plataforma

### 2.1. Constantes compartidas (`scripts/ui/hud_layout.gd`, nuevo)

Un único sitio con los números del HUD, para que vida, recursos, equipo, fila y mapa no se desincronicen:

| Constante | Valor | Significado |
|---|---|---|
| `MARGIN` | 22.0 | margen respecto al borde de la pantalla |
| `VITALS_W` | 320.0 | ancho de la barra de vida (`VitalsPanel.W`) |
| `VITALS_PANEL_W` | 340.0 | ancho real del panel (`W + PAD*2`) |
| `VITALS_H` | 44.0 | alto del panel de vida |
| `RESOURCES_H` | 63.0 | alto reservado para las barras de recursos en escritorio |
| `RESOURCES_BOTTOM` | -64.0 | borde inferior de las barras de recursos (escritorio) |
| `EQUIP_GAP` | 12.0 | separación entre la vida y la tira de equipo |
| `EQUIP_LEFT` | 374.0 | `MARGIN + VITALS_PANEL_W + EQUIP_GAP` (borde izquierdo de la tira) |
| `ROW_H` | 44.0 | alto de la fila de oro + pausa |
| `ROW_GAP` | 8.0 | separación entre el bloque de vida y la fila |
| `MAP_MARGIN` | 22.0 | margen del minimapa respecto al borde |
| `MAP_COMPACT` | 200.0 | lado del minimapa compacto |

### 2.2. Escritorio (la vida no se mueve)

| Elemento | Posición | Cambio |
|---|---|---|
| Vida (`VitalsPanel`) | abajo a la izquierda: x=22, borde inferior a `-64 - 63 = -127` | **ninguno** |
| Energía/maná/balas (`ResourceBars`) | abajo a la izquierda, justo debajo de la vida: borde inferior `-64` | **ninguno** |
| Tira de equipo (`EquipmentHud`) | **a la derecha de la vida**: x=374; centrada en vertical con la barra de vida (de `-173` a `-125`) | **reubicada** |
| Oro + pausa (`VitalsRow`) | **filera bajo el bloque**: x=22, de `-56` a `-12` (12 px por encima del borde inferior, 8 px de separación con las barras de recursos) | **reubicada** |
| Minimapa (`Minimap`) | **arriba a la derecha**: 200×200, margen 22 | **reubicado** |
| FPS | bajo el minimapa (en mazmorra) o en la esquina superior derecha (supervivencia) | **reubicado** |

### 2.3. Móvil (la vida no se mueve)

| Elemento | Posición | Cambio |
|---|---|---|
| Vida (`VitalsPanel`) | arriba a la izquierda: (22, 22), 44 px de alto | **ninguno** |
| Energía/maná/balas (`ResourceBars`) | (22, 66), debajo de la vida | **ninguno** |
| Tira de equipo (`EquipmentHud`) | **a la derecha de la vida**: x=374, y de 22 a 70 (alineada con la barra de vida) | **reubicada** |
| Oro + pausa (`VitalsRow`) | **filera bajo el bloque**: x=22, y = `66 + alto_recursos + 8` (sube 16 px si aparece la barra de balas) | **reubicada** |
| Minimapa (`Minimap`) | **arriba a la derecha**: 200×200, margen 22 | **reubicado** |
| FPS | bajo el minimapa | **reubicado** |

### 2.4. Detalles de implementación

- **La fila de oro y pausa** es un `HBoxContainer` nuevo en `scenes/ui/hud.tscn`, llamado `VitalsRow`, con
  el `GoldPanel` actual (que se mueve de `Control/TopRight` a `Control/VitalsRow`) y el botón de pausa
  creado por código dentro de la misma fila. Orden en la fila: **contador de oro a la izquierda, botón
  "II" a la derecha**.
- El botón de pausa pasa a existir **también en escritorio** (hoy solo en móvil). En móvil 58×58 px y en
  escritorio 48×48 px. Abre el menú de pausa (`PauseMenu.open_menu()`), como hoy.
- `hud.gd` recalcula la fila cuando cambia el alto de las barras de recursos (aparece o desaparece la
  barra de balas): `ResourceBars` emite la señal `layout_changed` y el HUD recoloca la fila. En escritorio
  la fila **no se mueve** con ese cambio (el borde inferior de las barras de recursos es fijo en `-64`);
  en móvil sube 16 px cuando aparece la barra de balas.
- La tira de equipo (`EquipmentHud`) se coloca calculando su posición a partir de la de la vida, de modo
  que "a la derecha de la vida" se cumple en las dos plataformas. Sus etiquetas secundaria (bonus
  temporales y aviso de perk) se recolocan debajo de la tira, no en coordenadas sueltas.
- El minimapa cambia de `PRESET_TOP_LEFT` a `PRESET_TOP_RIGHT`: el borde derecho a `-22` y el izquierdo a
  `-22 - lado`. La vista ampliada también se ancla a la derecha, para que no se salga de la pantalla.
- El FPS deja de pisar el minimapa: en mazmorra se dibuja bajo él; en supervivencia se queda en la esquina
  superior derecha y la etiqueta de bajas/DPS baja 6 px para no solaparse.
- **Responsive**: en pantallas estrechas (< 900 px de ancho) el lado compacto del mapa baja a 150 px para no
  pisar la tira de equipo de la derecha.

---

## 3. Interacciones

### 3.1. Tocar el minimenu de objetos → inventario

- La tira de equipo (la fila, la placa y el contador de mochila) pasa a ser pulsable:
  - `_row._gui_input` detecta el clic/toque en la fila y en la mochila.
  - `StoneUI.SocketPlate.socket_pressed` cubre los huecos (la pulsación larga ya no emite ese sinal, así que
    la tarjeta de información y el inventario no se pisan).
- Al pulsar se llama a `PauseMenu.open_inventory()`:
  1. Abre el menú de pausa (que pausa la partida) y encima el `EquipmentPanel`.
  2. Al cerrar el panel se cierra también el menú, se recupera el ratón capturado y el juego sigue.
  3. Si no hay equipo (supervivencia), no se abre nada.
- `PauseMenu` (CanvasLayer `layer = 100`) queda por encima de `EquipmentHud` (`layer = 12`), así que el
  inventario se ve por encima de la tira.

### 3.2. Tocar el mapa → mapa

- Se reutiliza el mecanismo actual de expansión: `_gui_input` (toque y clic) llama a `toggle()`.
- El texto de ayuda cambia: en compacto "M · TOCA", en ampliado "TOCA PARA CERRAR" (y "M" en escritorio).
- El minimapa sigue visible solo en modo mazmorra.

---

## 4. Resistencia de los Enemigos

### 4.1. Mazmorra (`scripts/entities/dungeon_*.gd`)

Campos afectados (todos ya existen en `DungeonGoblin`): `armor` (daño por debajo del cual el golpe no lo
inmuta y se acumula), `armor_break` (daño acumulado para romper la armadura), `stagger_damage` (daño que
aturde de un golpe), `windup_poise` (daño acumulado que interrumpe la anticipación) y `knock_scale` (cuánto
le empujan los golpes).

| Enemigo | `armor` | `armor_break` | `stagger_damage` | `windup_poise` | `knock_scale` |
|---|---|---|---|---|---|
| Goblin (base, `DungeonGoblin`) | 0 → **9** | 0 → **26** | 18 → **20** | 12 → **18** | 1.0 → **0.8** |
| Rata (`DungeonRat`) | 0 → **5** | 0 → **18** | 10 → **13** | 3 → **5** | 1.5 → **1.2** |
| Rata grande (`DungeonBigRat`) | 8 → **11** | 30 → **38** | 24 → **27** | 14 → **20** | 0.6 → **0.45** |
| Bruto (`DungeonBrute`) | 15 → **20** | 32 → **44** | 30 → **36** | 28 → **36** | 0.35 → **0.25** |
| Zombi (`DungeonZombie`) | 0 → **10** | 0 → **30** | 18 → **21** | 14 → **20** | 0.8 → **0.6** |
| Hinchado (`DungeonBloater`) | 0 → **12** | 0 → **34** | 18 → **23** | 20 → **27** | 0.9 → **0.7** |
| Babosa grande (`DungeonSlug`) | 0 → **9** | 0 → **28** | 22 → **25** | 16 → **22** | 0.6 → **0.45** |
| Babosa pequeña (`DungeonSlug`) | 0 → **5** | 0 → **18** | 12 → **14** | 6 → **9** | 1.1 → **0.95** |
| Mago (`DungeonMage`) | 0 → **6** | 0 → **20** | 15 → **18** | 8 → **11** | 1.0 → **0.9** |
| Necromante (jefe) | 9999 (igual) | 140 → **170** | 9999 (igual) | 9999 (igual) | 0.1 → **0.05** |

Criterios de equilibrio:
- El **goblin** es el caso medio: la espada (≈10 de daño) sigue inmutándolo, pero las dagas (≈6) y los
  ticks del lanzallamas (≈1.7) ya no: se acumulan contra la armadura y hacen falta 26 de daño seguidos
  para romperla.
- El **bruto** aguanta 44 de daño acumulado antes de romperse y necesita 36 de daño de un golpe para
  aturdirse: solo la maza (≈22 con laheavy, ≈44 con la pesada) lo tumba de un golpe.
- La **rata** sigue siendo la más frágil: se rompe con 18 de daño acumulado.
- El **mago** se interrumpe algo más que antes, pero sigue siendo interrumpible (su regla de diseño es
  que hay que castigar la conjuración).
- El **jefe** ya era casi inaturdible: solo se le endurece la armadura (170) y se le empuja la mitad.

**No se modifican** `max_hp`, `hp`, `damage`, `damage_mult`, `damage_taken_mult` ni el oro de ningún
enemigo. Los modificadores de élite (`DungeonElites`) tampoco se tocan.

### 4.2. Supervivencia (`scripts/entities/enemy_behavior.gd`, `enemy_data.gd`)

En supervivencia no hay barra de aturdimiento, así que la resistencia se aplica al **empujón**
(`EnemyBehavior.get_knockback_resistance()`, que multiplica la velocidad del empujón):

| Comportamiento | Antes | Después |
|---|---|---|
| Base (`EnemyBehavior`) | 1.0 | **0.85** |
| Goblin normal (`NormalGoblinBehavior`) | 1.0 | **0.85** |
| Mago (`RangedGoblinBehavior`) | 1.0 | **0.8** |
| Tirador (`SniperGoblinBehavior`) | 1.0 | **0.75** |
| Mortero (`MortarGoblinBehavior`) | 1.0 | **0.6** |
| Bruto (`HeavyBruteBehavior`) | 0.3 | **0.2** |
| Zombi (`ZombieGoblinBehavior`) | 1.0 | **0.6** |

Además, `EnemyData` gana el campo `knockback_resistance` (1.0 por defecto), que multiplica el empujón:
el rasgo **splitter** (goblin hinchado) lo pone a **0.6** (es grande y pesa); el rasgo **mini** se queda en
1.0. La vida y el daño de los rasgos tampoco se tocan.

---

## 5. Pruebas

### 5.1. `tests/test_hud_layout.gd` (nuevo)

Comprueba la disposición real de los nodos del HUD en las dos plataformas:

1. Instancia `scenes/ui/hud.tscn` con `GameData.game_mode = "dungeon"`.
2. **Escritorio**: la vida sigue abajo a la izquierda y en su sitio; los recursos debajo; la tira de
   equipo a la derecha de la vida (`x = 374`) y centrada en vertical con ella; la fila de oro + pausa bajo
   el bloque de vida; el minimapa arriba a la derecha (borde derecho a -22) y **no** arriba a la izquierda.
3. **Móvil**: se llama a `apply_layout(true)` en vida, recursos, equipo y mapa, y se comprueba que la
   vida sigue arriba a la izquierda (22, 22), que la tira queda a la derecha de la vida y que la fila
   queda bajo el bloque.
4. La fila de oro + pausa existe en las dos plataformas y contiene el contador de oro y el botón de pausa.
5. Al pulsar la tira de equipo se crea el `EquipmentPanel` (inventario abierto) y al cerrarlo se cierra el
   menú.

### 5.2. `tests/test_enemy_resistance.gd` (nuevo)

1. Para cada tipo de enemigo de mazmorra: los valores nuevos de `armor`, `armor_break`, `stagger_damage`,
   `windup_poise` y `knock_scale` son los de la tabla 4.1.
2. `max_hp` y `damage` **son los de antes** (tabla de referencia en el propio test): la resistencia no toca
   la vida ni el daño.
3. `armor_break >= armor` en todos los tipos (si no, la armadura se rompería de un golpe).
4. Supervivencia: la resistencia al empujón de cada comportamiento es la de la tabla 4.2 y el bruto es la
   más baja.

### 5.3. Verificación

- `godot --headless --path . res://tests/test_hud_layout.tscn` y `res://tests/test_enemy_resistance.tscn`.
- Suites que tocan lo modificado: `test_equipment`, `test_minimap`, `test_dungeon_brute`,
  `test_dungeon_mage`, `test_dungeon_undead`, `test_sewer_enemies`, `test_touch_layout`.
- Captura del HUD antes/después (`tests/shot_dungeon.tscn`) para verificar que nada se solapa.

---

## 6. Fuera de Alcance

- No se cambia la vida, el daño ni el oro de los enemigos (ni de sus élites).
- No se cambia la posición de la barra de vida ni de las barras de recursos. Por eso queda **sin tocar** el
  solapamiento de 6 px que ya existe hoy entre la vida y las barras de recursos cuando el jugador lleva un
  arma de balas (`VitalsPanel` reserva 63 px de alto y las barras ocupan 69): mover la vida para taparlo
  contradiría el requisito de no moverla.
- No se toca la barra de armas del centro inferior (`HubImage`) ni la barra de experiencia.
- No se redesigna el `EquipmentPanel` ni el `PauseMenu`: solo se les añade la entrada `open_inventory()`.
- No se crea una pantalla de mapa nueva: se reutiliza la vista ampliada del minimapa.

---

## 7. Archivos Tocados

| Archivo | Cambio |
|---|---|
| `scripts/ui/hud_layout.gd` | **nuevo**: constantes y helpers del HUD |
| `scenes/ui/hud.tscn` | `VitalsRow` nuevo; el `GoldPanel` pasa de `TopRight` a `VitalsRow` |
| `scripts/ui/hud.gd` | ruta del oro, fila de oro + pausa, botón de pausa en las dos plataformas, FPS, conexión con `ResourceBars` |
| `scripts/ui/vitals_panel.gd` | `apply_layout(mobile)` con las constantes compartidas |
| `scripts/ui/resource_bars.gd` | `apply_layout(mobile)`, señal `layout_changed` |
| `scripts/ui/equipment_hud.gd` | posición a la derecha de la vida, clic → inventario, etiquetas recolocadas |
| `scripts/ui/minimap.gd` | anclaje arriba a la derecha, mapa adaptable, textos de ayuda |
| `scripts/ui/pause_menu.gd` | `open_inventory()` |
| `scripts/entities/dungeon_goblin.gd` y los `dungeon_*.gd` de cada tipo | valores de armadura, aguante y empuje |
| `scripts/entities/enemy_behavior.gd` | resistencia al empujón por comportamiento |
| `scripts/entities/enemy_data.gd` | campo `knockback_resistance` y rasgo splitter |
| `tests/test_hud_layout.gd`, `tests/test_hud_layout.tscn` | **nuevos** |
| `tests/test_enemy_resistance.gd`, `tests/test_enemy_resistance.tscn` | **nuevos** |
| `graphify-out/*` | se regenera el grafo (`python graphify-out/build_graph.py`) |
