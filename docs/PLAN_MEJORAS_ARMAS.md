# Plan — Mejoras específicas por arma (empezando por la Espalanza)

> Tu mensaje se cortó en *"…robo de vida (empieza en cero) también quiero"*. Dime qué más querías añadir y lo incluyo; abajo dejo marcado dónde encaja.

## 1. Qué encontré en el código

### Por qué la Espalanza no daña a los enemigos pegados al jugador
`SpearLanceStrategy.attack()` crea `spear_lance_hitbox.tscn` (un `MeleeHitbox`, `Area3D`) **a 1.8 m delante del jugador**, y su `CollisionShape3D` va desplazada `z = -3` (hacia delante) con escala `(0.7, 1, 1.3)`:
- El volumen cubre de `z = 1.8` m hasta ~`9.6` m delante del jugador → **hay una zona muerta de 1.8 m alrededor del personaje** (justo donde están los enemigos "pegados", y todo lo que está atrás o a los lados).
- Además `MeleeHitbox` solo daña en la señal `body_entered`; un enemigo que ya estaba tocando el área al aparecer no siempre dispara la señal. Conviene leer `get_overlapping_bodies()` en los primeros frames.

### Cómo funcionan hoy las mejoras de arma
- Al subir de nivel (`UpgradeChoiceUI`) salen 3 opciones: *Nueva arma* o *Mejorar arma* (genérico: "+Daño/Área").
- `PlayerWeaponInventory.get_weapon_modifiers()` aplica una tabla **igual para todas las armas** (nivel 2 +15 % daño, 3 +10 % tamaño, 4 −15 % cooldown, …).
- Hoy solo se leen `damage` y `cooldown` de esa tabla; `size` y `quantity_bonus` **se calculan pero no los usa ninguna arma** (por eso "tamaño" y "cantidad" aún no hacen nada).
- No existe robo de vida en ningún arma.

## 2. Diseño propuesto

### 2.1 Mejoras específicas por arma (framework reutilizable)
Nuevo recurso de datos `WeaponUpgradeDef` + registro `WeaponUpgrades` (`scripts/entities/player_weapons/weapon_upgrades.gd`):
```
WeaponUpgrades.for_weapon(SPEAR_LANCE) -> [
  {id:"blade_count",  nombre:"Hoja extra",      max:7, desc:"+1 corte (máx. 8)"},
  {id:"attack_speed", nombre:"Filo veloz",      max:5, desc:"-10% enfriamiento"},
  {id:"size",         nombre:"Corte amplio",    max:5, desc:"+15% tamaño del corte"},
  {id:"damage",       nombre:"Filo templado",   max:5, desc:"+15% daño"},
  {id:"lifesteal",    nombre:"Sed de vida",     max:5, desc:"+2% del daño se convierte en vida"},
]
```
- `PlayerWeaponInventory` guarda `weapon_upgrades[w_id][upgrade_id] = nivel` (reemplaza `weapon_levels` para las armas que tengan definición; las demás siguen con la tabla genérica hasta que les toque).
- `get_weapon_modifiers()` pasa a **sumar** estos niveles (daño, cooldown, tamaño, cantidad, robo de vida) → la misma API que ya consumen `damage` y `cooldown`, más `size`, `quantity_bonus` y el nuevo `lifesteal`.
- **Al subir de nivel**: `UpgradeChoiceUI` sortea 3 cartas entre *(a)* mejoras específicas disponibles de las armas equipadas (no maxeadas), *(b)* nueva arma si hay hueco. Cada carta muestra icono del arma, nombre de la mejora, nivel `2/5 → 3/5` y descripción. Peso mayor a las armas que más usa el jugador.
- Mismo framework servirá luego para el resto de armas (cada una define su lista).

### 2.2 Espalanza: hasta 8 cortes
- Orden de aparición (cada "Hoja extra" añade la siguiente): **1 frente → 2 atrás → 3 derecha → 4 izquierda → 5-8 diagonales** (frente-der, frente-izq, atrás-der, atrás-izq). Son 8 direcciones a 45°, "en los bordes" = las diagonales.
- Cada corte = una instancia de `spear_lance_hitbox` + un `SlashVFX` orientado a su ángulo (el pool de tajos ya existe). Se disparan **simultáneamente** con el ataque base (propuesta; alternativa: barrido en sentido horario con 40 ms entre cortes, más vistoso — dime cuál prefieres).
- Con 8 hojas hay hasta 8 hitboxes/VFX por ataque → se mantiene el pool y el límite de nodos.

### 2.3 Arreglo de la zona muerta (bug de daño pegado)
- Reposicionar el hitbox: origen **en el jugador** y forma en abanico/caja que arranca en el cuerpo (`z` de `-0.3` a `-4.5`), ancho ≈ 3.0 m.
- `MeleeHitbox`: además de `body_entered`, en los 2 primeros frames recorrer `get_overlapping_bodies()` (con la lista `hit_enemies` ya evita golpear dos veces).
- Prueba de regresión: spawnear un enemigo a 0.5 m, a 1 m y detrás; el ataque con 1 y con 8 hojas debe dañar a todos los que estén dentro de su sector.

### 2.4 Estadísticas de la Espalanza (con efecto visual cuando aplique)
| Estadística | Efecto en juego | Efecto visual |
|---|---|---|
| Velocidad de ataque | `cooldown *= 0.9^nivel` (mínimo 0.3 s) | animación de swing del modelo y tajo más rápidos (`SlashVFX.DURATION` escala con el cooldown) |
| **Tamaño del corte** | hitbox × `(1 + 0.15·nivel)` | quad del tajo × el mismo factor (`SlashVFX` ya recibe `size`) y arco del shader más largo |
| Daño | `+15 %` por nivel (aditivo) | color del corte se calienta (blanco/verde más intenso: `emission_strength` sube un poco por nivel) |
| Robo de vida (empieza en 0) | `vida += daño_infligido × lifesteal`, acumulando fracciones; tope por golpe | destello verde breve en el jugador al curar |
| Cantidad de hojas | hasta 8 cortes | un tajo por dirección |

- Robo de vida: nuevo hook `Player.on_damage_dealt(amount, weapon_type)`; `MeleeHitbox` y proyectiles lo llaman al dañar. Se acumula y cura en pasos de 0.1 (como la regeneración) para no emitir señales a cada golpe. Se aplica solo al arma que lo tiene, y se suma al robo de vida global que pueda dar un objeto en el futuro.
- Interacción con objetos ya implementados: `melee_size` (Mango de Hierro) y `melee_hits` (Doble Filo) se **multiplican/suman** sobre estas mejoras; el tope global de tamaño (+100 %) se mantiene.

## 3. Pasos de implementación (pequeños y probables)
1. **Arreglar el daño pegado** (hitbox + `get_overlapping_bodies`) y test con enemigos a 0.5 m / 1 m / detrás.
2. `WeaponUpgrades` + niveles por mejora en `PlayerWeaponInventory`; `get_weapon_modifiers()` lee `size`, `quantity_bonus`, `lifesteal` (todas las armas heredan `size`/`quantity`, las que aún no los usen no cambian).
3. Espalanza: tamaño del corte aplicado a hitbox **y** visual; velocidad de ataque; daño.
4. Espalanza: múltiples hojas (8 direcciones) con VFX por dirección.
5. Robo de vida (`on_damage_dealt`) + feedback visual de curación.
6. `UpgradeChoiceUI`: cartas de mejoras específicas con nivel actual → siguiente; mostrar niveles del arma en el panel de pausa.
7. Tests automáticos (patrón de `tests/test_stats.tscn`): niveles, tope de 8 hojas, cooldown mínimo, robo de vida, enemigo pegado.

## 4. Preguntas abiertas
1. **¿Qué más querías añadir?** (tu frase terminó en *"tambien quiero"*).
2. Hojas simultáneas o en barrido secuencial (propuesta: simultáneas).
3. ¿El robo de vida cura solo al jugador o también da escudo? (propuesta: solo vida).
4. ¿"Hoja extra" puede salir en cualquier subida de nivel, o la Espalanza debe llegar antes a cierto nivel para desbloquear diagonales?
5. ¿Los niveles de mejora se reinician cada partida? (propuesta: sí; la meta-progresión ya existe en "Mejoras" del menú con oro y puede comprar un nivel inicial).
