extends Node3D

## Maza Gigante (supervivencia): registro del arma (tabla, mejoras, sinergia, icono, estrategia) y el mazazo
## de GiantMaceSlam: aparece, baja y daña en área con empuje hacia fuera; lejos no daña.

class FakeEnemy extends Node3D:
	var hp := 100.0
	var hit_radius := 0.5
	var last_kb := Vector3.ZERO
	func take_damage(amount: float, kb: Vector3 = Vector3.ZERO) -> void:
		hp -= amount
		last_kb = kb

func _ready() -> void:
	print("--- TEST: MAZA GIGANTE ---")
	var W := WeaponData.WeaponType.GIANT_MACE
	# 1. Registro
	assert(WeaponData.get_weapon_table().has(W), "Está en la tabla de armas")
	assert(WeaponData.weapon_names[W] == "Maza Gigante", "Nombre")
	assert(WeaponUpgrades.has_specific(W) and WeaponUpgrades.for_weapon(W).size() == 4, "Mejoras propias")
	assert(WeaponSynergies.tags_of(W) == ["explosivo"], "Etiqueta explosivo")
	assert(ResourceLoader.exists(WeaponChoiceUI.ICONS[W]), "Icono de carta")
	assert(GameData.weapon_available_in_mode(W), "Sale en supervivencia")
	assert(PlayerResources.TABLE.has(W), "Gasta energía")
	print("CHECK 1 PASSED: arma registrada")

	# 2. Mazazo: daña cerca (empuje hacia fuera), no lejos
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 6, 10)
	cam.look_at(Vector3.ZERO)
	var near := FakeEnemy.new()
	var far := FakeEnemy.new()
	add_child(near)
	add_child(far)
	near.global_position = Vector3(1.5, 0, 0)
	far.global_position = Vector3(9, 0, 0)
	EnemyRegistry.register(near)
	EnemyRegistry.register(far)
	var slam := GiantMaceSlam.spawn(self, Vector3.ZERO, 40.0, 3.0, 1.0, null)
	assert(slam._sprite != null and slam._sprite.texture != null, "La maza es un dibujo (maza.png)")
	await get_tree().create_timer(0.2).timeout
	assert(near.hp == 100.0, "Antes de bajar no daña")
	await get_tree().create_timer(0.35).timeout
	assert(near.hp == 60.0, "El mazazo daña al de cerca (%s)" % near.hp)
	assert(near.last_kb.x > 0.0, "Empuja hacia fuera")
	assert(far.hp == 100.0, "No daña al de lejos")
	print("CHECK 2 PASSED: mazazo en área")
	await get_tree().create_timer(0.8).timeout
	assert(not is_instance_valid(slam), "La maza desaparece sola")
	print("CHECK 3 PASSED: desaparece")
	EnemyRegistry.unregister(near)
	EnemyRegistry.unregister(far)
	print("ALL GIANT MACE CHECKS PASSED")
	get_tree().quit(0)
