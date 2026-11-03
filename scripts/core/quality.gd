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
	return [0.35, 0.7, 1.0][level()]

## Máximo de enemigos vivos a la vez al final de la partida. Medido en PC simulando móvil (banco
## RUMBANG_BENCH, ver OPTIMIZACION_MOVIL.md): tras la optimización de 2026-11 la IA cuesta ~45 % menos
## (reparto por multitud, obstáculos empaquetados, rejilla con claves enteras) y 600 enemigos van a
## ~58 FPS en PC. Un móvil es 3-5 veces más lento: Medio (el valor por defecto en Android) sube de
## 160 a 220 y Alto a 320; validar en un dispositivo real antes de subir más.
static func alive_cap_end() -> int:
	if is_mobile():
		return [120, 220, 320][level()]
	return [150, 300, 500][level()]

## Números de daño flotantes a la vez (PoolManager).
static func floating_numbers_max() -> int:
	return 24 if is_mobile() else 50

## Orbes de experiencia en el suelo a la vez (LootManager: pasado el tope se suman al más reciente).
static func xp_orbs_max() -> int:
	return 50 if is_mobile() else 90

## Resolución 3D base (la gobernadora de rendimiento puede bajarla temporalmente).
static func scale_3d() -> float:
	if is_mobile():
		return [0.5, 0.65, 0.85][level()]
	return [0.7, 0.85, 1.0][level()]

## Resolución mínima que la gobernadora puede aplicar.
static func scale_3d_floor() -> float:
	return 0.5 if is_mobile() else 0.7

static func shadows_enabled() -> bool:
	return level() == Level.HIGH and not is_mobile()

static func shadow_distance() -> float:
	return 45.0

static func glow_enabled() -> bool:
	return level() == Level.HIGH and not is_mobile()

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
	return 30 if level() == Level.LOW else 60

## FPS objetivo para la resolución dinámica.
static func target_fps() -> float:
	if is_mobile():
		return 28.0 if mobile_max_fps() == 30 else 45.0
	return 60.0

## Escala una cantidad de partículas por el nivel de calidad (mínimo 2).
static func count(n: int) -> int:
	return maxi(2, int(round(float(n) * particle_factor())))
