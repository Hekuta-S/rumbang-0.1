# Plan de mejora: game feel ("juice")

Objetivo: que cada acción (golpear, matar, esquivar, recoger, subir de nivel) tenga **respuesta inmediata,
legible y satisfactoria**, sin romper el rendimiento en Android ni el multijugador LAN.

## Estado

- **Fase 1 — hecha** (`hit_feedback.gd`, `assets/shaders/hit_mark.gdshader`, test `tests/test_hit_feel`). Sin hitstop asimétrico: el temblor de la víctima cubre el efecto.
- **Fase 2 — hecha** (`hit_feedback.gd` muertes/overkill/multi-kill/room_clear, `assets/shaders/enemy_dissolve.gdshader`,
  `scripts/objects/reward_juice.gd`, test `tests/test_death_rewards`, captura `tests/shot_death_fx`).
- **Fase 3 — hecha** (esquiva perfecta en `player_movement_controller.gd` + `player.gd`, fantasmas
  `assets/shaders/afterimage.gdshader`, aterrizaje, pasos `assets/sfx/step*.wav` generados, cámara con inercia, FOV y
  líneas de velocidad al esprintar en `camera_controller.gd`, empujón en el parry; test `tests/test_movement_feel`,
  captura `tests/shot_movement_fx`). Pendiente: pasos por superficie (agua, madera): de momento un solo juego.
- Fase 3: los fantasmas de la voltereta (`HitFeedback.afterimages`) están desactivados; quedan para la habilidad de una
  armadura.
- **Fase 4 — hecha** (`scripts/ui/combo_counter.gd` rangos D–S, `scripts/ui/ui_juice.gd` entrada de cartas/hover/punch/
  destello, temblor del panel de vida, punch de los números de daño también al reutilizarlos del pool, destello y onda
  al subir de nivel; test `tests/test_ui_juice`, captura `tests/shot_ui_juice`).
- **Fase 5 — hecha** (`HitFeedback.profile()` full/light/off y `_hit_light`: 2 golpes con efectos por frame, sin
  hitstop salvo élites, temblor con tope, bajas del mismo frame agrupadas en hasta 3 estallidos; gemas de XP con salto,
  imán que acelera, tintineo con escalera de tono y brillo de la barra de XP; test `tests/test_survival_feel`, banco
  `tests/bench_survival_juice` (60 enemigos muriendo a la vez cada 0,8 s: ~+0,5 ms de media frente a sin juice, en PC)).
  Sin medir aún en Android.
- **Fase 6 — hecha** (`audio_manager.gd`: buses SFX/Music/UI/Ambient creados al arrancar —sin .tres—, ducking de la
  música con AudioEffectAmplify en golpes pesados, remates, esquiva perfecta, caverna despejada, élites, daño recibido y
  `boss_sting`/`victory`; paso bajo en Music+SFX y latido `assets/sfx/heartbeat.wav` por debajo del 25 % de vida
  (`VitalsPanel.danger_for`); ±1,5 % de tono aleatorio en todo; 2 variantes generadas de 14 sonidos frecuentes;
  test `tests/test_audio_mix`). El bus Ambient está listo pero aún no hay sonidos de ambiente.
- Fases 0 y 7 pendientes.

## Qué ya tenemos (no rehacer)

| Sistema | Dónde | Estado |
|---|---|---|
| Hitstop global (`Engine.time_scale`), shake por trauma, flash aditivo, partículas por arma, knockback extra | `scripts/core/hit_feedback.gd` | Bien, **solo en mazmorra** |
| Viñeta roja + flash rojo de Mikeura al recibir daño | `hit_feedback.gd` (`_player_hit`) | Bien |
| Slow-mo de remates, freeze de parry | `player_finisher_controller.gd`, `player_parry_controller.gd` | Bien |
| Números de daño por tipo (crit, kill, dot…) | `scripts/core/damage_numbers.gd` | Bien |
| Hitmarker en la mira | `scripts/ui/crosshair.gd` (lee `HitFeedback.last_hit_ms`) | Bien |
| Estelas de arma, cinta del hacha | `blade_trail.gd`, `axe_ribbon.gd` | Bien |
| Polvo al pisar, FOV al esquivar, `camera_kick_z` | `player_movement_controller.gd`, `camera_controller.gd` | Básico |
| Imán de gemas/almas, tiers de gema | `xp_orb.gd`, `heal_soul.gd` | Básico |

## Huecos detectados

1. **Supervivencia no tiene juice**: `HitFeedback.enabled()` devuelve false fuera de mazmorra. Es el modo bullet-heaven, donde el "feel" de matar en masa lo es todo.
2. **El shake es aleatorio** (senos en h/v_offset): no tiene dirección ni rotación, así que no "empuja" en el sentido del golpe.
3. **El hitstop congela el mundo entero**: el enemigo golpeado no tiembla durante el freeze (la sacudida de la víctima es lo que vende el impacto).
4. **Muertes planas**: el goblin espera 1,6 s y se hunde. No sale despedido, no se deshace, no hay "último enemigo" especial.
5. **Recompensas silenciosas**: las gemas no saltan al soltarse ni suben de tono al encadenar recogidas.
6. **Sin combo/ritmo visible**: el HUD muestra BAJAS/DPS pero no una racha que premie no parar.
7. **Movimiento sin peso**: sin esquiva perfecta, sin aterrizaje con squash, sin fantasmas al esquivar.
8. **Audio sin mezcla**: `AudioManager` no usa buses; no hay ducking de música ni filtro a vida baja.
9. **Sin vibración** (mando ni móvil) y **sin ajustes de accesibilidad** (intensidad de shake, flashes).

## Fases

Cada fase es jugable y comprobable por sí sola. Orden pensado por impacto/esfuerzo.

### Fase 0 — Infraestructura y ajustes (base para todo)
- `FeelSettings` en `settings_manager.gd`: intensidad de shake (0–100 %), hitstop sí/no, reducir flashes, vibración sí/no. Todo lo de `HitFeedback` multiplica por ellos.
- Perfiles de feel por modo: `HitFeedback.enabled()` pasa a `profile()` → `"full"` (mazmorra), `"light"` (supervivencia), `"off"` (servidor dedicado).
- Panel de tuning en debug (tecla F9 en builds de editor): sliders en vivo de shake/stop/kb para ajustar sin recompilar; guardar en `resources/feel_tuning.json`.
- **Hecho cuando**: se puede bajar el shake a 0 desde Ajustes y el panel cambia valores en caliente.

### Fase 1 — El golpe (prioridad máxima)
- **Shake direccional + rotacional**: impulso en la dirección del golpe (`kb_dir` proyectado a pantalla) + leve roll de cámara; ruido suave (no senos fijos).
- **Víctima tiembla durante el hitstop**: offset aleatorio del modelo del enemigo mientras dura el freeze (tiempo real), y un pulso de squash & stretch (escala 1.15/0.9 → 1) al recibir.
- **Hitstop asimétrico ligero**: el golpe que mata o el pesado congela un poco más al jugador que al resto (sensación de "atravesar").
- **Capas de sonido**: impacto + "carne/cuerpo" + sting en crítico; **escalera de tono** en golpes consecutivos de un combo (+1 semitono por golpe, reinicia a los 0,6 s).
- **Golpes pesados**: FOV punch (−3°) y 2–3 frames de aberración cromática/flash blanco de pantalla (shader barato en CanvasLayer).
- **Marca de impacto**: arco de corte o grieta (decal/quad) 0,15 s en el punto del golpe, orientado al swing.
- **Hecho cuando**: grabación lado a lado antes/después de un combo de espada y maza contra goblins se nota claramente distinta.

### Fase 2 — Muerte y recompensa
- **Muerte con física**: impulso hacia atrás y arriba + giro según el golpe; al tocar suelo, shader de disolución (borde brillante del color del arma) en vez de hundirse.
- **Overkill**: si el daño supera mucho la vida restante, esquirlas/gibs extra y un sonido más grave.
- **Último enemigo de la sala/oleada**: slow-mo 0,4 s + leve zoom + sting.
- **Multi-kill**: banner breve ("DOBLE", "TRIPLE", "MASACRE") si se matan N en < 0,5 s.
- **Gemas y monedas**: salen en abanico con rebote, el imán acelera (ease-in), al recoger: chispa + tono que sube por cada gema encadenada; la barra de XP hace pulso.
- **Hecho cuando**: matar a un grupo de 5 enemigos de un golpe se siente como un "momento".

### Fase 3 — Movimiento y defensa
- **Esquiva perfecta**: si un golpe enemigo entra en los primeros frames de i-frames → slow-mo 0,25 s, destello azul, sonido propio y pequeño bonus (ej. recarga de estamina).
- **Fantasmas de esquiva**: 3–4 siluetas (overlay unshaded) que se desvanecen.
- **Parry**: añadir onda expansiva (anillo) y chispas al freeze actual.
- **Aterrizaje**: squash del modelo + polvo radial + cámara baja un poco según la velocidad de caída.
- **Cámara**: lead hacia la dirección de movimiento y ligero lag; líneas de velocidad al esprintar.
- **Pasos con sonido** por superficie (piedra/tierra/agua) sincronizados con `_spawn_footstep_puff`.

### Fase 4 — HUD y UI
- **Contador de combo** (estilo rango D→S): sube con golpes, decae si paras, color y tamaño crecen; al romperse, se "rompe" visualmente.
- **Barras con daño fantasma**: el tramo perdido queda en blanco y se vacía con retraso; curación con brillo verde.
- **Números de daño con punch**: escala 1.4 → 1 con overshoot; críticos con leve giro.
- **Subida de nivel**: flash de pantalla, anillo de luz en el jugador, cartas de elección que entran con tween y overshoot; hover/pulsación con escala en todos los botones de `rumbang_style.gd`.

### Fase 5 — Supervivencia "light"
- Perfil `light`: sin hitstop salvo al matar élites/jefes; shake con tope bajo; partículas con presupuesto por frame (`Quality.count`) y pooling compartido.
- **Agregación**: si mueren 10 enemigos en un frame, un único burst grande + un único sonido gordo, no 10.
- Escalera de tono al recoger gemas (la mejor fuente de dopamina del género).
- **Hecho cuando**: oleada grande de supervivencia mantiene FPS en Android y se siente viva.

### Fase 6 — Audio y mezcla
- Buses `Music`, `SFX`, `UI`, `Ambient` en `default_bus_layout.tres`; `AudioManager` enruta por bus.
- **Ducking**: la música baja 4–6 dB unos 0,3 s en golpes pesados, remates y sting de jefe.
- **Vida baja**: latido + low-pass suave en el bus SFX/Music por debajo del 25 %.
- Variantes y pitch aleatorio en todos los SFX repetidos (ya existe `_pick_variant`; revisar que todos los tengan).

### Fase 7 — Vibración
- Mando: `Input.start_joy_vibration` por intensidad del golpe (débil en golpes, fuerte al recibir daño/remate).
- Android: `Input.vibrate_handheld(ms)` corto; requiere permiso `VIBRATE` en `export_presets.cfg`.
- Respeta el ajuste de la Fase 0.

## Reglas transversales
- **Rendimiento Android**: nada de OmniLight por golpe (límite de 8 luces del renderer Mobile); usar quads unshaded aditivos y pools como ya hace `HitFeedback`.
- **Multijugador**: el hitstop/slow-mo solo afecta al cliente local; nunca en servidor dedicado; no tocar `Engine.time_scale` en partidas LAN con varios jugadores (usar solo freeze visual local).
- **Legibilidad**: el juice no puede tapar los telegrafiados de enemigos (los flashes de wind-up del goblin deben seguir viéndose).
- Todo con tiempo real (`set_ignore_time_scale(true)`) para que funcione durante hitstop.

## Prioridad sugerida (impacto / esfuerzo)

| # | Mejora | Impacto | Esfuerzo |
|---|---|---|---|
| 1 | Víctima tiembla + squash en hitstop | Alto | Bajo |
| 2 | Shake direccional/rotacional | Alto | Bajo |
| 3 | Escalera de tono en combo y gemas | Alto | Bajo |
| 4 | Muerte con impulso + disolución | Alto | Medio |
| 5 | Perfil light para supervivencia | Alto | Medio |
| 6 | Contador de combo | Medio | Medio |
| 7 | Esquiva perfecta | Medio | Medio |
| 8 | Ajustes de accesibilidad | Medio | Bajo |
| 9 | Buses + ducking | Medio | Medio |
| 10 | Vibración | Bajo-medio | Bajo |

## Validación
- Grabar clips cortos antes/después de cada fase (mismo combo, misma sala).
- Medir FPS en la mazmorra y en una oleada grande de supervivencia (enchufado, no con batería).
- Tests headless de lo puro: escalera de tono, clasificación de multi-kill, decaimiento del combo.
