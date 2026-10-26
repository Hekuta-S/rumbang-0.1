# Plan — Mejoras de nivel del Brazo Bumerán (Heckler)

Reutiliza el framework que ya hicimos con la Espalanza (`WeaponUpgrades`, cartas al subir de nivel, `on_damage_dealt` para robo de vida, hooks `size`/`cooldown`/`damage` en `get_weapon_modifiers`). Casi todo es añadir datos + hacer que el proyectil los lea.

## 1. Hallazgo importante (bug previo): el brazo no hace daño
Comprobado con una prueba en juego: un brazo lanzado hacia 3 enemigos (a 4, 8 y 12 m) **no les quita nada de vida**.
- Causa: `zombie_arm_projectile.gd` usa `collision_mask = 3` (capas 1 y 2), pero los enemigos están en la **capa 4** (`collision_layer = 4`). El área nunca detecta enemigos.
- Además, aunque los detectara, `_on_body_entered` daña cada vez que un cuerpo "entra" (sin lista de golpeados), así que podría golpear varias veces al mismo enemigo en la ida y la vuelta de forma inconsistente.
- Y el daño usa `WeaponData.weapon_damage(...)` directo (ya lo cambié a `_weapon_damage`, que incluye daño por mejoras/objetos).

**Paso 0 del plan = arreglar esto primero** (máscara de colisión + lista de golpeados + test de regresión), igual que hicimos con el hitbox de la lanza.

## 2. Diseño de mejoras (propuesta, 6 mejoras, cada una máx. 5 niveles salvo brazos)
| Mejora | Efecto por nivel | Notas |
|---|---|---|
| **Brazo extra** (máx. 4 niveles = 5 brazos) | +1 brazo por lanzamiento | Abanico: 1 central, luego ±15°, ±30°… (ángulo creciente) |
| **Reflejos de ultratumba** | −10 % enfriamiento (mín. 0.3×) | Igual que "Filo veloz" |
| **Brazo colosal** | +15 % tamaño (modelo, hitbox y estela) | La estela `RibbonTrail3D` escala el ancho |
| **Largo alcance** | +12 % distancia de ida (`max_range`) y +velocidad | Hoy: 22 m / 1.2 s máx. |
| **Daño** | +15 % daño | Ya entra por `_weapon_damage` |
| **Sed de vida** (empieza en 0) | +2 % del daño → vida (máx. 10 %) | Mismo hook `on_damage_dealt` con `source_weapon` |

Ideas opcionales (no incluidas salvo que las quieras): **Doble pasada** (golpea de nuevo en el regreso; hoy no está definido), **Perforación limitada** (golpea como máximo a N enemigos por pasada), **Intercambio de Heckler** (la pasiva de teletransporte puede ir al brazo, al estilo "Paso del Vacío").

## 3. Pasos de implementación
0. **Arreglar el daño** del brazo: `collision_mask` correcto, lista de golpeados por pasada (ida y vuelta cuentan por separado: hasta 2 golpes por enemigo, uno por pasada), test con enemigos a distintas distancias.
1. **Datos**: entrada `ZOMBIE_ARM` en `WeaponUpgrades.TABLE` con las 6 mejoras (las cartas del nivel ya las muestran solas porque `UpgradeChoiceUI.build_choices` es genérico).
2. **Proyectil**: leer `mods` → tamaño (escala nodo + ancho de estela), alcance/velocidad, `source_weapon`/`source_player` para robo de vida.
3. **Estrategia** (`ZombieArmStrategy`): cantidad de brazos en abanico; cada brazo comparte la lista de golpeados con los demás del mismo lanzamiento (un enemigo recibe una sola vez por pasada aunque lo crucen 2 brazos) — mismo criterio que las hojas de la lanza.
4. **Visual**: estela y giro proporcionales al tamaño; ligero brillo verde al subir daño; destello de curación ya existente.
5. **Pausa/HUD**: ya lista niveles (genérico); añadir solo nombres.
6. **Tests** (patrón de `tests/test_spear_*`): daño real a 3 distancias, un golpe por pasada, nº de brazos 1–5 y direcciones del abanico, tamaño/alcance, robo de vida, tope de niveles.

## 4. Interacciones a vigilar
- El objeto **Carcaj Encantado** (+proyectiles) repite el lanzamiento (eco a 0.09 s): se suma a "Brazo extra". Propuesta: dejarlos acumulables, con tope global de brazos simultáneos (p. ej. 8) para no saturar.
- **Pólvora Gruesa** (tamaño de proyectiles) multiplica sobre "Brazo colosal"; el tope global de tamaño ya existe (+100 %).
- El brazo vuelve a la mano del jugador: con varios brazos, el retorno de cada uno debe terminar al llegar (ya limpia al acercarse a 2 m).
- Heckler **no puede correr** (su pasiva usa la tecla de correr para teletransportarse): el brazo es su única arma; conviene que el rework no cambie eso.

## 5. Preguntas
1. ¿Abanico (propuesta) u **orbitando** al jugador para los brazos extra?
2. ¿Quieres "Doble pasada" y/o "Perforación limitada" desde el principio?
3. ¿El brazo debe quitar vida a enemigos al regresar (hoy, tras el arreglo, golpeará ida y vuelta)?
