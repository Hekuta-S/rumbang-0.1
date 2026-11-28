class_name Quality
extends RefCounted

## Nivel de calidad gráfica (Bajo / Medio / Alto). Android/móvil arranca en Bajo y PC en Alto; el valor guardado por el jugador (SettingsManager.quality_level) tiene prioridad. Todo lo que cuesta
## rendimiento (partículas, luces dinámicas, sombras, resolución 3D, tope de enemigos) consulta aquí.

enum Level { LOW, MEDIUM, HIGH }

static var _level: int = -1
## Fracción del tope de enemigos que se permite ahora (la baja PerformanceGovernor si la CPU no llega).
static var crowd_factor: float = 1.0

## Para probar el modo móvil en PC: lanzar con la variable de entorno RUMBANG_FORCE_MOBILE=1.
## Móvil: Android/iOS nativos y también el navegador de un móvil (versión web en iPhone o Android).
static func is_mobile() -> bool:
	return OS.get_name() in ["Android", "iOS"] or OS.has_feature("web_ios") or OS.has_feature("web_android") 		or OS.get_environment("RUMBANG_FORCE_MOBILE") == "1"

## SettingsManager es un autoload: se busca en el árbol (no por identificador) para que este script
## compile también cuando se carga fuera del juego (importación, pruebas).
static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SettingsManager") if tree else null

static func level() -> int:
	if _level < 0:
		var st := _settings()
		var saved: int = int(st.get("quality_level")) if st else -1
		if saved >= 0 and saved <= Level.HIGH:
			_level = saved
		elif is_mobile():
			_level = Level.LOW
		else:
			_level = Level.HIGH
		_apply_vfx()
	return _level

# ── Gama del dispositivo ───────────────────────────────────────────────
## GPUs de gama baja-media de móvil (subcadenas del nombre que da el driver, en minúsculas). Con ellas el
## juego arranca en calidad Baja y resolución reducida si el jugador no eligió otra cosa. Medido en un
## Mali-G57 MC2 (Helio G99, 2026-11-17): en Media va a ~26 FPS a escala 1.0 y en Baja llega a 30 estables.
const LOW_END_GPUS := [
	"mali-4", "mali-t", "mali-g31", "mali-g51", "mali-g52", "mali-g57",
	"adreno (tm) 3", "adreno (tm) 4", "adreno (tm) 5", "adreno (tm) 60", "adreno (tm) 610",
	"adreno (tm) 612", "adreno (tm) 613",
	"powervr", "img bxm", "img bxe",
]
## Con esta RAM o menos el móvil es de gama baja aunque la GPU no esté en la lista.
const LOW_END_RAM_GB := 4.5

static var _low_end: int = -1

## ¿Móvil de gama baja-media? Por nombre de GPU o poca RAM. Solo baja valores por defecto: nunca sube la
## calidad y lo que el jugador elige en Ajustes manda. RUMBANG_LOW_END=1/0 lo fuerza (pruebas en PC).
static func is_low_end() -> bool:
	if _low_end < 0:
		var env := OS.get_environment("RUMBANG_LOW_END")
		if env == "1" or env == "0":
			_low_end = int(env)
		elif not is_mobile():
			_low_end = 0
		else:
			_low_end = 1 if low_end_for(RenderingServer.get_video_adapter_name(), _ram_gb()) else 0
	return _low_end == 1

## Regla de gama baja, separada para probarla sin un móvil.
static func low_end_for(gpu_name: String, ram_gb: float) -> bool:
	var g := gpu_name.to_lower()
	for k in LOW_END_GPUS:
		if g.contains(k):
			return true
	return ram_gb > 0.0 and ram_gb <= LOW_END_RAM_GB

static func _ram_gb() -> float:
	var info := OS.get_memory_info()
	return float(info.get("physical", -1)) / 1073741824.0 if int(info.get("physical", -1)) > 0 else -1.0

## Resolución cuando el jugador no eligió (SettingsManager.resolution == -1): reducida en gama baja.
static func auto_resolution() -> int:
	return RES_REDUCED if is_mobile() and is_low_end() else RES_NATIVE

static func set_level(l: int) -> void:
	_level = clampi(l, Level.LOW, Level.HIGH)
	_apply_vfx()
	var st := _settings()
	if st:
		st.set("quality_level", _level)
		st.call("save_settings")

## Enemigos como impostores (sprites con varios ángulos): por defecto en móvil. Se puede forzar con la
## variable de entorno RUMBANG_IMPOSTORS=1 (activar) o 0 (desactivar).
static func use_impostors() -> bool:
	var env := OS.get_environment("RUMBANG_IMPOSTORS")
	if env == "1":
		return true
	if env == "0":
		return false
	return is_mobile()

## Pasa el nivel a los shaders de efectos (uniforme global vfx_quality): menos octavas de ruido y capas.
static func _apply_vfx() -> void:
	RenderingServer.global_shader_parameter_set("vfx_quality", _level)

static func level_name() -> String:
	return ["Bajo", "Medio", "Alto"][level()]

## Multiplicador de cantidad de partículas.
static func particle_factor() -> float:
	if is_mobile():
		return [0.25, 0.5, 0.75][level()]   # CPUParticles: coste en CPU por partícula, el móvil va justo
	return [0.35, 0.7, 1.0][level()]

## Máximo de enemigos vivos a la vez al final de la partida. Medido en PC simulando móvil (banco
## RUMBANG_BENCH, ver OPTIMIZACION_MOVIL.md): tras la optimización de 2026-11 la IA cuesta ~45 % menos
## (reparto por multitud, obstáculos empaquetados, rejilla con claves enteras) y 600 enemigos van a
## ~58 FPS en PC. Medido en un móvil real (Mali-G57 / Helio G99, 2026-11-17, con el movimiento en C++):
## 420 enemigos van a 39.4 FPS sin tope frente a 39.9 con 300, y con el tope de 30 FPS se mantienen en
## 28-30 (en calidad Baja). Todas las calidades llegan a 420; el gobernador quita enemigos si
## un móvil más lento no da abasto (Quality.crowd_factor).
static func alive_cap_end() -> int:
	# Ritmo más pausado (menos enemigos por segundo): antes 420 / 500
	if is_mobile():
		return [220, 220, 220][level()]
	return [220, 220, 260][level()]

## Números de daño flotantes a la vez (PoolManager).
static func floating_numbers_max() -> int:
	return 24 if is_mobile() else 50

## Orbes de experiencia en el suelo a la vez (LootManager: pasado el tope se suman al más reciente).
static func xp_orbs_max() -> int:
	return 50 if is_mobile() else 90

## Resolución 3D base (la gobernadora de rendimiento puede bajarla temporalmente).
## Con una resolución fija (1080p, 900p, 720p, 540p) manda esa altura y no la calidad.
static func scale_3d() -> float:
	var h := fixed_height()
	if h > 0:
		return _fixed_scale(h)
	var s: float = [0.5, 0.65, 0.85][level()] if is_mobile() else [0.7, 0.85, 1.0][level()]
	return minf(1.0, s * _res_boost())

## Resolución mínima que la gobernadora puede aplicar.
static func scale_3d_floor() -> float:
	var h := fixed_height()
	if h > 0:
		return _fixed_scale(h) * 0.7      # con resolución fija la gobernadora solo puede bajar un 30 %
	return minf(1.0, (0.5 if is_mobile() else 0.7) * _res_boost())

# ── Resolución de pantalla ─────────────────────────────────────────────
## 0 = nativa: la interfaz se dibuja a la resolución de la pantalla (stretch "canvas_items").
## 1 = reducida: TODO (3D e interfaz) se dibuja a la resolución base del proyecto (1280×720, ampliada al
## formato de la pantalla) y se escala al mostrarlo. En un móvil de 2460×1080 son ~2.2 veces menos píxeles
## para la interfaz y la copia final; el texto se ve algo más suave.
## La escala 3D se compensa (_res_boost) para que el 3D no pierda más detalle que en nativa.
## 2-5 = resolución fija: interfaz como en "reducida" (base 720p) y el 3D a esa altura exacta de píxeles
## (1080/900/720/540 filas), sin importar la calidad. Nunca por encima de la pantalla (sin supermuestreo).
const RES_NATIVE := 0
const RES_REDUCED := 1
const RES_1080 := 2
const RES_900 := 3
const RES_720 := 4
const RES_540 := 5
const RES_HEIGHTS := {RES_1080: 1080, RES_900: 900, RES_720: 720, RES_540: 540}
const RES_COUNT := 6
static var _res_mode := RES_NATIVE

static func resolution_mode() -> int:
	return _res_mode

## Altura 3D fija del modo actual (0 = la decide la calidad).
static func fixed_height() -> int:
	return int(RES_HEIGHTS.get(_res_mode, 0))

## Modos que tienen sentido en esta pantalla: se omiten las alturas fijas que no caben (en un móvil de
## 1080 filas, 1080p sería igual que la pantalla y sí se ofrece; 1440p no existe).
static func resolution_modes_available() -> Array[int]:
	var out: Array[int] = [RES_NATIVE, RES_REDUCED]
	var screen_h := _screen_height()
	for m in [RES_1080, RES_900, RES_720, RES_540]:
		if screen_h <= 0 or int(RES_HEIGHTS[m]) <= screen_h:
			out.append(m)
	return out

static func resolution_label(mode: int) -> String:
	match mode:
		RES_NATIVE: return "Nativa"
		RES_REDUCED: return "Reducida (más FPS)"
	return "%dp" % int(RES_HEIGHTS.get(mode, 720))

static func apply_resolution(mode: int) -> void:
	_res_mode = mode if mode >= 0 and mode < RES_COUNT else RES_NATIVE
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var win := tree.root
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if _res_mode == RES_NATIVE else Window.CONTENT_SCALE_MODE_VIEWPORT
	win.scaling_3d_scale = scale_3d()

## Escala 3D para dibujar `h` filas: relativa al viewport (720 filas en modo viewport), sin pasar de la
## pantalla. Godot admite hasta 2.0 (por encima de 1.0 el 3D tiene más píxeles que la interfaz).
static func _fixed_scale(h: int) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1.0
	var vis_h := maxf(tree.root.get_visible_rect().size.y, 1.0)
	var screen_h := _screen_height()
	var rows := float(h) if screen_h <= 0 else minf(float(h), float(screen_h))
	return clampf(rows / vis_h, 0.25, 2.0)

## Filas reales de la ventana (lado corto en apaisado).
static func _screen_height() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	return tree.root.size.y

## Cuánto más pequeño es el viewport que la ventana (1 en nativa): la escala 3D se multiplica por esto.
static func _res_boost() -> float:
	if _res_mode == RES_NATIVE:
		return 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1.0
	var vis := tree.root.get_visible_rect().size.x
	return maxf(1.0, float(tree.root.size.x) / maxf(vis, 1.0))

static func shadows_enabled() -> bool:
	return level() == Level.HIGH and not is_mobile()

static func shadow_distance() -> float:
	return 45.0

## AA de pantalla en móvil: FXAA solo en Alta. Medido en un Mali-G57 (2026-11-16, 300 enemigos, escala 1.0):
## FXAA + debanding costaban ~9.5 ms por frame (20.0 -> 24.7 FPS al quitarlos). A 396 ppp el dentado apenas se ve.
static func mobile_aa() -> Viewport.ScreenSpaceAA:
	return Viewport.SCREEN_SPACE_AA_FXAA if level() == Level.HIGH else Viewport.SCREEN_SPACE_AA_DISABLED

static func glow_enabled() -> bool:
	return level() == Level.HIGH and not is_mobile()

## Ajusta una escena con su propio Environment (salón, patio, fondo del título) a la misma política que
## la mazmorra: sin glow ni SSAO en móvil, FXAA, resolución 3D por calidad. `vp` puede ser null.
static func tune_environment(env: Environment, vp: Viewport = null) -> void:
	env.glow_enabled = glow_enabled()
	if is_mobile():
		env.ssao_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
	if vp:
		vp.scaling_3d_scale = scale_3d()
		if is_mobile():
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = mobile_aa()
			vp.use_debanding = false

## Sombras de una luz solo donde se permiten (PC en calidad Alta).
static func tune_light(l: Light3D, wants_shadow: bool = true) -> void:
	l.shadow_enabled = wants_shadow and shadows_enabled()

## Gobernador de resolución dinámica para escenas fuera de GameStartFacade (salón, patio).
static func add_governor(parent: Node, vp: Viewport) -> void:
	var g := PerformanceGovernor.new()
	g.name = "PerformanceGovernor"
	parent.add_child(g)
	g.setup(vp)

## Luces dinámicas de efectos (destellos, impactos, aura). En Bajo se crean invisibles (coste ~0).
static func lights_enabled() -> bool:
	return level() >= Level.MEDIUM

## Luz propia de cada bala: solo en PC con calidad Alta.
static func bullet_lights() -> bool:
	return level() == Level.HIGH and not is_mobile()

## Crea una OmniLight3D respetando el nivel de calidad (invisible si las luces están desactivadas).
static func new_light() -> OmniLight3D:
	var l := OmniLight3D.new()
	l.shadow_enabled = false
	l.visible = lights_enabled()
	return l

## Tope de FPS en móvil: 60, o 30 en calidad Baja (batería y temperatura: un móvil caliente baja de
## frecuencia y acaba yendo peor que a 30 estables).
static func mobile_max_fps() -> int:
	var st := _settings()
	var saved: int = int(st.get("mobile_fps")) if st else 0
	if saved == 30 or saved == 60:
		return saved
	return 30 if level() == Level.LOW else 60

## Guarda el tope de FPS del móvil (0 = automático) y lo aplica ya.
static func set_mobile_fps(v: int) -> void:
	var st := _settings()
	if st:
		st.set("mobile_fps", v if v == 30 or v == 60 else 0)
		st.call("save_settings")
	if is_mobile():
		Engine.max_fps = mobile_max_fps()

## Activa o desactiva el V-Sync. En PC, desactivado = sin V-Sync. En Android se pide "mailbox" (no espera al
## refresco y no hay tearing): muchos Android no admiten "sin V-Sync" y Godot vuelve a activarlo en silencio
## aunque window_get_vsync_mode() diga lo contrario (medido en un Helio G99, 2026-11-17: allí mailbox tampoco
## cambió los FPS). Devuelve false si el modo no quedó aplicado.
static func apply_vsync(on: bool) -> bool:
	if on:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		return true
	var mode := DisplayServer.VSYNC_MAILBOX if OS.has_feature("mobile") else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)
	return DisplayServer.window_get_vsync_mode() == mode

## FPS objetivo para la resolución dinámica.
static func target_fps() -> float:
	if is_mobile():
		return 28.0 if mobile_max_fps() == 30 else 45.0
	return 60.0

## Escala una cantidad de partículas por el nivel de calidad (mínimo 2).
static func count(n: int) -> int:
	return maxi(2, int(round(float(n) * particle_factor())))
