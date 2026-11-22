extends Node

## Instalaciones anteriores al 2026-11-19 guardaban "resolution": 0 (nativa) aunque el jugador nunca la
## eligiera, así que un móvil de gama baja seguía en nativa (2460×1080 en el Mali-G57 de pruebas) y no
## recibía la resolución reducida automática. Un ajuste sin marca de versión con 0 debe leerse como
## automático (-1); con la marca, 0 es una elección del jugador y se respeta.
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	# Arrange
	var st: Node = load("res://scripts/core/settings_manager.gd").new()
	# Act + Assert: ajuste viejo (sin marca) con nativa
	st.apply_data({"resolution": 0})
	_check(st.resolution == -1, "resolution 0 sin marca de versión pasa a automática (got %d)" % st.resolution)
	# Ajuste nuevo con nativa elegida por el jugador
	st.apply_data({"resolution": 0, "res_v": 2})
	_check(st.resolution == 0, "resolution 0 con marca se respeta (got %d)" % st.resolution)
	# Otras elecciones viejas se respetan
	st.apply_data({"resolution": 1})
	_check(st.resolution == 1, "resolution 1 sin marca se respeta (got %d)" % st.resolution)
	# Guardar escribe la marca
	st.resolution = 0
	_check(int(st.to_payload().get("res_v", 0)) == 2, "el guardado incluye res_v = 2")
	st.free()
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
