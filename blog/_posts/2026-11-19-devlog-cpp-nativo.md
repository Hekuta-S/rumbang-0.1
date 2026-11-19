---
layout: post
title: "Devlog técnico: cientos de goblins en C++"
tag: Técnico
cover: /static/img/lod_enemigos_primer_plano.jpg
cover_alt: "Enjambre de goblins con niveles de detalle según la distancia"
---

El modo supervivencia vive de las hordas. En PC eso no era un problema, pero en un teléfono Android de gama media el bucle de los enemigos se comía buena parte de cada frame. Esta entrada cuenta cómo pasamos ese bucle de GDScript a C++.

## Antes de tocar C++

Primero exprimimos GDScript. Los enemigos ya no son nodos de Godot: son datos en un arreglo, se mueven con una física propia y se dibujan con un solo `MultiMesh` por tipo, con animaciones horneadas en texturas y niveles de detalle según la distancia. En el teléfono, los lejanos se dibujan como impostores, que son imágenes planas.

Con eso y varias pasadas de perfilado, el tiempo del bucle de enemigos en supervivencia bajó de 4,8 a 3,7 ms por tick. Seguía siendo mucho para un teléfono.

## La extensión nativa

Godot permite escribir clases en C++ con **GDExtension** y usarlas desde GDScript como si fueran nativas. La migración se hizo en dos pasos.

### Paso 1: el movimiento

Primero se portó solo `EnemyMotion.move`, la función que mueve a cada enemigo, lo choca contra el terreno y los obstáculos y lo separa de los demás. Una prueba compara la versión C++ con la de GDScript en 16 000 pasos y exige que el resultado sea idéntico.

| Movimiento por paso | Tiempo |
|---|---|
| GDScript | 15,6 µs |
| C++ | 6,0 µs |

### Paso 2: toda la simulación

Después se portó el bucle completo del gestor de enemigos: temporizadores, la IA de los seis tipos de goblin, la "mente colmena" que reparte quién ataca, la separación, el movimiento y el llenado de los buffers de los impostores.

El reto fue la frontera entre los dos lenguajes. C++ escribe de vuelta en los datos del enemigo, y los disparos, golpes y morteros vuelven como eventos que ejecuta GDScript. Cualquier cambio externo, como un empujón o una ralentización, tiene que pasar por funciones que avisan a la simulación nativa.

| 300 enemigos en PC | ms por tick |
|---|---|
| GDScript | 1,66 |
| C++ | 0,30 |

## Siempre con red de seguridad

Si la librería nativa no está, por ejemplo en la exportación web, el juego usa la versión GDScript sin cambiar nada más. También se puede apagar con una variable de entorno, lo que facilita comparar las dos versiones en el mismo equipo.

> El número que importa todavía falta: la ganancia real en el teléfono. Eso irá en la próxima entrada técnica.

## Y la interfaz

En paralelo revisamos las llamadas de dibujo en el teléfono. Los controles táctiles se dibujaban con un círculo o un arco por llamada. Al hornearlos en un atlas una sola vez, las llamadas de dibujo en supervivencia sin enemigos bajaron de 221 a 69.

![HUD móvil con los controles táctiles]({{ '/static/img/ui_hud_movil.jpg' | relative_url }})
