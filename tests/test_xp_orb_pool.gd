extends Node3D

## Pool de gemas de XP (LootManager.recycle_xp_orb): una gema recogida se esconde y la siguiente muerte la
## reutiliza en vez de instanciar la escena. Comprueba el estado al reciclar y al reactivar, que el imán del
## mapa (grupo "xp_orbs") no ve las escondidas y que el tope de gemas solo cuenta las activas.
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	var lm := LootManager.new()
	add_child(lm)
	await get_tree().process_frame

	lm.spawn_xp_orb(Vector3(3, 0, 0), 1.0)
	await get_tree().physics_frame
	var orbs := get_tree().get_nodes_in_group("xp_orbs")
	_check(orbs.size() == 1, "una gema en el grupo tras la primera muerte")
	var orb := orbs[0] as XPOrb
	_check(orb.pool_owner == lm and not orb.has_node("CSGSphere3D"), "la gema conoce su pool y ya no lleva CSG")

	orb.pull_to(self, 50.0)                     # el imán cambia la velocidad: al reutilizarla debe volver
	orb._release()
	await get_tree().physics_frame
	_check(is_instance_valid(orb) and not orb.is_active() and not orb.visible, "recogida: escondida, no liberada")
	_check(not orb.is_in_group("xp_orbs") and not orb.monitoring, "escondida: fuera del grupo y sin detectar cuerpos")
	orb._release()                              # doble recogida en el mismo frame: no se mete dos veces
	_check(lm._free_orbs.size() == 1, "en el pool una sola vez")

	lm.spawn_xp_orb(Vector3(-5, 0, 2), 7.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(get_tree().get_nodes_in_group("xp_orbs").size() == 1 and orb.is_active(), "la siguiente muerte reutiliza la misma gema")
	_check(orb.visible and orb.monitoring and orb.target == null and is_equal_approx(orb.speed, 10.0), "reactivada: visible, detecta, sin imán y velocidad original")
	_check(is_equal_approx(orb.xp_amount, 7.0) and orb._tier == XpCurve.gem_tier(7.0), "valor y tier nuevos")
	_check(absf(orb.global_position.x + 5.0) < 0.5, "sale donde murió el enemigo")

	# Tope: con el máximo de gemas activas, la siguiente se funde; las escondidas no cuentan
	var cap := Quality.xp_orbs_max()
	for i in cap + 3:
		lm.spawn_xp_orb(Vector3(float(i), 0, 10), 1.0)
		if i % 5 == 4:
			await get_tree().process_frame
	for i in 20:
		await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("xp_orbs").size() == cap, "tope de %d gemas activas" % cap)

	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
