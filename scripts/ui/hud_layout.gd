class_name HudLayout
extends RefCounted

## Un único sitio con los números del HUD, para que la vida, los recursos, la tira de equipo, la fila de
## oro + pausa y el minimapa no se desincronicen. La vida manda: el resto se coloca respecto a ella.
##  Escritorio: vida y recursos abajo a la izquierda; equipo a la derecha de la vida; oro + pausa debajo.
##  Móvil: lo mismo pero arriba a la izquierda (abajo a la izquierda va el joystick).
##  Las dos: minimapa arriba a la derecha.

const MARGIN := 22.0                  ## margen respecto al borde de la pantalla
const VITALS_PANEL_W := 320.0         ## ancho real del panel de vida (VitalsPanel.W + PAD * 2)
const VITALS_H := 44.0                ## alto del panel de vida (VitalsPanel.HEIGHT)
const RESOURCES_H := 63.0             ## alto reservado para las barras de recursos en escritorio
const RESOURCES_BOTTOM := -64.0       ## borde inferior de las barras de recursos (escritorio)
const EQUIP_GAP := 12.0               ## separación entre la vida y la tira de equipo
const EQUIP_LEFT := MARGIN + VITALS_PANEL_W + EQUIP_GAP   ## borde izquierdo de la tira (móvil)
const ROW_H := 44.0                   ## alto de la fila de oro + pausa (escritorio)
const ROW_GAP := 8.0                  ## separación entre el bloque de vida y la fila
const PAUSE_DESKTOP := 44.0           ## lado del botón de pausa en escritorio (cabe en ROW_H)
const PAUSE_MOBILE := 58.0            ## lado del botón de pausa en móvil (dedo)
const MAP_MARGIN := 22.0              ## margen del minimapa respecto al borde
const MAP_COMPACT := 200.0            ## lado del minimapa compacto
const MAP_COMPACT_NARROW := 150.0     ## lado compacto en pantallas estrechas (no pisa la tira de equipo)
const NARROW_W := 900.0               ## ancho por debajo del cual la pantalla cuenta como estrecha

## Borde izquierdo de la tira de equipo. Móvil: a la derecha de la vida. Escritorio: en el margen (la vida
## flota junto al personaje, así que la esquina queda libre para la tira).
static func equip_left(mobile: bool) -> float:
	return EQUIP_LEFT if mobile else MARGIN

## Escritorio: borde inferior del panel de vida (anclado abajo). En supervivencia no hay barras de recursos.
static func vitals_bottom_desktop(dungeon: bool) -> float:
	return RESOURCES_BOTTOM - (RESOURCES_H if dungeon else 0.0)

## Centro vertical de la barra de vida: en escritorio, desde el borde inferior; en móvil, desde el superior.
static func vitals_center_y(mobile: bool, dungeon: bool) -> float:
	if mobile:
		return MARGIN + VITALS_H * 0.5
	return vitals_bottom_desktop(dungeon) - VITALS_H * 0.5

## Móvil: borde superior de la fila de oro + pausa, bajo la vida y las barras de recursos visibles.
static func row_top_mobile(resources_h: float) -> float:
	return MARGIN + VITALS_H + resources_h + ROW_GAP

## Escritorio: borde superior de la fila (anclada abajo). No depende de las balas: el borde inferior
## de las barras de recursos es fijo.
static func row_top_desktop() -> float:
	return RESOURCES_BOTTOM + ROW_GAP

static func pause_side(mobile: bool) -> float:
	return PAUSE_MOBILE if mobile else PAUSE_DESKTOP

## Lado del minimapa compacto según el ancho de la pantalla.
static func map_compact(viewport_w: float) -> float:
	return MAP_COMPACT_NARROW if viewport_w < NARROW_W else MAP_COMPACT

## Primera Y libre bajo el minimapa compacto (para el FPS y el panel de equipo en red).
static func below_map_y(viewport_w: float) -> float:
	return MAP_MARGIN + map_compact(viewport_w) + 4.0
