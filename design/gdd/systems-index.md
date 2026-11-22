# Systems Index: Rumbang

> **Status**: Draft
> **Created**: 2026-11-21
> **Last Updated**: 2026-11-21
> **Source Concept**: design/game-brief.md (reverse-documented; most systems are already implemented, so Status tracks design docs, not code)

---

## Overview

Rumbang es un roguelite de acción 3D con dos modos principales, Supervivencia y Mazmorra. Ambos comparten el núcleo de combate y daño, pero no las armas; la sinergia entre modos está planeada y no construida. El gancho es el build por sinergias (cartas, tomos, runas), el estilo cómic con tinta y los enjambres masivos. Hay 31 sistemas; casi todos ya existen en código, pero ninguno tiene GDD.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Guardado | Persistence | MVP | Not Started | — | — |
| 2 | Estadísticas y almas | Progression | MVP | Not Started | — | Guardado |
| 3 | Daño y vida | Core | MVP | Not Started | — | — |
| 4 | Movimiento y slide | Core | MVP | Not Started | — | Estadísticas y almas |
| 5 | Cámara centrada | Core | MVP | Not Started | — | Movimiento y slide |
| 6 | Combate y armas | Gameplay | MVP | Not Started | — | Daño y vida; Estadísticas y almas; Movimiento y slide |
| 7 | Efectos de estado | Gameplay | MVP | Not Started | — | Daño y vida |
| 8 | Mapa de Supervivencia | Gameplay | MVP | Not Started | — | — |
| 9 | Simulación de enjambres | Gameplay | MVP | Not Started | — | Mapa de Supervivencia |
| 10 | Jefes | Gameplay | MVP | Not Started | — | Combate y armas; Simulación de enjambres |
| 11 | XP y nivel | Progression | MVP | Not Started | — | Estadísticas y almas; Combate y armas |
| 12 | Cartas y tomos | Progression | MVP | Not Started | — | XP y nivel; Combate y armas |
| 13 | HUD y menús | UI | MVP | Not Started | — | Daño y vida; XP y nivel; Combate y armas |
| 14 | Estilo cómic y VFX | UI | Vertical Slice | Not Started | — | — |
| 15 | Parry y remates | Gameplay | Vertical Slice | Not Started | — | Combate y armas |
| 16 | Sinergias de armas | Progression | Vertical Slice | Not Started | — | Combate y armas; Efectos de estado |
| 17 | Runas y objetos | Economy | Vertical Slice | Not Started | — | Estadísticas y almas; Cartas y tomos |
| 18 | Mazmorra: cavernas y cloacas | Gameplay | Vertical Slice | Not Started | — | Mapa de Supervivencia |
| 19 | IA y rutinas de enemigos | Gameplay | Vertical Slice | Not Started | — | Simulación de enjambres |
| 20 | Élites y botín | Economy | Vertical Slice | Not Started | — | Mazmorra; Jefes |
| 21 | Game feel | UI | Vertical Slice | Not Started | — | Combate y armas; Estilo cómic y VFX |
| 22 | Audio | Audio | Alpha | Not Started | — | — |
| 23 | Meta y tienda | Economy | Alpha | Not Started | — | Guardado |
| 24 | Mesas, rampas y destructibles | Gameplay | Alpha | Not Started | — | Mapa de Supervivencia; Daño y vida |
| 25 | Ciclo día/noche | Gameplay | Alpha | Not Started | — | Mapa de Supervivencia |
| 26 | Fauna ambiental | Gameplay | Alpha | Not Started | — | Mapa de Supervivencia |
| 27 | Personaje y ropa | Gameplay | Alpha | Not Started | — | Estadísticas y almas |
| 28 | Tutorial y hub | Meta | Alpha | Not Started | — | Mapa de Supervivencia; HUD y menús |
| 29 | Multijugador LAN | Core | Full Vision | Not Started | — | Combate y armas; Mapa de Supervivencia; Guardado |
| 30 | Dado del destino | Gameplay | Full Vision | Not Started | — | Estadísticas y almas; Efectos de estado |
| 31 | Sinergia entre modos | Meta | Full Vision | Not Started | — | Sinergias de armas; Mapa de Supervivencia; Mazmorra |

---

## Categories

| Category | Description |
|----------|-------------|
| **Core** | Daño, movimiento, cámara, red |
| **Gameplay** | Combate, enemigos, mapas, jefes |
| **Progression** | Estadísticas, XP, cartas, sinergias |
| **Economy** | Runas, tienda, botín |
| **Persistence** | Guardado |
| **UI** | HUD, estilo cómic, game feel |
| **Audio** | Música y SFX |
| **Meta** | Tutorial, sinergia entre modos |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | Núcleo de Supervivencia: moverse, pelear, subir de nivel, jefe | First playable | Design FIRST |
| **Vertical Slice** | Mazmorra, sinergias, enjambre con IA, estilo cómic | Vertical slice | Design SECOND |
| **Alpha** | Alcance completo, contenido provisional | Alpha | Design THIRD |
| **Full Vision** | LAN, Dado del destino, sinergia entre modos | Release | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. Guardado — base de persistencia
2. Daño y vida — base de todo el combate
3. Mapa de Supervivencia — la Mazmorra lo hereda
4. Estilo cómic y VFX
5. Audio

### Core Layer

1. Estadísticas y almas — depends on: Guardado
2. Movimiento y slide — depends on: Estadísticas y almas
3. Cámara centrada — depends on: Movimiento y slide
4. Combate y armas — depends on: Daño, Estadísticas, Movimiento
5. Efectos de estado — depends on: Daño
6. Simulación de enjambres — depends on: Mapa de Supervivencia
7. Mazmorra — depends on: Mapa de Supervivencia

### Feature Layer

1. Jefes, XP y nivel, Cartas y tomos, Parry y remates, Sinergias de armas, Runas y objetos, IA y rutinas, Élites y botín, Meta y tienda
2. Destructibles, Día/noche, Fauna, Personaje y ropa, Multijugador LAN, Dado del destino

### Presentation Layer

1. HUD y menús, Game feel, Tutorial y hub

### Polish Layer

1. Sinergia entre modos — depends on: Sinergias de armas, Mapa, Mazmorra

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | Daño y vida | MVP | Foundation | systems-designer | S |
| 2 | Estadísticas y almas | MVP | Core | systems-designer | M |
| 3 | Combate y armas | MVP | Core | game-designer | L |
| 4 | Efectos de estado | MVP | Core | systems-designer | S |
| 5 | XP y nivel | MVP | Feature | game-designer | S |
| 6 | Cartas y tomos | MVP | Feature | game-designer | M |
| 7 | Simulación de enjambres | MVP | Core | game-designer | M |
| 8 | Jefes | MVP | Feature | game-designer | M |
| 9 | Sinergias de armas | Vertical Slice | Feature | systems-designer | L |
| 10 | Mazmorra | Vertical Slice | Core | level-designer | M |
| 11 | Sinergia entre modos | Full Vision | Polish | game-designer | L |

El resto sigue el orden de la tabla de sistemas dentro de cada nivel de prioridad.

---

## Circular Dependencies

- None found

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| Sinergia entre modos | Design | El brief dice que las armas no se comparten; el contrato de sinergia no está definido | Diseñar el contrato antes de construir; prototipo mínimo |
| Combate y armas | Scope | Más de 20 armas, cuello de botella de varios sistemas | GDD por familia de armas |
| Simulación de enjambres | Technical | Rendimiento en Android sin medir en dispositivo | Medir en el teléfono antes de ampliar |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 31 |
| Design docs started | 0 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 0/13 |
| Vertical Slice systems designed | 0/8 |

---

## Next Steps

- [ ] Diseñar los sistemas MVP primero (`/design-system daño-vida-escudo`)
- [ ] Ejecutar `/design-review` en cada GDD
- [ ] Definir el contrato de Sinergia entre modos
