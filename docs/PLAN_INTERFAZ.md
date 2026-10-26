# Plan — Rediseño de interfaz (menú inicial + selección de personaje)

## Estado actual (lo que encontré)
- `scripts/ui/main_menu.gd` (268 líneas): UI 100 % por código, fondo plano `ColorRect`, título **"SOUL KNIGHT 3D"** (nombre viejo), botones Jugar / Mejoras / Opciones / Salir.
- `scripts/ui/character_select.gd` (335 líneas): una sola ficha con flechas ◀ ▶, retrato = `ColorRect` con una letra. Sin modelo 3D.
- `GameData.CHARACTERS` tiene 11 héroes con `name, subtitle, lore, color, stats, passive_name/desc, initial_weapons` (si falta `initial_weapons` el arma es la **Espalanza**).
- Los modelos 3D de los héroes son `.fbx` con idle (`assets/models/<id>/…-idle.fbx`), y `PlayerAnimationController` ya sabe resolver modelo + textura por personaje (Kaionz y Crane comparten `cray`).
- El mapa procedural ya existe (`scenes/core/main_procedural.tscn`, `ProceduralMap`), así que puede reutilizarse como fondo.

## Fase 1 — Fondo panorámico estilo Minecraft + título RUMBANG
1. **Escena `scenes/ui/menu_background.tscn`** (nueva, reutilizable): `SubViewport`-less, un `Node3D` con:
   - `ProceduralMap` con **semilla fija** (para que el panorama sea siempre el mismo y bonito) y `embers_enabled`, sin jugador/HUD/enemigos.
   - Cámara que **orbita lentamente** (≈ 1 vuelta/90 s) a ~6 m de altura mirando al centro de la plaza o a la cripta; opcional: ligero vaivén vertical.
   - Mismo `WorldEnvironment` y luna del mapa (niebla, brasas, luces parpadeantes).
2. **`main_menu.gd`**: sustituir el `ColorRect` de fondo por la escena anterior (en un `SubViewportContainer` con `stretch` o directamente como `Node3D` detrás de la UI `CanvasLayer`); viñeta oscura (`TextureRect` con gradiente radial) + fundido a negro al pulsar *Jugar*.
3. **Título "RUMBANG"**: cambiar el texto, usar la fuente `PressStart2P` ya incluida (`assets/fonts`), con sombra/contorno y un shader sencillo de brillo (`title_glow.gdshader`, en el estilo de los shaders de ataques). Subtítulo: *"Dark Fantasy Roguelike"*. Quitar "SOUL KNIGHT 3D" también de otros textos/ajustes (`config/name` está en "tesis").
4. Pulir botones (paleta dark fantasy: violeta arcano/ámbar de brasas en lugar del azul actual) y música/sfx de hover si existen.
- **Aceptación:** el menú muestra el mapa girando con niebla y brasas, título RUMBANG legible, 60 fps en PC; en móvil el fondo baja a 50 % de densidad (`ProceduralMap` ya lo hace) o cae a imagen estática.

## Fase 2 — Selección de personajes en una sola vista
Layout (1280×720, escala con anclas):
```
┌──────────────────────────────┬───────────────────────────────┐
│  ELIGE A TU HÉROE            │      [ PREVIEW 3D del héroe ] │
│  ┌──┐┌──┐┌──┐┌──┐            │       (gira con el mouse)     │
│  │M ││H ││V ││B │  cuadrícula│  Nombre — subtítulo           │
│  ├──┤├──┤├──┤├──┤  4×3       │  PASIVA: nombre + descripción │
│  │C ││K ││T ││J │  celdas    │  ARMA: icono + nombre         │
│  ├──┤├──┤├──┤├──┤  ~96 px    │  Stats: vida/escudo/energía/  │
│  │R ││G ││S ││  │            │         velocidad             │
│  └──┘└──┘└──┘└──┘            │   [  COMENZAR PARTIDA  ]      │
│  [← Volver]                  │                               │
└──────────────────────────────┴───────────────────────────────┘
```
1. **Cuadrícula** (`GridContainer`, 4 columnas, 11 celdas): cada celda = botón cuadrado con miniatura + nombre corto; borde del color del héroe, resalte al hover/selección, foco por teclado/mando (flechas / D-pad).
2. **Miniaturas**: generarlas una vez a partir del mismo preview 3D (render a `ViewportTexture` en caché) o, como primera versión, usar la inicial + color actual (ya existe) y sustituir luego.
3. **Preview 3D** (`scenes/ui/character_preview.tscn`): `SubViewportContainer` + `SubViewport` (transparente) con `Node3D`, cámara fija, luz de relleno + contraluz del color del héroe, suelo circular tenue. Carga el idle `.fbx` del personaje (misma tabla de rutas que `PlayerAnimationController`: extraerla a `GameData` para no duplicarla) y le aplica la textura `assets/textures/entities/<id>/texture_<id>.png`. Reproduce la animación idle en bucle; rotación con arrastre del mouse; al cambiar de héroe, fundido corto.
4. **Panel de detalle** (abajo-derecha): pasiva (`passive_name` + `passive_desc` con el color de la pasiva), **arma principal** (primer elemento de `initial_weapons`, o Espalanza por defecto → nombre e icono desde `WeaponData.weapon_names/weapon_icons`), stats base y botón **COMENZAR PARTIDA** (el actual `_on_select`).
5. Navegación: clic/teclado para elegir; doble clic o Enter = comenzar; Esc = volver al menú; botón *Volver*.
- **Aceptación:** los 11 héroes visibles a la vez sin scroll, cambiar de héroe actualiza modelo/pasiva/arma al instante, comenzar carga el mapa con ese héroe.

## Fase 3 — Consistencia y limpieza
- Extraer los colores/estilos repetidos (`C_BG`, `_btn_style`…) a un `Theme` (`themes/rumbang_theme.tres`) compartido por menú, selección, pausa y HUD.
- Aplicar el mismo tema al menú de pausa y a las pantallas de objetos/mejoras.
- Revisar la pantalla de carga con el nombre/estilo nuevos.

## Riesgos y decisiones abiertas
| Tema | Riesgo | Mitigación |
|---|---|---|
| Rendimiento del fondo 3D en móvil | Terreno + props + luces detrás del menú | Misma lógica móvil de `ProceduralMap`; opción de imagen estática |
| Modelos `.fbx` en un `SubViewport` | Animación/escala distintas por héroe | Reusar `_fit_model()` del controlador de animación; probar los 11 uno por uno |
| Héroes sin textura propia (Kaionz/Crane usan `cray`) | Se verían iguales | Aceptable por ahora; el color de acento y el nombre los diferencian |
| Texto del título | Fuente pixel puede no tener "ñ/á" | RUMBANG solo usa letras ASCII |

## Orden de trabajo propuesto (pasos pequeños, cada uno probable por separado)
1. Título RUMBANG + paleta + fuente (cambio rápido, sin 3D).
2. Escena de fondo panorámico y cámara orbital, integrada al menú.
3. Cuadrícula de selección (sin preview) con panel de detalle de pasiva/arma/botón.
4. Preview 3D del héroe en la derecha.
5. Miniaturas, tema compartido y pulido.

## Preguntas para ti
1. ¿Qué **vista** prefieres para el panorama: la plaza de inicio con brasas, la cripta morada, o que alterne entre ambas cada cierto tiempo?
2. ¿La cuadrícula con **inicial + color** como miniatura está bien para la primera versión, o prefieres que ya sean retratos del modelo 3D?
3. ¿Dejo **Mejoras** y **Opciones** en el menú principal tal como están (solo rediseñados)?
