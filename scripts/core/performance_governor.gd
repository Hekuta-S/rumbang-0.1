class_name PerformanceGovernor
extends Node

## Resolución 3D dinámica: si los FPS se quedan por debajo del objetivo la baja poco a poco (hasta un
## mínimo) y, cuando hay margen, la vuelve a subir hasta la resolución base de la calidad elegida.
## Si con la resolución ya en el mínimo sigue sin llegar, el cuello de botella es la CPU (IA de cientos
## de enemigos, típico de un móvil caliente): baja el tope de enemigos vivos (Quality.crowd_factor)
## hasta CROWD_FLOOR y lo recupera despacio cuando sobra margen.

const CHECK_INTERVAL := 1.0
const STEP_DOWN := 0.05
const STEP_UP := 0.025
const MAX_PHYSICS_STEPS_MOBILE := 2
const MAX_PHYSICS_STEPS_PC := 4
const CROWD_STEP_DOWN := 0.1
const CROWD_STEP_UP := 0.05
const CROWD_FLOOR := 0.6
const CROWD_SLOW_CHECKS := 3          ## comprobaciones seguidas lentas (y sin resolución que bajar) antes de quitar enemigos
const CROWD_FAST_CHECKS := 5          ## comprobaciones seguidas con margen antes de devolverlos
var _slow_checks := 0
var _fast_checks := 0

var _viewport: Viewport
var _timer := 0.0
var _frames := 0
var _time := 0.0

func setup(viewport: Viewport) -> void:
	_viewport = viewport
	# LOD de mallas más agresivo (píxeles de error aceptados antes de cambiar de nivel): menos
	# polígonos en enemigos y props lejanos. Más agresivo en móvil.
	viewport.mesh_lod_threshold = 4.0 if Quality.is_mobile() else 2.0
	# Filtrado anisotrópico: solo cuesta en PC con calidad Media/Alta (en móvil y calidad Baja, desactivado)
	if Quality.is_mobile() or Quality.level() == Quality.Level.LOW:
		viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
	# Móvil: tope de 60 FPS (pantallas de 90/120 Hz gastarían batería y calentarían sin necesidad)
	if Quality.is_mobile():
		Engine.max_fps = Quality.mobile_max_fps()
	Quality.crowd_factor = 1.0
	# Móvil o calidad Baja: 30 ticks de física por segundo en vez de 40 (la interpolación suaviza el dibujado)
	Engine.physics_ticks_per_second = 30 if (Quality.is_mobile() or Quality.level() == Quality.Level.LOW) else 40
	# Sin "espiral de la muerte": si un frame va lento, Godot repite la física hasta 8 veces para
	# ponerse al día y el frame siguiente es aún más lento. Mejor que el juego vaya un poco más
	# lento un instante que encadenar tirones.
	Engine.max_physics_steps_per_frame = MAX_PHYSICS_STEPS_MOBILE if Quality.is_mobile() else MAX_PHYSICS_STEPS_PC
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if _viewport == null or get_tree().paused:
		return
	_frames += 1
	_time += delta
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	var fps := float(_frames) / maxf(_time, 0.001)
	_timer = 0.0
	_frames = 0
	_time = 0.0

	var target := Quality.target_fps()
	var base := Quality.scale_3d()
	var floor_scale := minf(Quality.scale_3d_floor(), base)
	var cur := _viewport.scaling_3d_scale
	var at_floor := cur <= floor_scale + 0.001
	if fps < target * 0.85:
		cur = maxf(cur - STEP_DOWN, floor_scale)
	elif fps > target * 0.97 and cur < base:
		cur = minf(cur + STEP_UP, base)
	if not is_equal_approx(cur, _viewport.scaling_3d_scale):
		_viewport.scaling_3d_scale = cur
	_update_crowd(fps, target, at_floor)

## Tope de enemigos según la CPU: solo baja si la resolución ya no puede bajar más.
func _update_crowd(fps: float, target: float, at_floor: bool) -> void:
	if fps < target * 0.8 and at_floor:
		_slow_checks += 1
		_fast_checks = 0
		if _slow_checks >= CROWD_SLOW_CHECKS:
			_slow_checks = 0
			Quality.crowd_factor = maxf(Quality.crowd_factor - CROWD_STEP_DOWN, CROWD_FLOOR)
	elif fps > target * 0.97:
		_fast_checks += 1
		_slow_checks = 0
		if _fast_checks >= CROWD_FAST_CHECKS:
			_fast_checks = 0
			Quality.crowd_factor = minf(Quality.crowd_factor + CROWD_STEP_UP, 1.0)
	else:
		_slow_checks = 0
		_fast_checks = 0
