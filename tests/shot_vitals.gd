extends Node

## Captura de la vida flotante de escritorio (necesita ventana): llena, recién golpeada, poca vida y curándose.
## res://tests/shot_vitals.tscn -- <prefijo>

var _out := "user://vitals"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	await get_tree().create_timer(2.0).timeout
	var vit: VitalsPanel = scene.find_children("VitalsPanel", "", true, false)[0]
	vit.set_values(350.0, 350.0)
	await get_tree().create_timer(0.8).timeout
	await _shot("full")
	vit.set_values(215.0, 350.0)
	await get_tree().create_timer(0.15).timeout
	await _shot("hit")
	await get_tree().create_timer(1.2).timeout
	vit.set_values(62.0, 350.0)
	await get_tree().create_timer(1.6).timeout
	await _shot("low")
	vit.set_values(140.0, 350.0)
	await get_tree().create_timer(0.12).timeout
	await _shot("heal")
	get_tree().quit(0)

## Guarda el cuadro entero y un recorte x2 alrededor de la vida flotante.
func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s_full.png" % [_out, tag])
	var fv: FloatingVitals = get_tree().current_scene.find_children("FloatingVitals", "", true, false)[0]
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var c := Vector2i(fv.screen_pos() * k)
	var crop := img.get_region(Rect2i(c.x - 200, c.y - 180, 440, 360).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s_%s.png" % [_out, tag])
	print("SHOT ", tag)
