class_name Quality
extends RefCounted

## Nivel de calidad gráfica (Bajo / Medio / Alto). Android arranca en Medio y PC en Alto; el valor
## guardado por el jugador (SettingsManager.quality_level) tiene prioridad. Todo lo que cuesta
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
		else:
			_level = Level.MEDIUM if is_mobile() else Level.HIGH
		_apply_vfx()
	return _level

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
	if is_mobile():
		return [420, 420, 420][level()]
	return [420, 420, 500][level()]

## Números de daño flotantes a la vez (PoolManager).
static func floating_numbers_max() -> int:
	return 24 if is_mobile() else 50

## Orbes de experiencia en el suelo a la vez (LootManager: pasado el tope se suman al más reciente).
static func xp_orbs_max() -> int:
	return 50 if is_mobile() else 90

## Resolución 3D base (la gobernadora de rendimiento puede bajarla temporalmente).
static func scale_3d() -> float:
	var s: float = [0.5, 0.65, 0.85][level()] if is_mobile() else [0.7, 0.85, 1.0][level()]
	return minf(1.0, s * _res_boost())

## Resolución mínima que la gobernadora puede aplicar.
static func scale_3d_floor() -> float:
	return minf(1.0, (0.5 if is_mobile() else 0.7) * _res_boost())

# ── Resolución de pantalla ─────────────────────────────────────────────
## 0 = nativa: la interfaz se dibuja a la resolución de la pantalla (stretch "canvas_items").
## 1 = reducida: TODO (3D e interfaz) se dibuja a la resolución base del proyecto (1280×720, ampliada al
## formato de la pantalla) y se escala al mostrarlo. En un móvil de 2460×1080 son ~2.2 veces menos píxeles
## para la interfaz y la copia final; el texto se ve algo más suave.
## La escala 3D se compensa (_res_boost) para que el 3D no pierda más detalle que en nativa.
const RES_NATIVE := 0
const RES_REDUCED := 1
static var _res_mode := RES_NATIVE

static func resolution_mode() -> int:
	return _res_mode

static func apply_resolution(mode: int) -> void:
	_res_mode = RES_REDUCED if mode == RES_REDUCED else RES_NATIVE
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var win := tree.root
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if _res_mode == RES_REDUCED else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.scaling_3d_scale = scale_3d()

## Cuánto más pequeño es el viewport que la ventana (1 en nativa): la escala 3D se multiplica por esto.
static func _res_boost() -> float:
	if _res_mode != RES_REDUCED:
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
