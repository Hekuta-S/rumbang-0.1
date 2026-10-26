# Guion de presentación (10–15 min) y preparación de la sustentación individual

## Parte A · Guion de la presentación

La guía exige: contexto del proyecto, problema, solución, requerimientos funcionales y no funcionales, arquitectura C4, diagrama de clases, demostración y **énfasis en el incremento respecto a la versión anterior**.

| Min | Diapositiva | Contenido | Material del repo |
|---|---|---|---|
| 0:00–1:30 | 1. Contexto | RUMBANG: roguelike de supervivencia 3D (Godot 4.7) con enjambres de enemigos, 11 armas y 5+ personajes; objetivo: correr fluido en móvil. | `README.md`, `docs/resumen_runbang.txt` |
| 1:30–3:00 | 2. Problema y solución | Código acoplado a rutas, plataformas y fórmulas repetidas; solución: patrones GoF sobre el código SOLID de la E2. | `diagnostico_solid.txt` |
| 3:00–4:00 | 3. Requisitos | Funcionales: combate con armas, oleadas, mejoras, jefe. No funcionales: rendimiento móvil (pools, impostores, MultiMesh), extensibilidad, mantenibilidad. | `SPEC_MEJORAS.md` |
| 4:00–5:00 | 4. Arquitectura C4 | Diagrama C4 del repo. | `c4_architecture.puml`, `c4_explicacion.txt` |
| 5:00–6:00 | 5. Diagrama de clases | Antes/después global y tabla de diferencias. | `docs/entrega3/03_diagramas_uml.md` |
| 6:00–11:00 | 6. Patrones (≈ 40 s c/u, ANTES→DESPUÉS) | Creacionales: Factory Method, Abstract Factory, Builder+Director, Prototype, Singleton. Estructurales: Decorator, Flyweight, Adapter (+Facade). Mostrar el código real. | `docs/entrega3/02_...md` |
| 11:00–13:00 | 7. Demostración | Abrir el juego: jugar con una arma, activar Berserk (Decorator), tecla **O** para invocar al Nigromante (Factory Method), enjambre de enemigos (Flyweight), probar teclado + mando/táctil (Adapter). | Proyecto |
| 13:00–14:00 | 8. Incremento | 9 patrones documentados, 17 clases nuevas, 2 eliminadas (código muerto/duplicado), pool corregido, sin cambio de comportamiento. | `01_control_cambios.md` |
| 14:00–15:00 | 9. Conclusiones | Beneficios (OCP, menos duplicación) y costes (más clases); trabajo futuro. | |

Consejo de demo: abre antes el proyecto en Godot y verifica que corre; ten el código ANTES (`git show <commit>:ruta`) y DESPUÉS en pestañas.

## Parte B · Preguntas probables de la sustentación (qué, cómo, por qué, beneficios/desventajas, antes/después)

Responde cada una con: qué problema había → cómo lo resolviste (clases/roles) → beneficio → desventaja.

1. **¿Por qué el `EnemyFactory` anterior no era realmente un Factory Method?** Era una fábrica estática con `match`; faltaban Creator/ConcreteCreator. Ahora `EnemyCreator` define `create_enemy()` y las subclases sobreescriben `_create_product()`.
2. **¿Qué ganaste con Factory Method si solo hay dos jefes?** OCP: un jefe nuevo no obliga a editar código existente; los clientes no conocen rutas ni strings. Coste: una clase por producto.
3. **¿Qué familia crea tu Abstract Factory y por qué es parcial?** Familia móvil/escritorio (entorno, viewport, luz, controles, mapa). Es parcial porque casi todo son `configure_*` y solo `create_controls` retorna un producto.
4. **¿Qué hace el Director del Builder y qué pasa con las armas que no lo usan?** Encapsula recetas (`construct_melee/ranged`). Las armas irregulares usan el Builder directo.
5. **¿Dónde se usa Prototype y por qué clonar?** En `get_weapon_table()`: los prototipos quedan intactos y el balance se aplica a clones. Espada: 12.0 vs 10.2.
6. **¿Por qué `duplicate()` basta?** `WeaponData` solo tiene primitivos/strings; una copia superficial es independiente.
7. **¿Cuál es tu Singleton y por qué eliminaste `GameManagerSingleton`?** `GameState`; el otro era un duplicado sin referencias.
8. **¿Desventajas del Singleton?** Estado global, acoplamiento, pruebas difíciles, constructor público en GDScript.
9. **¿Cómo funciona la cadena del Decorator y por qué el orden importa?** Base → Berserk → Mejoras → StatBlock; todos multiplican, así que el resultado es igual, pero el orden se conservó para no cambiar redondeos.
10. **¿Qué ventaja tiene el Decorator sobre las dos funciones anteriores?** Sin duplicación; agregar un modificador = clase nueva.
11. **¿Qué es el estado intrínseco/extrínseco en tu Flyweight?** Intrínseco: stats del tipo (compartido). Extrínseco: posición, hp actual, IA (por enemigo).
12. **¿Cuántos flyweights existen con 500 enemigos?** 6 (`EnemyTypeFlyweightFactory.pool_size()`).
13. **¿Por qué `apply_to` copia valores en vez de leer del flyweight?** Rendimiento en el bucle de enemigos; el flyweight se trata como inmutable.
14. **¿Qué adapta cada Adapter y cuál es el Adaptee?** Touch → autoload `VirtualInput`; Keyboard y Gamepad → API `Input`. Target: `MovementSource`.
15. **¿Qué cambia si añado un periférico nuevo?** Un adaptador nuevo y agregarlo a `_direct_sources`.
16. **¿Facade vs Adapter?** Facade simplifica un subsistema; Adapter convierte una interfaz a otra que espera el cliente.
17. **¿Decorator vs Strategy (ya usado en armas)?** Strategy cambia el algoritmo completo (cómo ataca); Decorator añade comportamiento apilable sobre un valor.
18. **¿Cómo comprobaste que no rompiste nada?** Proyecto abre en Godot 4.7.1 sin errores, 600 fotogramas de la escena de juego sin errores, y prueba automática de valores (daño, flyweight, prototipo, creators).
19. **Muéstrame el diagrama antes/después de un patrón a tu elección.** `03_diagramas_uml.md`.
20. **¿Qué mejorarías?** Abstract Factory con productos reales, Builder abstracto con más constructores, adaptadores también para botones de acción.
