# Plan — Interfaces de la Forja de Tatán (mazmorra) y del Yunque (Salón)

Fecha: 2026-11-12. Rama: `feat/mejoras-combate`.

## Estado actual (capturas: `tests/shot_equipment.tscn` → equip_tienda/equip_forja, `tests/shot_dungeon_hub.tscn` → hub_yunque)

### Forja de Tatán — `scripts/world/dungeon_shop.gd` + `scripts/ui/dungeon_choice_ui.gd`
- **Se abre sola** al acercarse (`OPEN_DIST` 2.4 m). Molesta si solo pasas cerca; no hay aviso "E: hablar con Tatán".
- Usa la misma `DungeonChoiceUI` genérica que runas/portales: fila de cartas `HFlowContainer`.
  - Con 7+ opciones las cartas **saltan a una segunda fila** y tapan el HUD; el título "FORJA DE TATAN" queda **cortado arriba** y el botón SALIR **cortado abajo** (1280×720).
  - Subtítulo neón cian monta encima del cronómetro del HUD.
  - Atajos 1-9: con más de 9 opciones las últimas no tienen tecla.
- Las cartas de equipo meten todo el texto (tipo, rareza, stats, perk, set) en un bloque de 10 px: ilegible, **sin comparación** con lo que llevas equipado (la mochila sí la tiene).
- Iconos emoji (🧪 🔋) mezclados con pixel-art; las tomos usan iconos genéricos.
- Disabled = alfa 0.5 sin decir por qué (¿falta oro?, ¿mochila llena?, ¿tomo al máximo?).
- **Trabajar piezas** = 3 niveles de menú (Tienda → Yunque → Mejorar/Re-tirar/Desguazar → pieza). "Volver" es una carta más.
  - Mejorar / Re-tirar son **a ciegas**: no se ve el rango de stats posible ni el antes/después.
  - Desguazar es una a una, sin confirmación (se puede tirar una legendaria fija de un clic), sin "desguazar todo lo común".
- Tatán no reacciona: ni saludo, ni frase, ni animación al comprar. Sin sonido propio (usa `level-up`).
- 3D: el yunque es un `BoxMesh` negro; el rótulo `Label3D` lo tapa el jugador.

### Yunque del Salón — `scripts/ui/hub_panels.gd::_build_anvil`
- 6 cartas inclinadas (skew del tema) en un `HBoxContainer` de 900 px: los nombres **se salen** ("Espalanza de |", "Dagas Gemelas" pisa la carta vecina).
- Espadón, Espada y Arco **no tienen icono** (`WeaponChoiceUI.ICONS` solo cubre 3): las cartas se ven vacías/desalineadas.
- Descripción larga en 10 px; no hay stats comparables (daño, velocidad, alcance) ni vista del arma.
- "EQUIPO GUARDADO" es una lista de texto plano apretada; con todo vacío ocupa sitio sin aportar.
- No enseña el arma en 3D aunque el armero 3D (`dungeon_hub.gd::refresh_rack`) ya tiene los modelos.

## Objetivo
Dos pantallas propias, legibles a 1280×720 y en móvil, con comparación clara, sin menús anidados, y con Tatán como personaje. Mantener `DungeonChoiceUI` para runas/portales/cofres (no tocar esos flujos).

---

## Fase 1 — Arreglos rápidos (sin rediseño)
1. `DungeonShop`: abrir con **E / botón táctil "usar"** dentro de `OPEN_DIST`, con aviso flotante igual que las estaciones del Salón. Quitar la apertura automática.
2. `DungeonChoiceUI`: si hay > 5 opciones, envolver la fila en `ScrollContainer` horizontal (una sola fila) y anclar título/SALIR dentro de un panel con márgenes seguros; ocultar el HUD (`facade.set_hud_visible(false)`) mientras está abierta.
3. Motivo del bloqueo en la carta: "FALTA 23 ORO", "MOCHILA LLENA", "TOMO AL MÁXIMO".
4. Yunque Salón: quitar skew de estas cartas, `clip_text`/autowrap al nombre, iconos que faltan para Espadón, Espada y Arco (render del modelo a PNG con el mismo marco circular).
- **Aceptación:** capturas de `shot_equipment` y `shot_dungeon_hub` sin textos cortados ni solapes; tests `test_dungeon_economy`, `test_equipment`, `test_dungeon_hub` pasan.

## Fase 2 — Pantalla propia `TatanForgeUI` (tienda)
Nueva `scripts/ui/tatan_forge_ui.gd` (CanvasLayer, pausa, tema `RumbangStyle`). `DungeonShop` deja de usar `DungeonChoiceUI` y le pasa sus datos (precios, ofertas, nivel).
```
┌───────────────────────────────────────────────────────────────┐
│ FORJA DE TATÁN                                  ◆ 400 ORO     │
│ [ TIENDA ]  [ MEJORAR ]  [ RE-TIRAR ]  [ DESGUAZAR ]  ← pestañas (Q/E, LB/RB)
├──────────────────────────────┬────────────────────────────────┤
│ CONSUMIBLES                  │  DETALLE                       │
│  🧪 Poción      40           │  Grebas Naturales  (RARA)      │
│  🔋 Recarga     24           │  +20 energía máx    ▲ +20      │
│ TOMOS                        │  +1 salto extra     ▲ nuevo    │
│  Tomo de Poder  95  0→1/5    │  ★ Pies de Niebla …            │
│  Tomo de Área   95  0→1/4    │  Set Raíz Antigua (1/5)        │
│ EQUIPO                       │  ── vs. equipado ──            │
│  Grebas Naturales 134        │  Grebas de Sombra: +8 armad. ▼ │
│  Yelmo Conquistador 99       │                                │
│                              │  [ COMPRAR — 134 ORO ]         │
├──────────────────────────────┴────────────────────────────────┤
│ [retrato Tatán] "Buen acero, buen precio. Casi."     Esc: salir│
└───────────────────────────────────────────────────────────────┘
```
1. Lista a la izquierda por secciones (navegable con flechas/D-pad), **detalle a la derecha** con la comparación frente a la pieza equipada en esa ranura (reusar la lógica de comparación de `EquipmentPanel`/tarjeta de mochila; extraerla a `EquipmentDB.compare_lines(a, b)` si está duplicada).
2. Botón de compra único en el detalle; doble clic / Enter compra directo.
3. Oro arriba a la derecha con animación de resta (`UiJuice`) y sonido de monedas en vez de `level-up`.
4. Iconos: sustituir emoji por texturas pixel-art (poción, recarga) y usar los iconos de tomo existentes.
- **Aceptación:** comprar todo lo de la tienda con solo teclado, solo ratón y solo mando; `test_dungeon_economy` adaptado al nuevo UI (API pública `buy(id)` en `DungeonShop` para tests).

## Fase 3 — Trabajo de piezas sin menús anidados
Pestañas MEJORAR / RE-TIRAR / DESGUAZAR en la misma pantalla:
1. **Mejorar**: lista de piezas equipadas + arma en mano; detalle muestra rareza actual → siguiente y **rango** de stats posible a la nueva rareza (`EquipmentDB.roll_stats` expone min/max por rareza → añadir `EquipmentForge.preview_upgrade(item)`).
2. **Re-tirar**: mismo detalle con rango; tras tirar, mostrar **antes/después** 1.5 s con flechas ▲▼ (opcional: "conservar anterior" pagando de nuevo — decidir).
3. **Desguazar**: lista de la mochila con casillas; botón "Desguazar marcadas (+N oro)" y atajo "Marcar todo lo común/poco común". Confirmación si hay épica+, legendaria fija o pieza de set que completa bonus.
4. Animación de martillazo en el icono + chispas (`GPUParticles2D` sencillo) al mejorar/re-tirar.
- **Aceptación:** mejorar, re-tirar y desguazar en ≤ 2 acciones cada uno; ningún desguace de legendaria sin confirmación; tests de `EquipmentForge` para `preview_upgrade`.

## Fase 4 — Tatán como personaje (escena 3D de la forja)
1. Diálogo corto de Tatán: banco de frases en `resources/tatan_lines.json` (saludo por nivel, compra, sin oro, mejora a legendaria, desguace). Bocadillo `Label3D` al acercarse + franja en la UI.
2. Cámara: al abrir, encuadre suave a Tatán y al yunque (como `STATIONS[*].cam` del Salón) en lugar de quedarse detrás del jugador.
3. Sustituir el `BoxMesh` por un yunque real (el del Salón o modelo Blender vía MCP) + fragua con brasas; rótulo más alto o solo visible a distancia.
4. Animación de Tatán al vender/mejorar (martillear si hay clip Mixamo; si no, un `Tween` de giro/asentimiento).
- **Aceptación:** captura `equip_forja.png` legible: Tatán, yunque y rótulo visibles sin que el jugador los tape.

## Fase 5 — Yunque del Salón como "armería"
```
┌──────────────────────────────────────────────────────────────┐
│ YUNQUE · ARMA INICIAL DE LA MAZMORRA                         │
├─────────────────────┬────────────────────────────────────────┤
│ ◉ Espalanza         │      [ modelo 3D del arma girando ]    │
│ ◉ Dagas Gemelas  ✓  │  DAGAS GEMELAS                         │
│ ◉ Maza Rúnica       │  Daño ■■□□□  Velocidad ■■■■■            │
│ ◉ Espadón           │  Alcance ■■□□□  Control ■□□□□          │
│ ◉ Espada            │  Clic: combo de cortes rápidos         │
│ ◉ Arco              │  Clic dcho: embestida                  │
│                     │  [ EQUIPAR ]                           │
├─────────────────────┴────────────────────────────────────────┤
│ EQUIPO GUARDADO  [casco][pechera][pantalón][tal1][tal2][arma]│ ← iconos con color de rareza, tooltip
└──────────────────────────────────────────────────────────────┘
```
1. Lista vertical + preview 3D del arma (reusar `CharacterPreview` con el héroe sosteniendo el arma, o un `SubViewport` con solo el modelo del armero).
2. Barras de stats derivadas de `WeaponData`/`attack_windows.json` (daño medio, golpes/s, alcance de hitbox) — sin inventar números.
3. Controles del arma en 2 líneas (clic / clic derecho) en vez del párrafo.
4. "Equipo guardado" como fila de 6 casillas-icono (mismo `EquipmentPlate` del panel de equipo) con tooltip; oculto el texto largo, se muestra solo si todo está vacío.
5. Sincronía con el armero 3D: al mover la selección, se ilumina el arma en el armero (ya existe `refresh_rack`).
- **Aceptación:** 6 armas sin cortes, cada una con icono/modelo; `test_dungeon_hub` sigue llamando `equip(w)`.

## Fase 6 — Pulido común
- Fuente: PressStart2P en títulos, fuente legible (no pixel) para descripciones ≤ 11 px.
- Soporte táctil: botones ≥ 64 px en móvil, pestañas grandes.
- Unificar colores de rareza y precios en `RumbangStyle`.
- Actualizar `tests/shot_equipment.gd` con capturas de cada pestaña y `shot_dungeon_hub` con el yunque nuevo.

## Orden sugerido
F1 (rápido, arregla lo roto) → F2 → F3 → F5 → F4 (necesita Blender) → F6.

## Decisiones abiertas
1. ¿Apertura de la forja con tecla E (recomendado) o mantener la automática?
2. Re-tirar: ¿solo resultado nuevo, o permitir "quedarse con el anterior" (estilo Diablo/Enigma)?
3. ¿Tatán con voz/frases escritas por ti, o redacto yo un primer banco de frases?
4. ¿El yunque del Salón debe permitir algo más que elegir arma (p. ej. ver/mejorar equipo guardado con moneda meta)?
