var scene = load("res://scenes/ui/hud.tscn")
var root = scene.instantiate()

var vbox = root.get_node("Control/StatsPanel/Margin/VBox")
var hbox = vbox.get_node("HBox")
hbox.add_theme_constant_override("separation", 0)

# Make bars thinner
for child in hbox.get_children():
	if child is VBoxContainer:
		for bar in child.get_children():
			if bar is ProgressBar:
				bar.custom_minimum_size = Vector2(14, 100) # Thinner
				# Make the corners of the styleboxes 0 to avoid internal rounding
				for style_name in ["background", "fill"]:
					if bar.has_theme_stylebox_override(style_name):
						var s = bar.get_theme_stylebox(style_name).duplicate()
						s.corner_radius_top_left = 0
						s.corner_radius_top_right = 0
						s.corner_radius_bottom_left = 0
						s.corner_radius_bottom_right = 0
						bar.add_theme_stylebox_override(style_name, s)

# Add character portrait circle above the bars
var portrait_container = Panel.new()
portrait_container.name = "PortraitContainer"
portrait_container.custom_minimum_size = Vector2(48, 48)
portrait_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

var style = StyleBoxFlat.new()
style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
style.corner_radius_top_left = 24
style.corner_radius_top_right = 24
style.corner_radius_bottom_left = 24
style.corner_radius_bottom_right = 24
style.border_width_left = 2
style.border_width_right = 2
style.border_width_top = 2
style.border_width_bottom = 2
style.border_color = Color(1.0, 0.8, 0.1, 1.0)
portrait_container.add_theme_stylebox_override("panel", style)

var face_label = Label.new()
face_label.name = "Face"
face_label.text = "😎"
face_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
face_label.add_theme_font_size_override("font_size", 28)
portrait_container.add_child(face_label)

var center_vbox = VBoxContainer.new()
center_vbox.name = "BarsWithPortrait"
center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
center_vbox.add_theme_constant_override("separation", -6) # Overlap slightly so bars go under portrait

vbox.remove_child(hbox)
center_vbox.add_child(portrait_container)

var clipping_panel = PanelContainer.new()
clipping_panel.name = "DomeClipping"
clipping_panel.clip_children = 1 # CLIP_CHILDREN_ONLY
clipping_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

var clip_style = StyleBoxFlat.new()
clip_style.bg_color = Color.WHITE
clip_style.corner_radius_top_left = 21 # (14*3) / 2 = 21 (half of total width for perfect dome)
clip_style.corner_radius_top_right = 21
clipping_panel.add_theme_stylebox_override("panel", clip_style)

clipping_panel.add_child(hbox)
center_vbox.add_child(clipping_panel)
vbox.add_child(center_vbox)

# Adjust ownership
center_vbox.owner = root
portrait_container.owner = root
face_label.owner = root
clipping_panel.owner = root
hbox.owner = root
for child in hbox.get_children():
	child.owner = root
	for sub in child.get_children():
		sub.owner = root

var packed = PackedScene.new()
packed.pack(root)
ResourceSaver.save(packed, "res://scenes/ui/hud.tscn")
print("HUD dome updated.")
