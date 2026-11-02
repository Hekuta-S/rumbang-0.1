class_name DungeonAxe
extends Node3D

## Hacha de Garri lanzada en la mazmorra. Vuela recta; al tocar un enemigo (le hace daño), una
## pared o llegar a su alcance, se queda girando en el sitio y hace daño en área SPIN_TIME
## segundos. Después sigue girando despacio, con una luz que late, hasta que el jugador se acerca
## a recogerla (PICKUP_RADIUS): entonces emite `picked_up` y desaparece. Mientras está lanzada,
## Garri no tiene hacha (no puede atacar con ella). La crea SpinningAxeStrategy.

signal picked_up

enum Phase { FLYING, SPINNING, RESTING }

const MODEL := "res://assets/models/weapons/axe_guitar.glb"
const HEIGHT := 1.0                   ## altura de vuelo sobre el suelo
const PICKUP_RADIUS := 1.6
const SPIN_TIME := 2.0                ## giro con daño en área
const TICK := 0.2
const AREA_RADIUS := 1.8
const AREA_MULT := 0.5                ## daño de cada tic respecto al del impacto
const COLOR := Color(1.0, 0.25, 0.6)          ## fucsia, como la estela
const VISUAL_SCALE := 0.04

var dir := Vector3.FORWARD
var speed := 18.0
var max_range := 12.0
var damage := 10.0
var phase := Phase.FLYING
var _traveled := 0.0
var _t := 0.0
var _tick := 0.0
var _armed := false                   ## no se recoge hasta que el jugador se ha alejado
var _visual: Node3D
var _light: OmniLight3D
var _player: Node3D
var _spin_sfx: AudioStreamPlayer3D

static func throw(parent: Node, from: Vector3, p_dir: Vector3, p_speed: float, p_range: float, p_damage: float) -> DungeonAxe:
	var a := DungeonAxe.new()
	a.dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized()
	a.speed = p_speed
	a.max_range = p_range
	a.damage = p_damage
	parent.add_child(a)
	a.global_position = from
	return a

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_visual = Node3D.new()
	add_child(_visual)
	var scene := load(MODEL) as PackedScene
	if scene:
		# En el glb el hacha ya está tumbada a lo largo de −Z (de la hoja en z ≈ +10 a la punta del
		# mástil en −31,9): se centra para que gire sobre su mitad, como un disco
		var m := scene.instantiate() as Node3D
		m.scale = Vector3.ONE * VISUAL_SCALE
		m.position = Vector3(0.0, 0.0, 11.0 * VISUAL_SCALE)
		_visual.add_child(m)
	# Estelas de supervivencia: trayectoria (centro) y punta de la hoja girando
	var tip := Marker3D.new()
	tip.position = Vector3(0.0, 0.0, (11.0 + 8.0) * VISUAL_SCALE)
	_visual.add_child(tip)
	AxeRibbon.make(self, self, AxeRibbon.PATH, true)
	AxeRibbon.make(self, tip, AxeRibbon.TIP, true)
	_spin_sfx = AudioStreamPlayer3D.new()
	_spin_sfx.stream = AudioManager.get_stream("ataque-espalanza")
	_spin_sfx.volume_db = -10.0
	_spin_sfx.pitch_scale = 1.6
	add_child(_spin_sfx)
	_light = Quality.new_light()
	_light.light_color = COLOR
	_light.light_energy = 1.2
	_light.omni_range = 3.0
	add_child(_light)
	var sparks := DustVFX.sparkles(12, 0.4, 0.4, 0.06, 0.14, COLOR)
	sparks.local_coords = false
	add_child(sparks)
	sparks.emitting = true

func is_resting() -> bool:
	return phase == Phase.RESTING

func _physics_process(delta: float) -> void:
	_t += delta
	# Zumbido del giro (como en supervivencia) mientras vuela o gira con daño
	if _spin_sfx and phase != Phase.RESTING and not _spin_sfx.playing:
		_spin_sfx.play()
	elif _spin_sfx and phase == Phase.RESTING and _spin_sfx.playing:
		_spin_sfx.stop()
	match phase:
		Phase.FLYING:
			_visual.rotate_y(28.0 * delta)
			var step := dir * speed * delta
			var hit := EnemyQuery.segment_hit(global_position, global_position + step, 0.35)
			if not hit.is_empty():
				global_position = hit["pos"]
				HitFeedback.weapon_tag = WeaponData.WeaponType.SPINNING_AXE
				hit["enemy"].take_damage(damage, dir * 4.0)
				_start_spin()
				return
			var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step + dir * 0.3, 1)
			var wall := get_world_3d().direct_space_state.intersect_ray(q)
			if not wall.is_empty():
				global_position = (wall["position"] as Vector3) - dir * 0.4
				AudioManager.play_at("impact_blunt", global_position, -4.0, 1.3)
				_start_spin()
				return
			global_position += step
			_traveled += step.length()
			if _traveled >= max_range:
				_start_spin()
		Phase.SPINNING:
			_visual.rotate_y(34.0 * delta)
			_tick += delta
			if _tick >= TICK:
				_tick = 0.0
				_area_damage()
			if _t >= SPIN_TIME:
				phase = Phase.RESTING
				_t = 0.0
		Phase.RESTING:
			# Gira despacio y flota, con una luz que late: "¡ven a por mí!"
			_visual.rotate_y(5.0 * delta)
			_visual.position.y = sin(_t * 3.0) * 0.08
			_light.light_energy = 0.8 + 0.6 * (0.5 + 0.5 * sin(_t * 5.0))
	_check_pickup()

func _start_spin() -> void:
	phase = Phase.SPINNING
	_t = 0.0
	_tick = TICK
	_light.light_energy = 2.0

func _area_damage() -> void:
	for e in EnemyRegistry.all():
		if not is_instance_valid(e):
			continue
		var off: Vector3 = e.global_position - global_position
		var r := AREA_RADIUS + float(e.get("hit_radius") if e.get("hit_radius") != null else 0.5)
		if absf(off.y) < 2.0 and Vector2(off.x, off.z).length() <= r:
			HitFeedback.weapon_tag = WeaponData.WeaponType.SPINNING_AXE
			var out := Vector3(off.x, 0.0, off.z)
			e.take_damage(damage * AREA_MULT, out.normalized() * 2.0 if out.length_squared() > 0.01 else Vector3.ZERO)

func _check_pickup() -> void:
	if not is_instance_valid(_player):
		return
	var d := Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z).length()
	if not _armed:
		_armed = d > PICKUP_RADIUS + 0.4 or (phase != Phase.FLYING and _t > 0.6)
		return
	if d <= PICKUP_RADIUS:
		AudioManager.play_at("pickup", global_position, -2.0, 0.9)
		picked_up.emit()
		queue_free()
