class_name HeldWeaponRig
extends Node3D

## Modelo de un arma sujeta con las dos manos (solo mazmorra), hijo del ancla animada del personaje
## (WeaponAnchor, ver PlayerAnimationController): el ancla lo mueve según la animación del arma y las
## manos lo agarran con IK. Mueve el Muzzle del jugador a la boca del arma.
## Modelo y boca de fuego de cada arma: WeaponAnimSets.SETS.

var player: Node3D
var muzzle_marker: Marker3D

static func supports(weapon_type: int) -> bool:
	return WeaponAnimSets.supports(weapon_type)

static func attach(p_player: Node3D, anchor: Node3D, weapon_type: int, weapon_scale: float = 1.0) -> HeldWeaponRig:
	if anchor == null or not WeaponAnimSets.supports(weapon_type):
		return null
	var cfg: Dictionary = WeaponAnimSets.SETS[weapon_type]
	var rig := HeldWeaponRig.new()
	rig.name = "HeldWeapon_%d" % weapon_type
	rig.player = p_player
	anchor.add_child(rig)
	# El ancla está en unidades del esqueleto: el arma se modela en metros (y se ajusta a los brazos)
	rig.scale = Vector3.ONE * weapon_scale / maxf(anchor.global_transform.basis.get_scale().x, 0.000001)
	var model := (load(cfg["model"]) as PackedScene).instantiate() as Node3D
	rig.add_child(model)
	rig.muzzle_marker = Marker3D.new()
	rig.muzzle_marker.position = cfg["muzzle"]
	rig.add_child(rig.muzzle_marker)
	return rig

func _process(_delta: float) -> void:
	if is_visible_in_tree() and player and player.get("muzzle"):
		player.muzzle.global_position = muzzle_marker.global_position
