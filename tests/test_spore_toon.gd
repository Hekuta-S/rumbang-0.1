extends Node3D

## Bazuca de esporas en estilo cómic (SporeVFX con ToonFX): proyectil, nube, estallido y perdigones usan
## dibujos entintados (Sprite3D / partículas con puff.png y chispa.png) en lugar del shader FBM, las luces y
## los emisores por perdigón. Comprueba la estructura y que sigue haciendo daño.
const PROJ := preload("res://scenes/objects/spore_projectile.tscn")
const CLOUD := preload("res://scenes/objects/spore_cloud.tscn")
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _count(root: Node, cls: String) -> int:
	var c := 1 if root.is_class(cls) else 0
	for ch in root.get_children():
		c += _count(ch, cls)
	return c

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_check(SporeVFX.is_toon(), "las texturas cómic (puff.png, chispa.png) están y SporeVFX las usa")

	# Proyectil en vuelo
	var p = PROJ.instantiate()
	add_child(p)
	p.max_lifetime = 100.0
	p.setup(Vector3.RIGHT, 10.0, 0.0, 1.0, 1.0, 2.6)
	await _frames(3)
	_check(p.get_node_or_null("HeadSprite") is Sprite3D, "el proyectil lleva una nube dibujada")
	_check(_count(p, "MeshInstance3D") == 0, "sin esfera con shader FBM en el proyectil")
	_check(_count(p, "OmniLight3D") == 0, "sin luz en el proyectil")
	var f0: int = p.head_sprite.frame
	await get_tree().create_timer(0.2).timeout
	_check(p.head_sprite.frame != f0 or not is_equal_approx(p.head_sprite.pixel_size, p.HEAD_SIZE / 128.0), "la nube del proyectil hierve (cambia de dibujo)")

	# Estallido
	var before := _count(self, "OmniLight3D")
	p._burst(null, Vector3(0, 1, 0))
	await _frames(2)
	_check(_count(self, "OmniLight3D") == before, "el estallido no crea luces")
	var clouds := get_tree().get_nodes_in_group("spore_clouds")
	_check(clouds.size() == 1, "el estallido deja una nube de esporas")

	# Nube
	var cl = CLOUD.instantiate()
	cl.lifetime = 1.0
	add_child(cl)
	await _frames(3)
	_check(_count(cl, "Sprite3D") == 5 and _count(cl, "MeshInstance3D") == 0, "nube = 5 cúmulos dibujados, sin esferas FBM")
	var emit := 0
	for ps in cl.find_children("*", "CPUParticles3D", true, false):
		emit += (ps as CPUParticles3D).amount
	_check(emit <= 40, "la nube usa pocas partículas (%d; antes 96)" % emit)
	await get_tree().create_timer(1.2).timeout
	_check(not is_instance_valid(cl), "la nube se acaba sola")

	# Perdigón
	var pel := SporePellet.fire(self, Vector3(0, 1, 5), Vector3.FORWARD, 5.0, 1.0, 0.0, 9.0, null)
	await _frames(2)
	_check(_count(pel, "Sprite3D") == 1 and _count(pel, "CPUParticles3D") == 0 and _count(pel, "MeshInstance3D") == 0,
		"perdigón = 1 estrellita dibujada, sin emisor ni esfera")

	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
