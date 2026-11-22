class_name MushroomBouncer
extends Node

## Hongos del mapa de supervivencia como trampolines: pisar uno (o caer encima) lanza al jugador hacia arriba.
## Caer sobre él rebota más alto (conserva parte de la velocidad de caída). Los hongos son decorado sin
## colisión, así que se comprueba la distancia al jugador cada fotograma de física.

const BASE_REACH := 0.55              ## m de radio por unidad de escala del hongo
const HEIGHT := 0.9                   ## m de alto por unidad de escala (el rebote solo ocurre por debajo de esto)
const BOUNCE_V := 11.5                ## m/s hacia arriba (un salto normal da 8.5)
const FALL_GAIN := 0.45               ## fracción de la velocidad de caída que se suma
const MAX_V := 17.0
const COOLDOWN := 0.35
const COLOR := Color(0.6, 1.0, 0.7)

var spots: Array = []                 ## [Vector3 base, float escala]
var player: Node3D
var _cool := 0.0

## Velocidad vertical del rebote según la vertical con la que llega el jugador. Pura.
static func bounce_velocity(incoming_vy: float) -> float:
	return minf(BOUNCE_V + maxf(-incoming_vy, 0.0) * FALL_GAIN, MAX_V)

## Índice del hongo que toca a `p` (pies) o -1. Pura.
static func hit_index(list: Array, p: Vector3) -> int:
	for i in list.size():
		var base: Vector3 = list[i][0]
		var s: float = list[i][1]
		var dx := p.x - base.x
		var dz := p.z - base.z
		var reach := BASE_REACH * s
		if dx * dx + dz * dz > reach * reach:
			continue
		var dy := p.y - base.y
		if dy > -0.3 and dy < HEIGHT * s:
			return i
	return -1

func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if _cool > 0.0 or spots.is_empty():
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	var mc = player.get("movement_controller")
	if mc == null or not mc.has_method("launch"):
		return
	var i := hit_index(spots, player.global_position)
	if i < 0:
		return
	var vy: float = player.velocity.y if player is CharacterBody3D else 0.0
	_cool = COOLDOWN
	mc.launch(Vector3(0, bounce_velocity(vy), 0))
	var base: Vector3 = spots[i][0]
	NecroVFX.shockwave(get_tree().current_scene, base, 2.2, COLOR)
	AudioManager.play_at("level-up", base, -12.0, 1.7)
