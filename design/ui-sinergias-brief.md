# Game Brief: Sinergias a la vista (UI de supervivencia)

<!-- Brief de una MEJORA de Rumbang, no del juego entero: por eso no es design/game-brief.md.
Hecho con /brainstorm (workflow minimal) el 2026-11-19, en modo autónomo: el usuario pidió "hazlo
todo" antes de dormir, así que las decisiones las tomó Claude Code y van marcadas. Siguiente paso:
design/ux/ui-sinergias.md (/ux-design). -->

## In your words
"ahora usa /brainstorm para generar sugerencias de mejora para la ui, que sea mas intuitiva en
supervivencia, me dicen que se les dificulta saber que cosa mejora otra y viceversa, creo que es por no
tener imagenes, y luego usa /ux-design pasa diseñar la idea, hazlo todo ya que dormire me duele la cabeza"

Elegido *(provisional, Claude decidió)*: direcciones 1 "Iconos que conectan" + 2 "Pistas en la carta",
con una versión simple de la 3 "Tablero de sinergias" dentro de la pantalla de subida de nivel.

**Pitch:** de un vistazo, cada carta te dice con imágenes qué de lo que ya llevas se hace más fuerte. *(guessed)*

**Genre:** survival bullet-heaven (al estilo Megabonk/Vampire Survivors), pantalla de cartas al subir de nivel.

**Controls:** igual que hoy: clic / toque en la carta, mando con foco; mantener (o pasar el ratón) para ver
el detalle de un icono. *(guessed)*

**Question:** ¿un jugador nuevo, sin leer, sabe qué carta potencia a qué arma o tomo que ya tiene? *(guessed)*

**Hooks:** iconos dibujados (estilo cómic, tinta) iguales en cartas, HUD y pausa; flechas/insignias que
conectan la carta con tus cosas; contador visual 2/3 de cada etiqueta. *(guessed)*

**Intent:**

## Look and references
- Look: iconos de 64 px con contorno de tinta y colores planos, como la UI cómic actual (sin cambiar los
  colores originales); cada etiqueta tiene forma y color propios (no solo color, por daltonismo). Nada de emoji. *(guessed)*
- References: Megabonk y Vampire Survivors (iconos de armas/pasivas y la pista de evolución en la carta);
  Hades (insignias de dúo en las bendiciones); Balatro (comodines legibles por icono). *(guessed)*
- View: 2D (UI sobre el juego 3D) · Camera: la del juego.

## First minute
El jugador sube de nivel por primera vez con 1 arma (p. ej. la Espada, etiqueta ⚔ Filo). Ve 3 cartas: una
arma nueva con la insignia Filo encendida y la frase-icono "Filo 1→2: +15% daño", un tomo y una mejora de su
espada. Abajo, la tira "Tu equipo" muestra la espada y la barra Filo 1/2. Elige el arma nueva: la barra
pasa a 2/2 con un destello y el HUD muestra la insignia Filo activa. Entendió la relación sin leer reglas.

## Challenge
La dificultad es de lectura, no de juego: a partir de 3 armas y 2-3 tomos las relaciones se cruzan
(evolución arma+tomo, etiquetas compartidas). La UI debe seguir clara con 4 armas, 4 tomos y 5 etiquetas.

## Core loop
- Matas, juntas XP y subes de nivel.
- Ves 3 cartas con iconos que señalan qué de lo tuyo potencia cada una.
- Eliges sabiendo qué combo construyes; el HUD lo confirma.

## Goal & fail state
- Meta: en la pantalla de cartas, el jugador identifica en ≤ 3 s qué carta sube una sinergia o lleva a una
  evolución, sin abrir ayuda. *(guessed)*
- Fallo: probadores siguen preguntando "¿esto qué mejora?" o eligen al azar. *(guessed)*

## Features
- [ ] Iconos dibujados para las 5 etiquetas, los 12 tomos y las 8 armas sin imagen (reemplazan los emoji).
- [ ] Carta nueva: imagen grande del arma/tomo + fila de insignias de etiqueta.
- [ ] Pista "conecta con lo tuyo" en la carta: mini-iconos de tus armas/tomos que potencia, con texto corto.
- [ ] Ruta de evolución visible: arma + tomo = arma evolucionada, con progreso de nivel (p. ej. 6/8).
- [ ] Tira "Tu equipo" en la pantalla de cartas: tus armas y tomos con barras de etiqueta 0/2/3.
- [ ] Mismos iconos en el HUD (sinergias activas) y en el menú de pausa.
- [ ] Detalle al mantener/pasar sobre un icono (qué es, qué potencia, qué lo potencia).

## Your systems
- iconos y estilo · in the slice
- cartas de subida de nivel · in the slice
- tira "Tu equipo" · in the slice
- HUD de sinergias · thin stand-in *(guessed)*
- pausa con tablero de sinergias · later *(guessed)*

## Keep
-

## Avoid
- Muros de texto o tutoriales para explicar sinergias. *(guessed)*
- Emoji como iconos (no se ven igual en todos los móviles y la fuente pixel no los tiene). *(guessed)*
- Cambiar los colores originales de la UI (corrección del usuario, 2026-11-15).

## Out of scope
- Cambiar las reglas de sinergias, tomos o evoluciones (solo se muestran mejor).
- La mazmorra (allí no hay cartas de mejora).
- Tablero de sinergias completo en pausa con líneas que unen todo (más adelante).

## Build order
1. Iconos de las 5 etiquetas + insignias en las cartas actuales (lo que más ayuda con menos trabajo).
2. Pista "conecta con lo tuyo" en la carta (mini-iconos + texto corto).
3. Tira "Tu equipo" con barras de etiqueta.
4. Iconos de tomos y de las 8 armas que faltan; ruta de evolución.
5. HUD y detalle al mantener.

---
**Kill condition:** si tras dos rondas de prueba los jugadores siguen sin saber qué mejora a qué, pasar al tablero completo (dirección 3). *(guessed)*

**Who it's for / what they feel:** jugadores casuales de móvil que quieren sentir que "arman su combo" sin leer reglas. *(guessed)*

**Games you love / don't:** Megabonk (inspira las sinergias y evoluciones, según el código). *(inferred (strong))*
