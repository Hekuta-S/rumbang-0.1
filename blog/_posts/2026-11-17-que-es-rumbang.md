---
layout: post
title: "¿Qué es Rumbang?"
tag: Presentación
cover: /static/img/supervivencia_despues.jpg
cover_alt: "El personaje en el mapa de supervivencia, con antorchas y la arena del jefe al fondo"
---

Rumbang es un roguelite de acción en tercera persona, en 3D, hecho en Godot con GDScript. Se juega en PC y en Android. Mezcla hordas de enemigos, combate cuerpo a cuerpo con peso y un estilo visual de cómic: contornos de tinta, colores planos y onomatopeyas que saltan en cada golpe.

## Dos formas de jugar

### Supervivencia

Un mapa abierto y procedural, con mesetas, rampas, puentes y toboganes. Las hordas de goblins crecen con el tiempo. Ganas experiencia, eliges mejoras y aguantas hasta que aparece el Nigromante, el jefe final. Es la parte *bullet-heaven* del juego: muchos enemigos a la vez y una build que crece en cada partida.

### Mazmorras

Cuevas y cloacas generadas por niveles, con enemigos de élite, botín con rarezas y un jefe al final. Aquí el combate es más lento y preciso, al estilo *souls*: esquivas, fijas el objetivo, administras la estamina y gastas las almas en subir de nivel.

![Combate en las cavernas, con onomatopeyas de cómic]({{ '/static/img/onomatopeyas_en_juego.jpg' | relative_url }})
<span class="caption">Cada golpe dibuja su onomatopeya: ¡TAJO!, ¡CHAS!, ¡PUM!</span>

## El salón

El menú principal no es un menú: es un salón por el que caminas. Desde ahí entras a los portales de las mazmorras, mejoras las armas en el yunque, compras equipo en la forja y subes de nivel con las almas que trajiste.

## Armas

Cada arma tiene su propio combo, sus animaciones y su ataque especial:

- **Espalanza**, la lanza original del juego, que también se puede lanzar.
- **Espadón** y **espada**, de golpes amplios.
- **Dagas**, rápidas y de combo largo.
- **Maza**, lenta y pesada.
- **Arco**, con disparo cargado.
- **Katana**, el arma mítica.
- **Puños**, con una ráfaga de golpes como especial.

## Estilo cómic

Todo el juego pasó por una capa de "tinta": texturas con el contorno horneado, enemigos con borde negro, interfaz con sombras duras y un dado del destino que puede salvarte la partida o arruinarla.

![El dado del destino]({{ '/static/img/dado_del_destino.jpg' | relative_url }})

## Qué viene en este blog

Aquí iremos contando el desarrollo: qué se añade, qué se rompe y cómo se arregla. Habrá entradas de diseño y entradas técnicas, sobre todo de optimización, porque el juego tiene que mover cientos de enemigos en un teléfono.
