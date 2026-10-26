# Plan — Aparición continua de enemigos y Jefe Nigromante

Archivos implicados: `scripts/core/wave_manager.gd`, `resources/wave_config.json`, `scripts/core/main.gd`, `scripts/core/game_start_facade.gd`, `scripts/core/game_state.gd`, `scripts/ui/hud.gd`, `scripts/entities/necromancer_boss.gd`, `scripts/objects/eruption.gd`.

## Decisiones tomadas
- **Sin oleadas, sin pisos.** Los enemigos aparecen siempre y la presión sube con el tiempo de partida.
- **Sin contador de enemigos y sin avisos en el suelo** para las apariciones.
- **El Nigromante entra a los 6:70 → 430 s = 7:10** (6 min + 70 s). Si querías 6:30 o 7:00, es una sola constante (`BOSS_TIME_S`).

## 1. Diagnóstico (estado actual)
- `WaveManager.start_wave()` genera un piso con cupo fijo (`25 + 15·nivel`), un `Timer` que lo vacía y `wave_cleared` al terminar → `main.gd` avanza de piso. Todo el flujo (`advance_level`, `update_floor`, `best_floor`, victoria en el piso 9) cuelga de eso.
- Tabla de enemigos plana (`"default"`), sin cambios con el tiempo; sin escalado de vida o daño.
- Jefe duplicado: `WaveManager` crea `"boss"` cada 3 pisos y `main.gd` crea `"necromancer"` con la tecla O.
- El Nigromante solo tiene la animación del modelo; sus efectos son pobres (rayo = cilindro, zombis aparecen de golpe, muerte = `queue_free`).
- El tiempo de partida ya existe: `GameState.elapsed_time` (`main.gd` lo suma solo cuando el juego no está pausado). Es la base natural del nuevo sistema.

## 2. Aparición continua (WaveManager → "SpawnDirector")

Un solo bucle que lee `elapsed_time` y decide cuánto y qué spawnear. Nada de pisos.

| # | Cambio | Detalle |
|---|---|---|
| S1 | **Spawn permanente** | Un `Timer` que arranca con la partida y nunca se detiene. Cada tick elige cuántos enemigos sacar (lote) y de qué tipo. |
| S2 | **Curva de intensidad** | `intervalo = lerp(1.4 s → 0.25 s)` y `lote = 1 → 6` según el minuto (curva suave, p. ej. `t/BOSS_TIME_S`). Más enemigos con el tiempo, sin picos bruscos. |
| S3 | **Tope de vivos (rendimiento)** | Máximo de enemigos simultáneos que crece con el tiempo (p. ej. 40 → 220). Interno, **no se muestra**. Si se alcanza, se pausa el spawn hasta que muera alguno. |
| S4 | **Tipos por minuto** | `wave_config.json` pasa de `"default"` a tramos por tiempo: `{"from": 0, "pool": [...]}`, `{"from": 120, "pool": [...]}`, … Los élites y zombis en grupo entran desde el minuto 2–3; el reparto cambia con el tiempo. |
| S5 | **Escalado de stats** | `hp_mult = 1 + 0.15·minuto` y `dmg_mult = 1 + 0.06·minuto`, aplicados al instanciar el enemigo. |
| S6 | **Aparición sin aviso** | Se mantiene el anillo actual (8–16 m del jugador, con la corrección de terreno), añadiendo variedad ligera: a veces dos lados opuestos o un grupo denso. Sin marcador en el suelo. |
| S7 | **Limpieza del flujo viejo** | Quitar `wave_cleared`, `start_wave/start_next_wave`, `advance_level`, la señal en la fachada y el cupo por piso. `HUD.update_floor` se reemplaza por el cronómetro (ya existe `update_elapsed_time`). |
| S8 | **Mejor marca** | `best_floor` deja de tener sentido: guardar **mejor tiempo sobrevivido** o **jefe derrotado**. Hay que migrar `SaveManager` (`best_floors` → tiempo). |

## 3. Llegada del Nigromante (7:10)

| # | Cambio | Detalle |
|---|---|---|
| B0 | **Disparo por tiempo** | Al cruzar `BOSS_TIME_S`, `WaveManager` instancia `EnemyFactory.create_enemy("necromancer")` una sola vez (bandera `boss_spawned`). Se retira el jefe genérico `"boss"` y queda la tecla O como atajo de depuración. |
| B0b | **Qué pasa con los enemigos normales** | Propuesta: el spawn normal **baja a ~35 %** mientras el jefe vive (para que el combate sea contra el jefe, no un muro de enemigos). Sin eventos de pantalla ni contador. |
| B0c | **Al derrotarlo** | Propuesta: pantalla de victoria (`show_victory`) con el tiempo total. Alternativa: seguir jugando en modo infinito. |

## 4. Efectos visuales del Nigromante

| # | Cambio | Detalle |
|---|---|---|
| B1 | **Aura permanente** | Niebla morada/verde a los pies, luz tenue que pulsa y un contorno fresnel para destacarlo del resto. |
| B2 | **Rayo de robo de vida** | Reemplazar el cilindro por un haz con shader animado (ondas hacia el jefe), chispas donde toca al jugador y destello verde en el jefe al curarse. |
| B3 | **Invocación de zombis** | Sin círculo en el suelo (lo pediste sin avisos): columnas de luz y humo/tierra en el punto de salida y zombis que emergen del suelo con escala + partículas. |
| B4 | **Erupciones** | Se conserva el disco actual de `eruption.gd` (es la telegrafía del ataque, no un aviso de aparición); añadir onda expansiva y sacudida de cámara al estallar. |
| B5 | **Fases por vida** | 100–66 %: actual. 66–33 %: más rápido y cooldowns menores. <33 %: enfurecido (aura roja, 5 zombis, rayo más largo). Cada cambio con onda + sacudida + destello. |
| B6 | **Golpes legibles** | Flash con tinte, esquirlas de hueso/energía y barra de vida del jefe en el HUD (solo la del jefe, no contador de enemigos). |
| B7 | **Muerte** | Disolución por shader, almas que suben y destello del oro, en vez de `queue_free()` inmediato. |
| B8 | **Habilidades** | Cola barajada (no repetir dos veces seguidas) y una pausa "vulnerable" tras cada habilidad. |

## 5. Orden de implementación
1. **S1 + S2 + S3 + S6** — spawn continuo con curva y tope; el juego ya se siente como survivor.
2. **S4 + S5** — tipos y stats por minuto (`wave_config.json`).
3. **S7 + S8** — borrar el flujo de pisos, cambiar HUD y guardado.
4. **B0 + B0b + B0c** — el Nigromante a los 7:10 y su final.
5. **B8 + B5** — lógica de habilidades y fases.
6. **B3, B4, B2** — efectos de habilidades.
7. **B1, B6, B7** — aura, golpes y muerte.

Cada paso se prueba solo; el paso 1 se puede validar con `BOSS_TIME_S` corto (p. ej. 20 s) para ver al jefe sin esperar siete minutos.

## 6. Preguntas abiertas
- ¿Hora del jefe: **7:10** (6 min + 70 s) o querías 6:30 / 7:00?
- ¿Al matarlo, victoria o seguir jugando?
- ¿Mientras el jefe vive, bajo el spawn normal (propuesta) o lo dejo igual?
