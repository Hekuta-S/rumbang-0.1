class_name PerformanceGovernor
extends Node

## Resolución 3D dinámica: si los FPS se quedan por debajo del objetivo la baja poco a poco (hasta un
## mínimo) y, cuando hay margen, la vuelve a subir hasta la resolución base de la calidad elegida.

const CHECK_INTERVAL := 1.0
const STEP_DOWN := 0.05
const STEP_UP := 0.025

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
		Engine.max_fps = 60
	# Móvil o calidad Baja: 30 ticks de física por segundo en vez de 40 (la interpolación suaviza el dibujado)
	Engine.physics_ticks_per_second = 30 if (Quality.is_mobile() or Quality.level() == Quality.Level.LOW) else 40
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
	if fps < target * 0.85:
		cur = maxf(cur - STEP_DOWN, floor_scale)
	elif fps > target * 0.97 and cur < base:
		cur = minf(cur + STEP_UP, base)
	if not is_equal_approx(cur, _viewport.scaling_3d_scale):
		_viewport.scaling_3d_scale = cur
