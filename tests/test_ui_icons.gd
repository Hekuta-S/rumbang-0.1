extends Node

## Todos los iconos que pide design/ux/level-up-cards.md existen y cargan como textura: las 18 armas de
## supervivencia (WeaponSynergies.TAGS), las 5 etiquetas y los 12 tomos. Así la UI no vuelve a caer en emoji.
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _loads(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path) and load(path) is Texture2D

func _ready() -> void:
	var missing: Array = []
	for w in WeaponSynergies.TAGS:
		if not _loads(String(WeaponChoiceUI.ICONS.get(w, ""))):
			missing.append(WeaponData.weapon_names.get(w, str(w)))
	_check(missing.is_empty(), "armas con icono (%d): faltan %s" % [WeaponSynergies.TAGS.size(), missing])
	missing = []
	for t in WeaponSynergies.TAG_INFO:
		if not _loads(WeaponSynergies.tag_icon_path(t)):
			missing.append(t)
	_check(missing.is_empty(), "etiquetas con icono (%d): faltan %s" % [WeaponSynergies.TAG_INFO.size(), missing])
	missing = []
	for id in TomeDB.TOMES:
		if not _loads(TomeDB.icon_path(id)):
			missing.append(id)
	_check(missing.is_empty(), "tomos con icono (%d): faltan %s" % [TomeDB.TOMES.size(), missing])
	print("ALL UI ICON CHECKS PASSED" if not _fail else "UI ICON CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
