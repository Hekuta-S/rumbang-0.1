class_name Quality
extends RefCounted

## Nivel de calidad gráfica (Bajo / Medio / Alto). Android arranca en Medio y PC en Alto; el valor
## guardado por el jugador (SettingsManager.quality_level) tiene prioridad. Todo lo que cuesta
## rendimiento (partículas, luces dinámicas, sombras, resolución 3D, tope de enemigos) consulta aquí.

enum Level { LOW, MEDIUM, HIGH }

static var _level: int = -1

## Para probar el modo móvil en PC: lanzar con la variable de entorno RUMBANG_FORCE_MOBILE=1.
static func is_mobile() -> bool:
	return OS.get_name() in ["Android", "iOS"] or OS.get_environment("RUMBANG_FORCE_MOBILE") == "1"

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

## Máximo de enemigos vivos a la vez al final de la partida. Medido en PC (banco RUMBANG_BENCH): 300 enemigos
## cuestan ~13 ms de física por tick; un móvil es varias veces más lento, así que Medio (el valor por defecto
## en Android) queda en 160 hasta validarlo en un dispositivo real.
static func alive_cap_end() -> int:
	return [100, 160, 300][level()]

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

## FPS objetivo para la resolución dinámica.
static func target_fps() -> float:
	return 45.0 if is_mobile() else 60.0

## Escala una cantidad de partículas por el nivel de calidad (mínimo 2).
static func count(n: int) -> int:
	return maxi(2, int(round(float(n) * particle_factor())))
