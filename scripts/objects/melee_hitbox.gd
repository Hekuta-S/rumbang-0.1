extends Area3D
class_name MeleeHitbox

var damage: float = 0.0
var active_duration: float = 0.1
var knockback_force: float = 14.0
var attack_direction: Vector3 = Vector3.ZERO
var timer: float = 0.0
var hit_enemies: Array = []
## Quién golpea y con qué arma (para robo de vida y similares). -1 = sin origen.
var source_weapon: int = -1
var source_player: Node = null

func setup(dmg: float, duration: float = 0.1, kb_force: float = 14.0, dir: Vector3 = Vector3.ZERO):
	damage = dmg
	active_duration = duration
	knockback_force = kb_force
	attack_direction = dir

func _ready():
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	body_entered.connect(_on_body_entered)

func _process(delta: float):
	timer += delta
	if timer >= active_duration:
		queue_free()

## body_entered no se emite para enemigos que YA tocaban el área al aparecer
## (p. ej. pegados al jugador), así que también se leen los solapamientos.
func _physics_process(_delta: float) -> void:
	for body in EnemyQuery.overlapping(self):
		_on_body_entered(body)

func _on_body_entered(body):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		if not hit_enemies.has(body):
			hit_enemies.append(body)
			var kb_dir = attack_direction
			if kb_dir == Vector3.ZERO:
				kb_dir = (body.global_position - global_position)
				kb_dir.y = 0
				if kb_dir.length_squared() < 0.01:
					kb_dir = -global_transform.basis.z
			kb_dir = kb_dir.normalized()
			body.take_damage(damage, kb_dir * knockback_force)
			if source_weapon >= 0 and is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
				source_player.on_damage_dealt(damage, source_weapon)

