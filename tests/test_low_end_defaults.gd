extends Node

## Valores por defecto para móviles de gama baja (Quality.is_low_end): qué GPUs y RAM cuentan como gama
## baja, y que un móvil de gama baja sin ajustes guardados arranca en calidad Baja y resolución reducida,
## mientras lo que el jugador eligió manda. No necesita un móvil: usa Quality.low_end_for y el forzado
## RUMBANG_LOW_END se simula con las variables estáticas.
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	# Regla por nombre de GPU (como lo da el driver) y RAM
	var low := ["Mali-G57 MC2", "Mali-G52 MC2", "Mali-G31 MP2", "Adreno (TM) 610", "Adreno (TM) 506",
		"PowerVR Rogue GE8320", "Mali-T830"]
	var mid := ["Mali-G68 MC4", "Mali-G76 MC4", "Adreno (TM) 618", "Adreno (TM) 619", "Adreno (TM) 730",
		"Mali-G710 MC10", "Samsung Xclipse 920"]
	var ok_low := true
	for g in low:
		ok_low = ok_low and Quality.low_end_for(g, 8.0)
	_check(ok_low, "GPUs de gama baja detectadas: %s" % ", ".join(low))
	var ok_mid := true
	for g in mid:
		ok_mid = ok_mid and not Quality.low_end_for(g, 8.0)
	_check(ok_mid, "GPUs de gama media/alta NO se bajan: %s" % ", ".join(mid))
	_check(Quality.low_end_for("Adreno (TM) 730", 3.7), "con 4 GB de RAM o menos cuenta como gama baja")
	_check(not Quality.low_end_for("Adreno (TM) 730", -1.0), "RAM desconocida no fuerza gama baja")

	# Arranque sin ajustes guardados en un móvil de gama baja
	var st := get_tree().root.get_node("SettingsManager")
	var saved_q: int = st.quality_level
	var saved_r: int = st.resolution
	OS.set_environment("RUMBANG_FORCE_MOBILE", "1")
	Quality._low_end = 1
	st.quality_level = -1
	Quality._level = -1
	_check(Quality.level() == Quality.Level.LOW, "móvil de gama baja sin ajustes -> calidad Baja")
	_check(Quality.auto_resolution() == Quality.RES_REDUCED, "móvil de gama baja -> resolución reducida")
	# Gama media: calidad Baja por defecto (todo móvil), resolución nativa
	Quality._low_end = 0
	Quality._level = -1
	_check(Quality.level() == Quality.Level.LOW, "móvil de gama media sin ajustes -> calidad Baja")
	_check(Quality.auto_resolution() == Quality.RES_NATIVE, "móvil de gama media -> resolución nativa")
	# Lo que eligió el jugador manda
	Quality._low_end = 1
	st.quality_level = Quality.Level.HIGH
	Quality._level = -1
	_check(Quality.level() == Quality.Level.HIGH, "calidad elegida por el jugador manda sobre la gama")
	# PC: nunca gama baja
	OS.set_environment("RUMBANG_FORCE_MOBILE", "")
	Quality._low_end = -1
	_check(not Quality.is_low_end() and Quality.auto_resolution() == Quality.RES_NATIVE, "PC: sin cambios")

	# Dejar todo como estaba (sin tocar el archivo de ajustes)
	st.quality_level = saved_q
	st.resolution = saved_r
	Quality._level = -1
	Quality._low_end = -1
	print("ALL LOW END CHECKS PASSED" if not _fail else "LOW END CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
