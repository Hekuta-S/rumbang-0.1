extends SceneTree

## Calcula el RECORTE de los impostores de enemigos y lo guarda en assets/vat/<clave>_impostor.json ("crop").
## Los impostores son sprites estáticos (primera casilla de cada ángulo): se mide la caja de píxeles opacos
## de esa casilla en los 8 ángulos y se guarda la unión como fracciones de la celda [x0, y0, x1, y1]
## (y hacia abajo). El shader dibuja solo ese rectángulo, así que se pintan muchos menos píxeles vacíos.
##
## Uso (tras hornear los atlas con tools/bake_enemy_impostors.gd):
##   godot --headless --path . --script tools/crop_enemy_impostors.gd

const VAT_DIR := "res://assets/vat/"
const ALPHA_MIN := 0.5          ## el mismo umbral que usa el shader para descartar
const MARGIN_PX := 2            ## margen alrededor de la silueta (el filtro lineal sangra un poco)

func _init() -> void:
	var dir := DirAccess.open(VAT_DIR)
	var keys: Array[String] = []
	for f in dir.get_files():
		if f.ends_with("_impostor.json"):
			keys.append(f.trim_suffix("_impostor.json"))
	for key in keys:
		_crop(key)
	quit()

func _crop(key: String) -> void:
	var json_path := VAT_DIR + key + "_impostor.json"
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var img := Image.load_from_file(ProjectSettings.globalize_path(VAT_DIR + key + "_impostor.png"))
	if img == null or img.is_empty():
		push_error("No se pudo leer el atlas de " + key)
		return
	var cell: int = int(info["cell"])
	var angles: int = int(info["angles"])
	var x0 := cell
	var y0 := cell
	var x1 := -1
	var y1 := -1
	for row in angles:
		for y in cell:
			for x in cell:
				if img.get_pixel(x, row * cell + y).a >= ALPHA_MIN:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
	if x1 < 0:
		push_error("Atlas vacío: " + key)
		return
	x0 = maxi(x0 - MARGIN_PX, 0)
	y0 = maxi(y0 - MARGIN_PX, 0)
	x1 = mini(x1 + MARGIN_PX + 1, cell)
	y1 = mini(y1 + MARGIN_PX + 1, cell)
	var crop := [float(x0) / cell, float(y0) / cell, float(x1) / cell, float(y1) / cell]
	info["crop"] = crop
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	var area: float = (crop[2] - crop[0]) * (crop[3] - crop[1])
	print("%s: recorte %s, área %.0f %% de la celda" % [key, crop, area * 100.0])
