extends Node3D

## Ballesta Sniper (supervivencia): registro del arma, cono de flechas y flecha que atraviesa a todos.

class FakeEnemy extends Node3D:
	var hp := 100.0
	var hit_radius := 0.5
	func take_damage(amount: float, _kb: Vector3 = Vector3.ZERO) -> void:
		hp -= amount

func _ready() -> void:
	print("--- TEST: BALLESTA SNIPER ---")
	var W := WeaponData.WeaponType.CROSSBOW
	assert(WeaponData.get_weapon_table().has(W), "Está en la tabla de armas")
	assert(WeaponData.weapon_names[W] == "Ballesta Sniper", "Nombre")
	assert(WeaponUpgrades.has_specific(W) and WeaponUpgrades.get_def(W, "arrow_count").size() > 0, "Mejora de flechas")
	assert(ResourceLoader.exists(WeaponChoiceUI.ICONS[W]), "Icono de carta")
	GameData.game_mode = "survival"
	assert(GameData.weapon_available_in_mode(W), "Sale en supervivencia")
	GameData.game_mode = "dungeon"
	assert(not GameData.weapon_available_in_mode(W), "No sale en mazmorra")
	GameData.game_mode = "survival"
	print("CHECK 1 PASSED: arma registrada")

	var S := WeaponStrategy.CrossbowStrategy
	assert(S.arrow_count({}) == 1 and S.arrow_count({"quantity_bonus": 2}) == 3, "Cantidad = 1 + mejoras")
	assert(S.arrow_count({"quantity_bonus": 50}) == S.MAX_ARROWS, "Tope de flechas")
	assert(S.cone_angles(1) == [0.0], "Una flecha va a la mira")
	var a := S.cone_angles(4)
	assert(a.size() == 4 and is_equal_approx(a[0], -a[3]) and a[3] > a[2] and a[2] > 0.0, "Cono simétrico y creciente")
	assert(S.cone_angles(3, 2.0)[2] > S.cone_angles(3, 1.0)[2], "Tamaño abre el cono")
	print("CHECK 2 PASSED: cono")

	var enemies: Array = []
	for z in [-6.0, -12.0, -20.0]:
		var e := FakeEnemy.new()
		add_child(e)
		e.global_position = Vector3(0, 1.0, z)
		EnemyRegistry.register(e)
		enemies.append(e)
	BowArrow.shoot(self, Vector3(0, 1.0, 0), Vector3(0, 0, -70), 30.0,
		{"range": 60.0, "gravity": 0.0, "pierce": -1})
	await get_tree().create_timer(1.2).timeout
	for e in enemies:
		assert(e.hp == 70.0, "La flecha atraviesa y daña a todos (%s)" % e.hp)
	print("CHECK 3 PASSED: atraviesa a todos")
	for e in enemies:
		EnemyRegistry.unregister(e)
	print("ALL CROSSBOW CHECKS PASSED")
	get_tree().quit(0)
