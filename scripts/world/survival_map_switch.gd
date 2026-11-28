class_name SurvivalMapSwitch
extends Node

## Portal entre mapas de Supervivencia: a mitad de partida se abre un portal en un sitio al azar del mapa
## (lejos del jugador) que lleva al otro mapa (Bosque <-> Cloacas, ver GameData.SURVIVAL_MAPS). Cruzarlo
## regenera el ProceduralMap en el sitio con el otro tema sin cortar la partida: el tiempo, el nivel, las
## armas y los tomos siguen; la horda se queda atrás y las gemas de experiencia te siguen.
##  - Se abre a FIRST s y luego cada GAP s después de cerrarse; dura OPEN s abierto.
##  - No se abre con el jefe vivo ni en los últimos BOSS_MARGIN s antes de que salga.
## Lo crea GameStartFacade (solo en Supervivencia); `switched` avisa para rehacer la vida del mapa.

signal switched(theme: String)
signal opened(at: Vector3)

const FIRST := 120.0
const OPEN := 55.0
const GAP := 140.0
const BOSS_MARGIN := 45.0
const SPOT_DIST := Vector2(28.0, 55.0)       ## m del jugador a los que aparece
const PORTAL_COLORS := {"forest": Color(0.45, 1.0, 0.35), "sewers": Color(1.0, 0.62, 0.25)}  ## color = mapa de destino
const BEAM_H := 40.0

var map: ProceduralMap
var player: Node3D
var waves: WaveManager
var portal: DungeonPortal = null
var _beam: MeshInstance3D = null
var _next_open := FIRST
var _close_at := INF
var _switching := false
var _rng := RandomNumberGenerator.new()
var switches := 0                             ## veces que se ha cruzado en esta partida (pruebas)

func setup(p_map: ProceduralMap, p_player: Node3D, p_waves: WaveManager) -> void:
	map = p_map
	player = p_player
	waves = p_waves
	_rng.randomize()
	reset()

## Partida nueva: sin portal y el primero a FIRST s.
func reset() -> void:
	_close()
	_next_open = FIRST
	_close_at = INF
	_switching = false
	switches = 0

func _elapsed() -> float:
	var gs := GameState.get_instance()
	return gs.elapsed_time if gs else 0.0

## ¿Se puede abrir ahora? (no con el jefe en juego ni justo antes de que salga)
func can_open(t: float) -> bool:
	if waves == null:
		return true
	if is_instance_valid(waves._boss):
		return false
	if not waves.endless and t > WaveManager.BOSS_TIME_S - BOSS_MARGIN:
		return false
	return waves._running or waves.endless

func _process(_delta: float) -> void:
	if _switching or map == null or not is_instance_valid(player):
		return
	var t := _elapsed()
	if is_instance_valid(portal):
		if t >= _close_at or not can_open(t):
			_close()
			_next_open = t + GAP
		return
	if t >= _next_open:
		if can_open(t):
			open_portal()
		else:
			_next_open = t + 10.0

## Abre el portal (en `at`, o en un sitio libre al azar a SPOT_DIST del jugador). Devuelve el portal.
func open_portal(at: Vector3 = Vector3.INF) -> DungeonPortal:
	_close()
	var pos := at if at != Vector3.INF else find_spot()
	if pos == Vector3.INF:
		_next_open = _elapsed() + 10.0
		return null
	var dest := GameData.other_survival_map(map.get_theme())
	portal = DungeonPortal.new()
	portal.name = "MapPortal"
	portal.color = PORTAL_COLORS.get(dest, DungeonPortal.COLOR)
	portal.player = player
	map.get_parent().add_child(portal)
	portal.global_position = pos
	portal.entered.connect(cross)
	_add_beam(pos, portal.color)
	_close_at = _elapsed() + OPEN
	var events := waves.events if waves else null
	if events:
		events.announce("PORTAL A %s" % GameData.survival_map_name(dest).to_upper(), portal.color,
			"Se cierra en %d s: sigue la columna de luz" % int(OPEN))
	opened.emit(pos)
	return portal

## Sitio para el portal: suelo llano, fuera del agua, de las mesetas y de los canales, a SPOT_DIST del jugador.
func find_spot() -> Vector3:
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var lim: float = map.play_half - 10.0
	for attempt in 60:
		var a := _rng.randf() * TAU
		var p := pp + Vector2(cos(a), sin(a)) * _rng.randf_range(SPOT_DIST.x, SPOT_DIST.y)
		if absf(p.x) > lim or absf(p.y) > lim:
			continue
		if map._in_any_canal(p, 2.0) or map._near_mesa(p, 3.0) or map._near_bridge(p, 2.0):
			continue
		if map._slope(p.x, p.y) > 0.25:
			continue
		var y := map.get_height_at(p.x, p.y)
		if map.is_water(Vector3(p.x, y, p.y)):
			continue
		return Vector3(p.x, y, p.y)
	return Vector3.INF

## Columna de luz que se ve desde lejos (un cilindro sin luz ni sombra: una llamada de dibujo).
func _add_beam(pos: Vector3, col: Color) -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "PortalBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.9
	cyl.height = BEAM_H
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.35)
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.get_parent().add_child(_beam)
	_beam.global_position = pos + Vector3(0.0, BEAM_H * 0.5, 0.0)

func _close() -> void:
	if is_instance_valid(portal):
		portal.queue_free()
	portal = null
	if is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null
	_close_at = INF

## Cruza al otro mapa: fundido, se regenera el mapa con el otro tema y el jugador sale en la plaza.
func cross() -> void:
	if _switching:
		return
	_switching = true
	var dest := GameData.other_survival_map(map.get_theme())
	var fade := CanvasLayer.new()
	fade.layer = 90
	fade.process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(black)
	var label := Label.new()
	label.text = "%s\n%s" % [GameData.survival_map_name(dest).to_upper(), String(GameData.SURVIVAL_MAPS[dest]["subtitle"])]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	RumbangStyle.style_title(label, 40, RumbangStyle.TITLE, PORTAL_COLORS.get(dest, RumbangStyle.NEON_MAGENTA))
	label.theme = RumbangStyle.get_theme()
	label.modulate.a = 0.0
	fade.add_child(label)
	add_child(fade)
	AudioManager.play("boss_sting", -6.0, 0.8)
	var tw := fade.create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.4)
	tw.parallel().tween_property(label, "modulate:a", 1.0, 0.4)
	await tw.finished
	await get_tree().process_frame
	switch_to(dest)
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var tw2 := fade.create_tween()
	tw2.tween_property(black, "color:a", 0.0, 0.6)
	tw2.parallel().tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw2.tween_callback(fade.queue_free)
	_switching = false

## El cambio en sí (sin fundido; las pruebas lo llaman directamente).
func switch_to(dest: String) -> void:
	_close()
	_next_open = _elapsed() + GAP
	# La horda se queda en el otro mapa (los jefes no: el portal no se abre con jefe)
	EnemyManager.recycle_all()
	for e in EnemyRegistry.all().duplicate():
		if e is Node and is_instance_valid(e) and e != waves._boss:
			(e as Node).queue_free()
	for g in ["fate_dice", "survival_merchants"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	map.theme = dest
	map.generate()
	EnemyMotion.reset()
	var start := Vector3(0.0, map.get_height_at(0.0, 0.0) + 0.3, 0.0)
	player.global_position = start
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	# Lo que había en el suelo vuelve a apoyarse en el suelo nuevo; las gemas de experiencia te siguen
	for g in ["weapon_pickups", "item_pickups", "equipment_pickups", "run_pickups", "map_pickups"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D:
				var p := (n as Node3D).global_position
				(n as Node3D).global_position = Vector3(p.x, map.get_height_at(p.x, p.z) + 0.5, p.z)
	for o in get_tree().get_nodes_in_group("xp_orbs"):
		if o.has_method("is_active") and o.is_active() and o.has_method("pull_to"):
			(o as Node3D).global_position = start + Vector3(_rng.randf_range(-6.0, 6.0), 1.0, _rng.randf_range(-6.0, 6.0))
			o.pull_to(player, 24.0)
	if waves and waves.events:
		waves.events.on_map_changed()
	switches += 1
	switched.emit(dest)
