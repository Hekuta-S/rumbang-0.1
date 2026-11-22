# UX Spec: Cartas al subir de nivel (supervivencia) + sinergias en el HUD

> **Status**: Implementado (2026-11-19): imagen, insignias, "Potencia a" (`WeaponSynergies.card_links`), tira
> "Tu equipo" con barras e iluminación carta↔equipo, mantener = detalle (soltar no elige), vuelo de la carta a
> su hueco, 🔒/✖ de 64×44, iconos en la barra de armas e insignias de sinergia activa en el HUD (saltan al
> activarse). Tests: test_card_links, test_level_up_cards, test_ui_icons. Sin probar en un móvil real; sin
> opción de "reducir movimiento"; mando sin revisar.
> **Author**: usuario + ux-designer (Claude Code, `/ux-design`)
> **Last Updated**: 2026-11-19
> **Journey Phase(s)**: desconocida (no hay `design/player-journey.md`); toda la partida de supervivencia, desde la 1.ª subida de nivel
> **Platform Target**: Android (táctil, principal) · PC (teclado/ratón) · mando parcial *(inferido del código; `project.yaml` no tiene bloque `platform`)*
> **Template**: UX Spec
> **Fuente**: `design/ui-sinergias-brief.md`. Pantalla actual: `scripts/ui/upgrade_choice_ui.gd` (UpgradeChoiceUI); reglas: `scripts/core/weapon_synergies.gd`, `scripts/core/tome_db.gd`.

Decisiones marcadas *(decidido por Claude)*: el usuario pidió hacerlo todo antes de dormir, así que no
hubo aprobación sección a sección. Revisar y cambiar lo que no encaje.

---

## Purpose & Player Need

El jugador llega queriendo **elegir la carta que más fortalece lo que ya lleva**. Hoy la relación entre
cartas y equipo solo está en texto pequeño con emoji ("Evoluciona con: …", "⚡ Filo ×2: …"), las 5
etiquetas y los 12 tomos no tienen imagen, y 8 de las 18 armas tampoco. Resultado (lo que reportan los
jugadores): no saben qué mejora a qué y eligen casi al azar.

Esta pantalla debe dejar ver, **sin leer**, para cada carta:
1. qué es (imagen),
2. a cuál de tus cosas potencia (mini-iconos de tu equipo, encendidos),
3. si te acerca a una sinergia (etiqueta x/2, x/3) o a una evolución (arma + tomo).

---

## Player Context on Arrival

- **Cuándo:** cada subida de nivel en supervivencia; la primera, a los ~30-60 s de partida.
- **Antes:** combate intenso; el juego se pausa (`get_tree().paused = true`).
- **Estado:** con prisa por volver a jugar, algo de adrenalina; en móvil, sujetando el teléfono con dos manos.
- **Llega enviado por el juego** (no voluntariamente). Debe decidir en pocos segundos.

---

## Navigation Position

Partida de supervivencia → (subida de nivel) → **Cartas al subir de nivel** (modal sobre el juego pausado).
Sin otra entrada. El HUD (sinergias activas) vive siempre en el juego.

---

## Entry & Exit Points

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Juego de supervivencia | Barra de XP llena (`present_choices(player)`) | armas (`weapon_slots`, niveles), tomos (`TomeDB.owned()`), tiradas/descartes restantes, carta fijada |
| Juego (subidas acumuladas) | Otra subida pendiente al cerrar | igual, con el equipo ya actualizado |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Juego (se reanuda) | Elegir una carta | **Irreversible**: aplica arma/mejora/tomo/evolución |
| Misma pantalla (nueva mano) | 🎲 Volver a tirar | gasta 1 tirada |
| Misma pantalla | 🔒 Fijar / ✖ Descartar | gasta descarte; la carta fijada vuelve en la siguiente subida |

No hay "cerrar sin elegir" (igual que hoy).

---

## Layout Specification

### Information Hierarchy

1. **Imagen grande** de lo que da la carta (arma, tomo, mejora o evolución).
2. **Conexión con tu equipo**: mini-iconos de tus armas/tomos que esta carta potencia, con un número de
   efecto ("+15% daño", "6/8 → evoluciona").
3. **Etiquetas** de la carta como insignias con icono + forma + color (no solo color).
4. Nombre y nivel (pips), como hoy.
5. Descripción corta (se mantiene; secundaria).
6. **Tira "Tu equipo"** abajo: tus 4 armas + 4 tomos y barras de etiqueta (x/2, x/3).
7. Acciones secundarias: 🎲 tirar, 🔒 fijar, ✖ descartar.

### Layout Zones

*(decidido por Claude: "Cartas arriba, equipo abajo"; alternativas descartadas: panel lateral de equipo
(no cabe en móvil vertical-paisaje con 3 cartas de 210 px) y equipo solo al pasar el ratón (no existe en táctil))*

- **Zona A (cabecera, 8 %):** "¡SUBES DE NIVEL!" + nivel.
- **Zona B (cartas, ~62 %):** 3 cartas en fila, cada una con su fila de 🔒 / ✖ debajo (igual que hoy).
- **Zona C (tira "Tu equipo", ~20 %):** iconos de tus armas y tomos + barras de etiqueta. Sustituye a la
  línea de texto "Sinergias: …" / "Tomos x/4: …".
- **Zona D (acciones, ~10 %):** 🎲 Volver a tirar (N).

### Component Inventory

| Zona | Componente | Contenido | Interactivo | Patrón |
|---|---|---|---|---|
| B | Carta (botón) | ver "Anatomía de la carta" | sí (elegir) | carta actual, ampliada |
| B | Insignia de etiqueta | icono 24 px + nombre corto; forma propia por etiqueta | no (detalle al mantener) | **nuevo**: Insignia de etiqueta |
| B | Fila "Potencia a" | 1-4 mini-iconos 28 px de tu equipo con contorno brillante + texto de efecto | no | **nuevo**: Conexión con tu equipo |
| B | Ruta de evolución | [icono arma] + [icono tomo] = [icono evolución], con "6/8" | no | **nuevo**: Ruta de evolución |
| B | Pips de nivel | como hoy | no | existente |
| B | 🔒 / ✖ | como hoy | sí | existente |
| C | Ranura de arma | icono 40 px + pips de nivel + insignias mini de sus etiquetas | detalle al mantener | **nuevo**: Ranura de equipo |
| C | Ranura de tomo | icono 40 px + nivel | detalle al mantener | Ranura de equipo |
| C | Barra de etiqueta | icono de etiqueta + segmentos ▢▢▢ (2 = bono 1, 3 = bono 2) | detalle al mantener | **nuevo**: Barra de sinergia |
| C | Ranura vacía | marco punteado "+" | no | — |
| D | 🎲 Volver a tirar | como hoy | sí | existente |

**Anatomía de la carta** (210×250 → 220×290 *(decidido por Claude, cabe 3 en 1280×720 con márgenes)*):

```
┌──────────────────────────┐
│ TIPO (NUEVA ARMA/TOMO…)  │  11 px, color del tipo/rareza
│        ┌────────┐        │
│        │ IMAGEN │ 72 px   │  icono del arma/tomo/evolución
│        └────────┘        │
│ NOMBRE          ●●●○○    │  15 px + pips
│ [⚔ Filo] [🌀 Arcano]     │  insignias de etiqueta
│ ── Potencia a ──         │
│ (🗡)(📖)  Filo 1→2 +15%  │  mini-iconos de TU equipo + efecto
│ descripción corta        │  11 px, gris
└──────────────────────────┘
```

Reglas de la fila "Potencia a" (en orden, se muestran como mucho 2 líneas):
1. **Evolución lista o cercana:** arma de nivel ≥ EVOLVE_LEVEL−3 + su tomo → ruta "arma + tomo = evolución" con "n/8".
2. **Arma nueva que sube una sinergia:** iconos de tus armas con esa etiqueta + "Filo 1→2: +15% daño".
3. **Tomo:** iconos de tus armas que evoluciona (TomeDB.weapons_for) + "catalizador".
4. **Mejora de arma:** icono de esa arma (la tuya) + "nivel 3→4".
5. Nada relacionado: la fila no aparece (la carta es más corta, no muestra "nada").

### ASCII Wireframe

```
┌──────────────────────────────────────────────────────────────────────┐
│                      ¡SUBES DE NIVEL!   Nv 7                          │ A
├──────────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐        │
│  │ NUEVA ARMA    │    │ TOMO · RARO   │    │ ¡EVOLUCIONA!  │        │
│  │   [espalanza] │    │   [zancada]   │    │ [lanza]+[zan] │        │ B
│  │ ESPALANZA     │    │ ZANCADA ●●○○○ │    │ = [trueno]    │        │
│  │ [⚔Filo]       │    │ +5% velocidad │    │ LANZA DEL     │        │
│  │ Potencia a:   │    │ Potencia a:   │    │ TRUENO        │        │
│  │ (🗡)(⚔) Filo  │    │ (lanza) 7/8   │    │ +60% daño…    │        │
│  │ 1→2 +15% daño │    │ catalizador   │    │               │        │
│  └───────────────┘    └───────────────┘    └───────────────┘        │
│     [🔒] [✖2]            [🔒] [✖2]                                    │
├──────────────────────────────────────────────────────────────────────┤
│ TU EQUIPO  [espada●●●][lanza●●●●●●●][ + ][ + ]  [zancada3][ + ][ + ] │ C
│            ⚔ Filo ■■□   🌀 Arcano ■□□   🔥 Fuego □□□ …              │
├──────────────────────────────────────────────────────────────────────┤
│                        [🎲 VOLVER A TIRAR (2)]                        │ D
└──────────────────────────────────────────────────────────────────────┘
```
(En el wireframe los emoji solo indican qué icono va; en el juego son imágenes, ver Accessibility.)

### HUD (thin stand-in)

*(decidido por Claude)* Junto a la barra de armas del HUD, una fila de insignias de las **sinergias
activas** (icono de etiqueta + número 2 o 3), con el mismo icono que en las cartas. Al activarse una nueva:
destello de 0,4 s y la insignia "salta". Sin texto en el HUD (el detalle está en la pantalla de cartas y la pausa).

---

## States & Variants

| State / Variant | Trigger | What Changes |
|---|---|---|
| Default | Subida de nivel con armas y tomos | Todo lo descrito |
| Inicio (1 arma, 0 tomos) | 1.ª subida | Tira C con 3 ranuras de arma vacías "+" y 4 de tomo vacías; barras en 0-1; "Potencia a" solo donde aplique |
| Sin relación | La carta no toca nada tuyo | Sin fila "Potencia a" |
| Evolución | Arma lista + su tomo | Carta dorada, ruta arma+tomo=evolución, sin 🔒/✖ (como hoy), siempre primera |
| Equipo lleno (4 armas) | 4 armas | No salen cartas de arma nueva (regla actual); ranuras sin "+" |
| Sin tiradas / descartes | contador en 0 | botones desactivados con el 0 visible (como hoy) |
| Icono que falta | Arma/tomo sin imagen | Marco con la inicial del nombre en la fuente del juego (no emoji); se registra un aviso en consola |
| Móvil pantalla pequeña | ancho < 1100 px lógicos | Cartas a 190×280; tira C con iconos de 32 px; descripción a 2 líneas |
| Mando | sin ratón | detalle con botón Y/△ sobre el elemento enfocado (ver Open Questions: mando) |

---

## Interaction Map

Mapeado para: táctil, teclado/ratón y mando (parcial).

| Componente | Acción | Entradas | Feedback | Resultado |
|---|---|---|---|---|
| Carta | elegir | toque / clic / Enter / A | escala 1.05 + sonido de elección (como hoy) | aplica la carta y reanuda |
| Carta | ver detalle | mantener 0,4 s (táctil) / pasar ratón / Y | globo con texto completo (card_text) | ninguno |
| Insignia / mini-icono / ranura / barra | ver detalle | mantener (táctil) / pasar ratón / foco + Y | globo: qué es, qué potencia, qué lo potencia | ninguno |
| 🔒 Fijar | pulsar | toque / clic / Enter / A | "🔒 FIJADA" en cian | la carta vuelve en la siguiente subida |
| ✖ Descartar | pulsar | toque / clic / Enter / A | la carta se va con animación | no vuelve en la partida |
| 🎲 Volver a tirar | pulsar | toque / clic / Enter / A / X | nueva mano con reparto | gasta 1 tirada |
| Foco | moverse | flechas / Tab / D-pad | contorno de foco (existente) | orden: cartas izq→der, 🔒/✖ de cada una, tira C, 🎲 |

**Regla del globo de detalle** *(decidido por Claude)*: en táctil, mantener abre el globo y soltar lo
cierra **sin elegir la carta** (un toque corto elige). Evita elecciones por accidente al querer leer.

---

## Events Fired

| Player Action | Event Fired | Payload / Data |
|---|---|---|
| Elegir carta | `choice_selected` (existente, `_on_choice_selected(type, id)`) | tipo, id; **cambia el estado de la partida** (armas, tomos, evolución) |
| Fijar | ninguno nuevo (GameState.locked_card) | carta — estado de partida, no de guardado |
| Descartar | ninguno nuevo (GameState.banished_cards) | carta |
| Volver a tirar | ninguno nuevo (GameState.card_rerolls) | — |
| Ver detalle | ninguno *(decidido: sin analítica en el juego)* | — |

Ninguna acción toca el guardado persistente (todo se reinicia por partida).

---

## Transitions & Animations

- **Entrada:** fondo oscurece en 0,15 s; cartas se reparten con `UiJuice.deal_in` (como hoy); la tira C sube desde abajo 0,2 s.
- **Salida:** la carta elegida se agranda y vuela hacia su ranura de la tira C (0,3 s) *(decidido por Claude: refuerza "esto va a tu equipo")*; luego fundido.
- **Cambio de estado:** al pasar el foco/dedo por una carta, sus mini-iconos y las ranuras correspondientes de la tira C se iluminan a la vez (vínculo visual carta ↔ equipo).
- **Barra de etiqueta que sube:** el segmento nuevo parpadea al elegir.
- **Movimiento reducido:** sin vuelo ni parpadeo; solo cambio instantáneo de estado. *(No existe aún la opción en Ajustes: ver Open Questions.)*

---

## Data Requirements

| Data | Source System | Read / Write | Notes |
|---|---|---|---|
| Armas equipadas y nivel | PlayerWeaponInventory (`weapon_slots`, `get_weapon_level`) | Read | — |
| Etiquetas y sinergias activas | WeaponSynergies (`tags_of`, `tag_counts`, `tier`, `active`) | Read | — |
| Evoluciones (arma, tomo, nivel) | WeaponSynergies (`EVOLUTIONS`, `EVOLVE_LEVEL`, `can_evolve`, `is_evolved`) | Read | — |
| Tomos, nivel y rareza | TomeDB (`owned`, `level`, `TOMES`, `weapons_for`) | Read | — |
| Cartas de la mano | UpgradeChoiceUI.build_choices | Read | sin cambios de reglas |
| Iconos (texturas) | **nuevo**: `assets/ui/icons/` (etiquetas, tomos, armas que faltan) | Read | hoy armas en `assets/ui/ingame_hub/armas/` (10 de 18); etiquetas y tomos solo emoji |
| Tiradas, descartes, fijada | GameState | Read/Write | ya existe |
| Elección | Player / inventario | Write | ya existe |

**Nueva función de datos sugerida** *(para el programador, no decide arquitectura)*: una consulta pura
"¿a qué de mi equipo potencia esta carta?" → lista de {icono, texto}, probable en WeaponSynergies, para
que la carta y las pruebas usen la misma regla.

---

## Input Method Completeness Checklist

**Táctil**
- [x] Todos los elementos se alcanzan con el dedo (cartas, 🔒, ✖, 🎲)
- [x] Diferencia toque (elegir) / mantener (detalle) definida
- [ ] Tamaño mínimo de toque de 🔒/✖ ≥ 48 dp — hoy son botones de texto pequeños (ver Open Questions)

**Teclado / ratón**
- [x] Orden de foco definido (cartas → 🔒/✖ → tira C → 🎲)
- [x] Foco visible (existente)
- [x] Detalle al pasar el ratón
- [ ] Atajos 1/2/3 para elegir carta — no definidos (opcional, ver Open Questions)

**Mando (parcial)**
- [x] Elegir con A, tirar con X, detalle con Y
- [ ] `ui_accept`/`ui_cancel` sin botón de mando asignado (problema conocido del proyecto, ver Open Questions)
- [ ] Desconexión del mando: no definido

---

## Accessibility

No hay `design/accessibility-requirements.md` (tier no definido; se asume WCAG‑AA como base).

- **No solo color:** cada etiqueta tiene **forma** distinta además de color *(decidido por Claude)*:
  Filo = rombo/espada, Fuego = llama, Explosivo = estallido de 8 puntas, Arcano = espiral, Naturaleza = hoja.
- **Sin emoji como icono:** todos son texturas dibujadas (la fuente pixel no tiene los glifos y cada
  Android dibuja los emoji distinto). Estilo: tinta oscura + colores planos, sin cambiar los colores
  originales de la UI.
- **Texto mínimo:** 11 px lógicos a 1280×720 (≈ 18 px reales en un móvil de 2460×1080); descripciones no bajan de 11.
- **Contraste:** texto claro sobre fondo de carta oscuro ≥ 4.5:1; insignias con contorno de tinta.
- **Lectores de pantalla:** `text_summary` / `tooltip_text` de cada carta ya existe; se amplía con la
  línea "Potencia a: …" en texto.
- **Movimiento reducido:** ver Transitions.

---

## Localization Considerations

- El juego está en español. Textos largos de riesgo: nombres de evolución ("GUARDIANES ANCESTRALES", 22
  car.), descripciones de evolución (~45 car.), "Potencia a" (≤ 28 car. por línea). **HIGH PRIORITY** si
  se traduce: limitar nombre a 2 líneas y descripción a 3 con autowrap.
- La fuente pixel no tiene "Ó" (ver comentario en `_make_card`): usar textos sin esa letra o cambiar de fuente.
- Números con "%" y "→": formato fijo, sin separadores de miles.

---

## Acceptance Criteria

- [ ] La pantalla aparece completa (cartas + tira "Tu equipo") ≤ 200 ms después de la subida de nivel en un Mali‑G57 en calidad Baja.
- [ ] Ninguna carta, insignia, ranura ni barra muestra un emoji: todo icono es una imagen (comprobable con las 18 armas, 12 tomos y 5 etiquetas).
- [ ] Una carta de arma nueva que activa una sinergia muestra los mini-iconos de tus armas con esa etiqueta y el texto "Etiqueta n→n+1: efecto".
- [ ] Una carta de tomo que es catalizador de un arma tuya muestra el icono de esa arma y su progreso "n/8".
- [ ] Una carta sin relación con tu equipo no muestra la fila "Potencia a" (estado vacío).
- [ ] La tira "Tu equipo" muestra 4 ranuras de arma y 4 de tomo; las vacías con "+"; las barras de etiqueta coinciden con `WeaponSynergies.tag_counts`.
- [ ] En táctil, mantener una carta 0,4 s muestra el detalle y al soltar **no** se elige; un toque corto sí elige.
- [ ] Con teclado/mando, el foco recorre cartas → 🔒/✖ → tira → 🎲 y siempre se ve.
- [ ] Al elegir, el HUD muestra la insignia de sinergia activa con el mismo icono de la carta.
- [ ] Prueba con 3 jugadores nuevos: identifican en ≤ 3 s qué carta sube una sinergia o lleva a una evolución, sin abrir ayuda.

---

## Open Questions

- No hay `design/player-journey.md`. Autorizarlo desde `.claude/docs/templates/player-journey.md` para fijar el contexto del jugador.
- No hay biblia de arte ni requisitos de accesibilidad. Formas y estilo de iconos decididos aquí; validar con `/art-bible` o el `art-director`.
- **Iconos a producir:** 5 etiquetas + 12 tomos + 8 armas sin imagen (Espada de energía, Railgun, Serpientes, Hacha giratoria, Ciclo elemental, Brazo zombi, Katana, Puños) + 11 evoluciones (o reutilizar el icono del arma con un marco dorado *(sugerido)*). ¿Dibujarlos en Blender/Python como las texturas toon, o encargarlos?
- Tamaño de 🔒/✖ en móvil (hoy pequeños): ¿agrandar a 48 dp aunque ocupe más alto?
- Mando: `ui_accept`/`ui_cancel` no tienen botón de mando (ver memoria "Gamepad UI diagnosis"). Arreglarlo antes o junto a esta pantalla.
- Atajos 1/2/3 en teclado: ¿se quieren?
- Opción "Reducir movimiento" en Ajustes: no existe.
- Tablero completo de sinergias en pausa: fuera de esta spec (later en el brief).
