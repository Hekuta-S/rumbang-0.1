---
layout: post
title: "Devlog: mapas vivos, puños, almas y estilo cómic"
tag: Devlog
cover: /static/img/cavernas_despues.jpg
cover_alt: "Las cavernas después del pase de estilo cómic"
---

La última actualización grande junta varias semanas de trabajo. El tema principal es que los mapas dejen de sentirse como un decorado quieto y empiecen a reaccionar a lo que haces.

## Mapas vivos

### Sonido de ambiente

Cada mundo tiene ahora su propio ambiente en bucle. Las fogatas y los hongos suenan desde su posición en 3D, y alrededor del jugador aparecen sonidos sueltos: gotas, viento, crujidos. Todo pasa por un bus de audio propio, para poder bajarlo sin tocar la música ni los golpes.

### El mapa reacciona

- La hierba se aparta cuando pasas por encima.
- Los hongos brillan y sueltan esporas cuando te acercas.
- En las cloacas, el agua hace anillos donde pisas.
- Las luces tiemblan con los ataques y las esquivas.

Detrás de esto hay dos valores globales de shader, la posición del jugador y un "pulso" del mundo, que cualquier material puede leer. Así un efecto nuevo no necesita un script por cada objeto.

### Fauna y rutinas

Después llegaron los animales de ambiente y las rutinas de los enemigos. Cuando te asomas a una caverna, la sala ya está habitada: unos goblins charlan junto a la hoguera, otros duermen y roncan, otros hacen la ronda o vigilan la entrada de un túnel.

Cada rutina oye y ve distinto. Por la espalda te oyen menos, y si corres, más. Un ruido cercano los pone en alerta unos segundos. Y si golpeas a uno que todavía no te ha visto, es una emboscada: el golpe hace más daño, y mucho más si estaba dormido.

## Puños

Los puños son una arma más, con su propio combo de cuatro golpes y versiones en espejo para alternar las manos. Si dejas de pelear un momento, el personaje pasa a una guardia de boxeo. El clic derecho lanza una ráfaga de golpes.

![Onomatopeyas de la maza y los puños]({{ '/static/img/onomatopeyas_maza_punos.jpg' | relative_url }})

## Almas

En las mazmorras, los enemigos sueltan almas. En el yunque del salón las gastas en subir estadísticas, como en un *souls*. La cámara también cambió: ahora va centrada detrás del personaje, con la opción de volver a la vista sobre el hombro.

## Slide

En supervivencia puedes deslizarte con Ctrl. En las rampas el deslizamiento acelera con la pendiente, y si caes desde una meseta haces un golpe de caída que empuja a los enemigos.

## Estilo cómic

El pase de tinta llegó a casi todo: mapas, personaje, armas, interfaz y minimapa. Los golpes muestran onomatopeyas dibujadas, y en el mapa aparece a veces el dado del destino, que da un efecto bueno o malo por un tiempo.

![Goblins antes y después del contorno de tinta]({{ '/static/img/enemigos_movil_antes_despues.jpg' | relative_url }})
<span class="caption">Arriba, el goblin original. Abajo, con el contorno de tinta.</span>

## Lo que sigue

Faltan dos fases de los mapas vivos: la atmósfera (niebla, clima, partículas) y los mapas que cambian durante la partida.
