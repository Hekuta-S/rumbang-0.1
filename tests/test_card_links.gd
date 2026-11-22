extends Node

## Fila "Potencia a" de las cartas (WeaponSynergies.card_links, design/ux/level-up-cards.md): qué de tu
## equipo potencia cada tipo de carta. Lógica pura, sin cargar la partida.
const W := WeaponData.WeaponType
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	var L := WeaponSynergies.card_links

	# Arma nueva que sube Filo de 1 a 2: enlaza tu lanza (filo) y la etiqueta
	var l: Array = L.call({"type": "new_weapon", "weapon": W.SPINNING_AXE}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 3}, [], [])
	_check(l.size() == 1 and l[0]["weapons"] == [W.SPEAR_LANCE] and l[0]["tags"] == ["filo"] and String(l[0]["text"]).contains("1→2"),
		"arma nueva: sinergia Filo 1→2 con tu lanza (%s)" % [l])

	# Arma nueva sin nada en común: sin enlaces (la fila no aparece)
	l = L.call({"type": "new_weapon", "weapon": W.FLAME_THROWER}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 3}, [], [])
	_check(l.is_empty(), "arma nueva sin relación: sin fila (%s)" % [l])

	# Tomo catalizador de tu lanza: enlaza la lanza con su progreso n/8
	l = L.call({"type": "tome", "weapon": -1, "upgrade_id": "zancada"}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 6}, [], [])
	_check(l.size() == 1 and l[0]["weapons"] == [W.SPEAR_LANCE] and String(l[0]["text"]).contains("6/8"),
		"tomo catalizador: tu lanza 6/8 (%s)" % [l])

	# El mismo tomo con la lanza ya evolucionada: nada que evolucionar
	l = L.call({"type": "tome", "weapon": -1, "upgrade_id": "zancada"}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 9}, [], [W.SPEAR_LANCE])
	_check(l.is_empty(), "tomo de un arma ya evolucionada: sin fila")

	# Mejora de tu arma: tu arma nivel n→n+1 y la pista de su tomo
	l = L.call({"type": "weapon_stat", "weapon": W.SPEAR_LANCE, "upgrade_id": "x"}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 4}, [], [])
	_check(l.size() == 2 and String(l[0]["text"]).contains("4→5") and l[1]["tomes"] == ["zancada"],
		"mejora de arma: nivel 4→5 y su tomo de evolución (%s)" % [l])

	# Evolución: arma + tomo = nombre de la evolución
	l = L.call({"type": "evolution", "weapon": W.SPEAR_LANCE}, [W.SPEAR_LANCE], {W.SPEAR_LANCE: 8}, ["zancada"], [])
	_check(l.size() == 1 and l[0]["weapons"] == [W.SPEAR_LANCE] and l[0]["tomes"] == ["zancada"] and String(l[0]["text"]).contains("Lanza del Trueno"),
		"evolución: lanza + zancada = Lanza del Trueno (%s)" % [l])

	# Nunca más de 2 enlaces
	l = L.call({"type": "new_weapon", "weapon": W.KATANA}, [W.SPEAR_LANCE, W.FLAME_THROWER], {}, [], [])
	_check(l.size() <= 2, "como mucho 2 enlaces (%d)" % l.size())

	print("ALL CARD LINK CHECKS PASSED" if not _fail else "CARD LINK CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
