---
name: patterns-delivery
description: Preparar los entregables de la Evaluación No. 3 (Patrones de Diseño, UPC): Control de Cambios PE-xx, Informe de Incorporación de Patrones, UML antes/después, README y guion de sustentación. Úsalo al documentar patrones aplicados o redactar el informe.
---

# Entregables Evaluación 3 — Patrones creacionales y estructurales

Requisitos de la guía: **todos los creacionales** (Abstract Factory, Builder, Factory Method, Prototype, Singleton) y **mínimo 3 estructurales**; el proyecto debe seguir funcionando; cada patrón resuelve un problema concreto del código de la E2 y sigue los participantes GoF.

## 1. Control de Cambios (prefijo PE)
| ID | Clase(s) Modificada(s) | Patrón Aplicado (Creacional / Estructural) | Problema Previo | Mejora Obtenida |
|---|---|---|---|---|
| PE-01 | `scripts/...` | Factory Method (Creacional) | `match` de tipos disperso en el spawner | Nuevos enemigos sin tocar el spawner (OCP) |

Todos los campos diligenciados; una fila por patrón (más filas si cambian varias clases). Obtén clases afectadas con `git diff --stat` y `graphify query`.

## 2. Informe de Incorporación (por cada patrón)
- **Qué**: intención del patrón y su tabla de participantes → clases reales del proyecto.
- **Cómo**: código ANTES y DESPUÉS, diagrama de clases antes/después.
- **Por qué**: problema de diseño de la E2 que resuelve (principio SOLID relacionado).
- **Beneficios y desventajas**: extensibilidad, acoplamiento, complejidad añadida.
- **Evidencia**: archivos y commits (`git log`, rutas `scripts/...`).

## 3. Diagrama UML
Exportar imagen del diagrama actualizado (puede generarse con Mermaid/PlantUML desde `graphify-out/graph.json`), marcando los nuevos participantes y diferencias frente al anterior. Incluirla en el documento.

## 4. Documento integrador
Base: documento de la E2, corrigiendo observaciones de portada, preliminares, formato, orden e imágenes/tablas. Agregar Control de Cambios, informe, UML y URL del repositorio.

## 5. Repositorio y README
README con tecnologías (Godot 4 / GDScript), funcionalidades, despliegue/ejecución y un apartado "Cambios de la tercera entrega". Verificar que el proyecto abre y corre sin errores.

## 6. Presentación (10–15 min)
Guion: contexto (1 min) → por patrón: problema, ANTES, DESPUÉS, mejora (≈1 min c/u) → demo del juego funcionando → conclusiones. Nota: la guía menciona Java, pero el proyecto es Godot/GDScript; aclararlo en el informe o confirmar con el docente.
