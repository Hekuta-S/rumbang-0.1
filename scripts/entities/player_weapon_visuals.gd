extends Node

## Construye las mallas 3D procedurales de las armas del jugador y las cuelga
## del mesh del modelo (KnightMesh). Extraído de player.gd (setup_weapon_models,
## ~1150 líneas): solo construye modelos; no guarda estado de combate.
## El player comparte el diccionario weapon_models para alternar visibilidad.

var weapon_models: Dictionary = {}

func setup_weapon_models(mount: Node3D) -> void:
	if mount == null:
		return
	# ─── HELPER: create a StandardMaterial3D quickly ───────────────────────────
	# (inline closures aren't a GDScript thing, so we use local vars instead)
	var arm_node := Node3D.new()
	var arm_mesh := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(0.1, 0.1, 0.5)
	arm_mesh.mesh = b_mesh
	arm_node.add_child(arm_mesh)
	arm_node.visible = false
	mount.add_child(arm_node)
	weapon_models[WeaponData.WeaponType.ZOMBIE_ARM] = arm_node

	# ══════════════════════════════════════════════════════════════════════════
	# 1. ENERGY SWORD — Espada de Energía
	#    Slim sci-fi longsword: tapered blade + cross-guard + grip + pommel,
	#    all glowing cyan with a bright core strip.
	# ══════════════════════════════════════════════════════════════════════════
	var sword_node := Node3D.new()

	# -- Grip (dark wrapped handle)
	var sw_grip := MeshInstance3D.new()
	var sw_grip_mesh := CylinderMesh.new()
	sw_grip_mesh.top_radius    = 0.028
	sw_grip_mesh.bottom_radius = 0.032
	sw_grip_mesh.height        = 0.32
	sw_grip_mesh.radial_segments = 10
	sw_grip.mesh     = sw_grip_mesh
	sw_grip.position = Vector3(0, -0.16, 0)
	var mat_sw_grip := StandardMaterial3D.new()
	mat_sw_grip.albedo_color = Color(0.08, 0.09, 0.12)
	mat_sw_grip.metallic     = 0.1
	mat_sw_grip.roughness    = 0.85
	sw_grip.material_override = mat_sw_grip
	sword_node.add_child(sw_grip)

	# -- Pommel sphere
	var sw_pommel := MeshInstance3D.new()
	var sw_pommel_mesh := SphereMesh.new()
	sw_pommel_mesh.radius = 0.045
	sw_pommel_mesh.height = 0.09
	sw_pommel.mesh     = sw_pommel_mesh
	sw_pommel.position = Vector3(0, -0.34, 0)
	var mat_sw_pommel := StandardMaterial3D.new()
	mat_sw_pommel.albedo_color            = Color(0.05, 0.6, 0.9)
	mat_sw_pommel.emission_enabled        = true
	mat_sw_pommel.emission                = Color(0.0, 0.7, 1.0)
	mat_sw_pommel.emission_energy_multiplier = 3.5
	sw_pommel.material_override = mat_sw_pommel
	sword_node.add_child(sw_pommel)

	# -- Cross-guard (thin horizontal bar)
	var sw_guard := MeshInstance3D.new()
	var sw_guard_mesh := BoxMesh.new()
	sw_guard_mesh.size = Vector3(0.38, 0.045, 0.055)
	sw_guard.mesh     = sw_guard_mesh
	sw_guard.position = Vector3(0, 0.0, 0)
	var mat_sw_guard := StandardMaterial3D.new()
	mat_sw_guard.albedo_color            = Color(0.05, 0.55, 0.85)
	mat_sw_guard.emission_enabled        = true
	mat_sw_guard.emission                = Color(0.0, 0.65, 1.0)
	mat_sw_guard.emission_energy_multiplier = 2.5
	mat_sw_guard.metallic  = 0.6
	mat_sw_guard.roughness = 0.25
	sw_guard.material_override = mat_sw_guard
	sword_node.add_child(sw_guard)

	# -- Blade body (wide, flat, glowing)
	var sw_blade := MeshInstance3D.new()
	var sw_blade_mesh := BoxMesh.new()
	sw_blade_mesh.size = Vector3(0.075, 1.05, 0.022)
	sw_blade.mesh     = sw_blade_mesh
	sw_blade.position = Vector3(0, 0.565, 0)
	var mat_sw_blade := StandardMaterial3D.new()
	mat_sw_blade.albedo_color            = Color(0.5, 0.95, 1.0)
	mat_sw_blade.emission_enabled        = true
	mat_sw_blade.emission                = Color(0.0, 0.85, 1.0)
	mat_sw_blade.emission_energy_multiplier = 2.8
	mat_sw_blade.metallic  = 0.3
	mat_sw_blade.roughness = 0.1
	sw_blade.material_override = mat_sw_blade
	sword_node.add_child(sw_blade)

	# -- Glowing core strip (brighter inner line)
	var sw_core := MeshInstance3D.new()
	var sw_core_mesh := BoxMesh.new()
	sw_core_mesh.size = Vector3(0.022, 1.0, 0.028)
	sw_core.mesh     = sw_core_mesh
	sw_core.position = Vector3(0, 0.56, 0)
	var mat_sw_core := StandardMaterial3D.new()
	mat_sw_core.albedo_color            = Color(0.85, 1.0, 1.0)
	mat_sw_core.emission_enabled        = true
	mat_sw_core.emission                = Color(0.6, 1.0, 1.0)
	mat_sw_core.emission_energy_multiplier = 5.0
	sw_core.material_override = mat_sw_core
	sword_node.add_child(sw_core)

	sword_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(45)),
		Vector3(0.42, 0.9, -0.28))
	mount.add_child(sword_node)
	weapon_models[WeaponData.WeaponType.ENERGY_SWORD] = sword_node

	# ══════════════════════════════════════════════════════════════════════════
	# 2. FLAME AXE — Hacha de Fuego
	#    Heavy two-bit axe: wrapped pole, thick head with crescent blades,
	#    molten orange glow with ember yellow hotspots.
	# ═════════════════════════════════════════════════════════════════════════
	var axe_node := Node3D.new()

	# -- Handle (wooden-dark cylinder)
	var axe_handle := MeshInstance3D.new()
	var axe_handle_mesh := CylinderMesh.new()
	axe_handle_mesh.top_radius    = 0.028
	axe_handle_mesh.bottom_radius = 0.035
	axe_handle_mesh.height        = 1.5
	axe_handle_mesh.radial_segments = 8
	axe_handle.mesh     = axe_handle_mesh
	axe_handle.position = Vector3(0, 0.0, 0)
	var mat_axe_handle := StandardMaterial3D.new()
	mat_axe_handle.albedo_color = Color(0.18, 0.10, 0.05)
	mat_axe_handle.metallic     = 0.05
	mat_axe_handle.roughness    = 0.9
	axe_handle.material_override = mat_axe_handle
	axe_node.add_child(axe_handle)

	# -- Handle wrap rings (3 metal bands)
	for ring_y in [-0.4, 0.0, 0.45]:
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius    = 0.038
		ring_mesh.bottom_radius = 0.038
		ring_mesh.height        = 0.05
		ring_mesh.radial_segments = 10
		ring.mesh     = ring_mesh
		ring.position = Vector3(0, ring_y, 0)
		var mat_ring := StandardMaterial3D.new()
		mat_ring.albedo_color = Color(0.55, 0.45, 0.3)
		mat_ring.metallic     = 0.8
		mat_ring.roughness    = 0.35
		ring.material_override = mat_ring
		axe_node.add_child(ring)

	# -- Axe head back-plate (steel base)
	var axe_back := MeshInstance3D.new()
	var axe_back_mesh := BoxMesh.new()
	axe_back_mesh.size = Vector3(0.12, 0.52, 0.18)
	axe_back.mesh     = axe_back_mesh
	axe_back.position = Vector3(0.0, 0.76, 0)
	var mat_axe_back := StandardMaterial3D.new()
	mat_axe_back.albedo_color = Color(0.35, 0.3, 0.28)
	mat_axe_back.metallic     = 0.85
	mat_axe_back.roughness    = 0.25
	axe_back.material_override = mat_axe_back
	axe_node.add_child(axe_back)

	# -- Left blade wing (crescent shape approximated with rotated box)
	var axe_wing_l := MeshInstance3D.new()
	var axe_wing_l_mesh := BoxMesh.new()
	axe_wing_l_mesh.size = Vector3(0.42, 0.16, 0.08)
	axe_wing_l.mesh     = axe_wing_l_mesh
	axe_wing_l.position = Vector3(-0.22, 0.85, 0)
	axe_wing_l.rotation = Vector3(0, 0, deg_to_rad(12))
	var mat_axe_blade := StandardMaterial3D.new()
	mat_axe_blade.albedo_color            = Color(1.0, 0.22, 0.0)
	mat_axe_blade.emission_enabled        = true
	mat_axe_blade.emission                = Color(1.0, 0.38, 0.0)
	mat_axe_blade.emission_energy_multiplier = 3.0
	mat_axe_blade.metallic  = 0.6
	mat_axe_blade.roughness = 0.2
	axe_wing_l.material_override = mat_axe_blade
	axe_node.add_child(axe_wing_l)

	# -- Right blade wing (mirror)
	var axe_wing_r := MeshInstance3D.new()
	var axe_wing_r_mesh := BoxMesh.new()
	axe_wing_r_mesh.size = Vector3(0.42, 0.16, 0.08)
	axe_wing_r.mesh     = axe_wing_r_mesh
	axe_wing_r.position = Vector3(0.22, 0.68, 0)
	axe_wing_r.rotation = Vector3(0, 0, deg_to_rad(-12))
	var mat_axe_blade2 := StandardMaterial3D.new()
	mat_axe_blade2.albedo_color            = Color(1.0, 0.22, 0.0)
	mat_axe_blade2.emission_enabled        = true
	mat_axe_blade2.emission                = Color(1.0, 0.38, 0.0)
	mat_axe_blade2.emission_energy_multiplier = 3.0
	mat_axe_blade2.metallic  = 0.6
	mat_axe_blade2.roughness = 0.2
	axe_wing_r.material_override = mat_axe_blade2
	axe_node.add_child(axe_wing_r)

	# -- Ember core gem (bright molten centre)
	var axe_gem := MeshInstance3D.new()
	var axe_gem_mesh := SphereMesh.new()
	axe_gem_mesh.radius = 0.055
	axe_gem_mesh.height = 0.11
	axe_gem.mesh     = axe_gem_mesh
	axe_gem.position = Vector3(0, 0.77, 0.1)
	var mat_axe_gem := StandardMaterial3D.new()
	mat_axe_gem.albedo_color            = Color(1.0, 0.85, 0.1)
	mat_axe_gem.emission_enabled        = true
	mat_axe_gem.emission                = Color(1.0, 0.9, 0.2)
	mat_axe_gem.emission_energy_multiplier = 5.5
	axe_gem.material_override = mat_axe_gem
	axe_node.add_child(axe_gem)
	
	# Fire particles for the axe core
	var fire_emitter := CPUParticles3D.new()
	fire_emitter.amount = 16
	fire_emitter.lifetime = 0.8
	fire_emitter.mesh = QuadMesh.new()
	fire_emitter.mesh.size = Vector2(0.08, 0.08)
	fire_emitter.direction = Vector3(0, 1, 0)
	fire_emitter.spread = 20.0
	fire_emitter.gravity = Vector3(0, 1.5, 0)
	fire_emitter.initial_velocity_min = 0.2
	fire_emitter.initial_velocity_max = 0.5
	fire_emitter.scale_amount_min = 0.5
	fire_emitter.scale_amount_max = 1.5
	var fire_mat = StandardMaterial3D.new()
	# BLEND_MODE_ADD below already forces the material into the transparent
	# pipeline with additive blending, so no explicit transparency flag is needed.
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.albedo_color = Color(1.0, 0.5, 0.0, 0.8)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.4, 0.0)
	fire_mat.emission_energy_multiplier = 2.0
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fire_emitter.material_override = fire_mat
	
	var fire_curve = Curve.new()
	fire_curve.add_point(Vector2(0, 0.2))
	fire_curve.add_point(Vector2(0.2, 1.0))
	fire_curve.add_point(Vector2(1, 0.0))
	fire_emitter.scale_amount_curve = fire_curve
	
	fire_emitter.position = Vector3(0, 0.77, 0.1)
	axe_node.add_child(fire_emitter)

	axe_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(30)),
		Vector3(0.42, 0.85, -0.28))
	mount.add_child(axe_node)
	weapon_models[WeaponData.WeaponType.FLAME_AXE] = axe_node

	# ══════════════════════════════════════════════════════════════════════════
	# 3. PLASMA RIFLE — Rifle de Plasma
	#    Sleek sci-fi carbine: receiver body, long tapered barrel, scope rail,
	#    under-barrel energy cell, forward grip, charged muzzle tip.
	# ══════════════════════════════════════════════════════════════════════════
	var rifle_node := Node3D.new()

	# -- Main receiver (body)
	var rf_body := MeshInstance3D.new()
	var rf_body_mesh := BoxMesh.new()
	rf_body_mesh.size = Vector3(0.10, 0.18, 0.44)
	rf_body.mesh     = rf_body_mesh
	rf_body.position = Vector3(0, 0, -0.08)
	var mat_rf_body := StandardMaterial3D.new()
	mat_rf_body.albedo_color = Color(0.08, 0.12, 0.18)
	mat_rf_body.metallic     = 0.75
	mat_rf_body.roughness    = 0.28
	rf_body.material_override = mat_rf_body
	rifle_node.add_child(rf_body)

	# -- Barrel (long, tapered cylinder)
	var rf_barrel := MeshInstance3D.new()
	var rf_barrel_mesh := CylinderMesh.new()
	rf_barrel_mesh.top_radius    = 0.022
	rf_barrel_mesh.bottom_radius = 0.038
	rf_barrel_mesh.height        = 0.72
	rf_barrel_mesh.radial_segments = 10
	rf_barrel.mesh     = rf_barrel_mesh
	rf_barrel.rotation = Vector3(deg_to_rad(90), 0, 0)
	rf_barrel.position = Vector3(0, 0.02, -0.66)
	var mat_rf_barrel := StandardMaterial3D.new()
	mat_rf_barrel.albedo_color = Color(0.10, 0.14, 0.22)
	mat_rf_barrel.metallic     = 0.85
	mat_rf_barrel.roughness    = 0.2
	rf_barrel.material_override = mat_rf_barrel
	rifle_node.add_child(rf_barrel)

	# -- Muzzle tip (glowing plasma mouth)
	var rf_muzzle := MeshInstance3D.new()
	var rf_muzzle_mesh := CylinderMesh.new()
	rf_muzzle_mesh.top_radius    = 0.032
	rf_muzzle_mesh.bottom_radius = 0.024
	rf_muzzle_mesh.height        = 0.07
	rf_muzzle_mesh.radial_segments = 12
	rf_muzzle.mesh     = rf_muzzle_mesh
	rf_muzzle.rotation = Vector3(deg_to_rad(90), 0, 0)
	rf_muzzle.position = Vector3(0, 0.02, -1.04)
	var mat_rf_muzzle := StandardMaterial3D.new()
	mat_rf_muzzle.albedo_color            = Color(0.3, 0.75, 1.0)
	mat_rf_muzzle.emission_enabled        = true
	mat_rf_muzzle.emission                = Color(0.0, 0.72, 1.0)
	mat_rf_muzzle.emission_energy_multiplier = 4.5
	rf_muzzle.material_override = mat_rf_muzzle
	rifle_node.add_child(rf_muzzle)

	# -- Top-rail / scope housing
	var rf_rail := MeshInstance3D.new()
	var rf_rail_mesh := BoxMesh.new()
	rf_rail_mesh.size = Vector3(0.045, 0.045, 0.55)
	rf_rail.mesh     = rf_rail_mesh
	rf_rail.position = Vector3(0, 0.115, -0.12)
	var mat_rf_rail := StandardMaterial3D.new()
	mat_rf_rail.albedo_color = Color(0.05, 0.08, 0.14)
	mat_rf_rail.metallic     = 0.9
	mat_rf_rail.roughness    = 0.15
	rf_rail.material_override = mat_rf_rail
	rifle_node.add_child(rf_rail)

	# -- Scope lens
	var rf_scope := MeshInstance3D.new()
	var rf_scope_mesh := CylinderMesh.new()
	rf_scope_mesh.top_radius    = 0.028
	rf_scope_mesh.bottom_radius = 0.028
	rf_scope_mesh.height        = 0.07
	rf_scope_mesh.radial_segments = 10
	rf_scope.mesh     = rf_scope_mesh
	rf_scope.rotation = Vector3(deg_to_rad(90), 0, 0)
	rf_scope.position = Vector3(0, 0.115, -0.18)
	var mat_rf_scope := StandardMaterial3D.new()
	mat_rf_scope.albedo_color            = Color(0.2, 0.6, 1.0)
	mat_rf_scope.emission_enabled        = true
	mat_rf_scope.emission                = Color(0.1, 0.5, 1.0)
	mat_rf_scope.emission_energy_multiplier = 3.0
	mat_rf_scope.metallic  = 0.4
	mat_rf_scope.roughness = 0.1
	rf_scope.material_override = mat_rf_scope
	rifle_node.add_child(rf_scope)

	# -- Energy cell / magazine (glowing blue slab under receiver)
	var rf_cell := MeshInstance3D.new()
	var rf_cell_mesh := BoxMesh.new()
	rf_cell_mesh.size = Vector3(0.07, 0.22, 0.12)
	rf_cell.mesh     = rf_cell_mesh
	rf_cell.position = Vector3(0, -0.19, -0.06)
	var mat_rf_cell := StandardMaterial3D.new()
	mat_rf_cell.albedo_color            = Color(0.1, 0.55, 1.0)
	mat_rf_cell.emission_enabled        = true
	mat_rf_cell.emission                = Color(0.0, 0.6, 1.0)
	mat_rf_cell.emission_energy_multiplier = 2.2
	mat_rf_cell.metallic  = 0.5
	mat_rf_cell.roughness = 0.3
	rf_cell.material_override = mat_rf_cell
	rifle_node.add_child(rf_cell)

	# -- Pistol grip
	var rf_grip := MeshInstance3D.new()
	var rf_grip_mesh := BoxMesh.new()
	rf_grip_mesh.size = Vector3(0.07, 0.20, 0.10)
	rf_grip.mesh     = rf_grip_mesh
	rf_grip.rotation = Vector3(deg_to_rad(-15), 0, 0)
	rf_grip.position = Vector3(0, -0.17, 0.12)
	var mat_rf_grip := StandardMaterial3D.new()
	mat_rf_grip.albedo_color = Color(0.06, 0.09, 0.13)
	mat_rf_grip.metallic     = 0.2
	mat_rf_grip.roughness    = 0.85
	rf_grip.material_override = mat_rf_grip
	rifle_node.add_child(rf_grip)

	rifle_node.transform = Transform3D(Basis(), Vector3(0.38, 0.92, -0.36))
	mount.add_child(rifle_node)
	weapon_models[WeaponData.WeaponType.PLASMA_RIFLE] = rifle_node

	# ══════════════════════════════════════════════════════════════════════════
	# 4. SMOKE SHOTGUN — Escopeta de Humo
	#    Wide pump-action shotgun: beefy receiver, three stacked barrels,
	#    pump slide, tactical grip, emitting a passive dark smoke cloud.
	# ══════════════════════════════════════════════════════════════════════════
	var shotgun_node := Node3D.new()

	# -- Receiver body (wide and chunky, dark grey metallic)
	var sg_body := MeshInstance3D.new()
	var sg_body_mesh := BoxMesh.new()
	sg_body_mesh.size = Vector3(0.19, 0.22, 0.42)
	sg_body.mesh     = sg_body_mesh
	sg_body.position = Vector3(0, 0, -0.04)
	var mat_sg_body := StandardMaterial3D.new()
	mat_sg_body.albedo_color = Color(0.10, 0.10, 0.10)
	mat_sg_body.metallic     = 0.85
	mat_sg_body.roughness    = 0.5
	sg_body.material_override = mat_sg_body
	shotgun_node.add_child(sg_body)

	# -- Three barrels (top, mid, bottom)
	var barrel_offsets: Array = [Vector3(0, 0.075, 0), Vector3(0, 0, 0), Vector3(0, -0.075, 0)]
	for b_pos in barrel_offsets:
		var sg_barrel := MeshInstance3D.new()
		var sg_barrel_mesh := CylinderMesh.new()
		sg_barrel_mesh.top_radius    = 0.028
		sg_barrel_mesh.bottom_radius = 0.030
		sg_barrel_mesh.height        = 0.68
		sg_barrel_mesh.radial_segments = 10
		sg_barrel.mesh     = sg_barrel_mesh
		sg_barrel.rotation = Vector3(deg_to_rad(90), 0, 0)
		sg_barrel.position = b_pos + Vector3(0, 0, -0.6)
		var mat_sg_barrel := StandardMaterial3D.new()
		mat_sg_barrel.albedo_color = Color(0.15, 0.15, 0.15)
		mat_sg_barrel.metallic     = 0.95
		mat_sg_barrel.roughness    = 0.3
		sg_barrel.material_override = mat_sg_barrel
		shotgun_node.add_child(sg_barrel)

		# Muzzle glow per barrel (ghostly pale grey/blue)
		var sg_muzzle_glow := MeshInstance3D.new()
		var sg_muzzle_glow_mesh := SphereMesh.new()
		sg_muzzle_glow_mesh.radius = 0.035
		sg_muzzle_glow_mesh.height = 0.07
		sg_muzzle_glow.mesh     = sg_muzzle_glow_mesh
		sg_muzzle_glow.position = b_pos + Vector3(0, 0, -0.96)
		var mat_sg_muzzle_glow := StandardMaterial3D.new()
		mat_sg_muzzle_glow.albedo_color            = Color(0.4, 0.4, 0.45)
		mat_sg_muzzle_glow.emission_enabled        = true
		mat_sg_muzzle_glow.emission                = Color(0.3, 0.3, 0.35)
		mat_sg_muzzle_glow.emission_energy_multiplier = 2.0
		sg_muzzle_glow.material_override = mat_sg_muzzle_glow
		shotgun_node.add_child(sg_muzzle_glow)
		
		# Continuous smoke particles emitted from each barrel
		var smoke_emitter := CPUParticles3D.new()
		smoke_emitter.amount = 12
		smoke_emitter.lifetime = 1.2
		smoke_emitter.mesh = QuadMesh.new()
		smoke_emitter.mesh.size = Vector2(0.1, 0.1)
		smoke_emitter.direction = Vector3(0, 0, -1)
		smoke_emitter.spread = 15.0
		smoke_emitter.gravity = Vector3(0, 0.5, 0)
		smoke_emitter.initial_velocity_min = 0.1
		smoke_emitter.initial_velocity_max = 0.4
		smoke_emitter.scale_amount_min = 0.5
		smoke_emitter.scale_amount_max = 2.0
		
		var smoke_mat = StandardMaterial3D.new()
		smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.6)
		smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smoke_emitter.material_override = smoke_mat
		
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.2))
		curve.add_point(Vector2(0.5, 1.0))
		curve.add_point(Vector2(1, 0.0))
		smoke_emitter.scale_amount_curve = curve
		
		smoke_emitter.position = b_pos + Vector3(0, 0, -0.98)
		shotgun_node.add_child(smoke_emitter)

	# -- Pump slide (carbon fiber look)
	var sg_pump := MeshInstance3D.new()
	var sg_pump_mesh := BoxMesh.new()
	sg_pump_mesh.size = Vector3(0.13, 0.10, 0.20)
	sg_pump.mesh     = sg_pump_mesh
	sg_pump.position = Vector3(0, -0.10, -0.45)
	var mat_sg_pump := StandardMaterial3D.new()
	mat_sg_pump.albedo_color = Color(0.12, 0.12, 0.14)
	mat_sg_pump.metallic     = 0.4
	mat_sg_pump.roughness    = 0.8
	sg_pump.material_override = mat_sg_pump
	shotgun_node.add_child(sg_pump)

	# -- Pistol grip
	var sg_grip := MeshInstance3D.new()
	var sg_grip_mesh := BoxMesh.new()
	sg_grip_mesh.size = Vector3(0.09, 0.22, 0.11)
	sg_grip.mesh     = sg_grip_mesh
	sg_grip.rotation = Vector3(deg_to_rad(-12), 0, 0)
	sg_grip.position = Vector3(0, -0.20, 0.15)
	var mat_sg_grip := StandardMaterial3D.new()
	mat_sg_grip.albedo_color = Color(0.05, 0.05, 0.05)
	mat_sg_grip.metallic     = 0.1
	mat_sg_grip.roughness    = 0.95
	sg_grip.material_override = mat_sg_grip
	shotgun_node.add_child(sg_grip)

	# -- Distorsion Shader Quad --
	var sg_distortion := MeshInstance3D.new()
	var sg_distortion_mesh := QuadMesh.new()
	sg_distortion_mesh.size = Vector2(1.5, 1.5)
	sg_distortion.mesh = sg_distortion_mesh
	sg_distortion.position = Vector3(0, 0, -1.2) # En frente del cañón
	var mat_sg_dist := ShaderMaterial.new()
	mat_sg_dist.shader = load("res://assets/shaders/shotgun_distortion.gdshader")
	mat_sg_dist.set_shader_parameter("distortion_strength", 0.15)
	mat_sg_dist.set_shader_parameter("progress", 0.0) # Animar en disparo
	sg_distortion.material_override = mat_sg_dist
	shotgun_node.add_child(sg_distortion)

	shotgun_node.transform = Transform3D(Basis(), Vector3(0.38, 0.92, -0.36))
	mount.add_child(shotgun_node)
	weapon_models[WeaponData.WeaponType.TRI_SHOTGUN] = shotgun_node

	# ══════════════════════════════════════════════════════════════════════════
	# 5. RAILGUN — Cañón Railgun
	#    Heavy futuristic cannon: thick body, exposed magnetic rail fins,
	#    energy coil rings, glowing purple charge crystal at back.
	# ══════════════════════════════════════════════════════════════════════════
	var railgun_node := Node3D.new()

	# -- Main body (long heavy box)
	var rg_body := MeshInstance3D.new()
	var rg_body_mesh := BoxMesh.new()
	rg_body_mesh.size = Vector3(0.14, 0.20, 0.85)
	rg_body.mesh     = rg_body_mesh
	rg_body.position = Vector3(0, 0, -0.22)
	var mat_rg_body := StandardMaterial3D.new()
	mat_rg_body.albedo_color = Color(0.12, 0.08, 0.16)
	mat_rg_body.metallic     = 0.85
	mat_rg_body.roughness    = 0.22
	rg_body.material_override = mat_rg_body
	railgun_node.add_child(rg_body)

	# -- Barrel extension
	var rg_barrel := MeshInstance3D.new()
	var rg_barrel_mesh := CylinderMesh.new()
	rg_barrel_mesh.top_radius    = 0.025
	rg_barrel_mesh.bottom_radius = 0.04
	rg_barrel_mesh.height        = 0.55
	rg_barrel_mesh.radial_segments = 10
	rg_barrel.mesh     = rg_barrel_mesh
	rg_barrel.rotation = Vector3(deg_to_rad(90), 0, 0)
	rg_barrel.position = Vector3(0, 0.02, -0.93)
	var mat_rg_barrel := StandardMaterial3D.new()
	mat_rg_barrel.albedo_color = Color(0.20, 0.10, 0.30)
	mat_rg_barrel.metallic     = 0.9
	mat_rg_barrel.roughness    = 0.15
	rg_barrel.material_override = mat_rg_barrel
	railgun_node.add_child(rg_barrel)

	# -- Muzzle discharge ring
	var rg_muzzle := MeshInstance3D.new()
	var rg_muzzle_mesh := CylinderMesh.new()
	rg_muzzle_mesh.top_radius    = 0.042
	rg_muzzle_mesh.bottom_radius = 0.035
	rg_muzzle_mesh.height        = 0.06
	rg_muzzle_mesh.radial_segments = 14
	rg_muzzle.mesh     = rg_muzzle_mesh
	rg_muzzle.rotation = Vector3(deg_to_rad(90), 0, 0)
	rg_muzzle.position = Vector3(0, 0.02, -1.22)
	var mat_rg_muzzle := StandardMaterial3D.new()
	mat_rg_muzzle.albedo_color            = Color(0.75, 0.3, 1.0)
	mat_rg_muzzle.emission_enabled        = true
	mat_rg_muzzle.emission                = Color(0.85, 0.2, 1.0)
	mat_rg_muzzle.emission_energy_multiplier = 5.0
	rg_muzzle.material_override = mat_rg_muzzle
	railgun_node.add_child(rg_muzzle)

	# -- Rail fins (2 side fins along barrel)
	for side in [-1, 1]:
		var rg_fin := MeshInstance3D.new()
		var rg_fin_mesh := BoxMesh.new()
		rg_fin_mesh.size = Vector3(0.06, 0.04, 0.75)
		rg_fin.mesh     = rg_fin_mesh
		rg_fin.position = Vector3(side * 0.10, 0.06, -0.28)
		var mat_rg_fin := StandardMaterial3D.new()
		mat_rg_fin.albedo_color            = Color(0.5, 0.1, 0.8)
		mat_rg_fin.emission_enabled        = true
		mat_rg_fin.emission                = Color(0.65, 0.15, 0.95)
		mat_rg_fin.emission_energy_multiplier = 2.8
		mat_rg_fin.metallic  = 0.7
		mat_rg_fin.roughness = 0.2
		rg_fin.material_override = mat_rg_fin
		railgun_node.add_child(rg_fin)

	# -- Charge coil rings (3 rings along body)
	for coil_z in [-0.05, -0.28, -0.50]:
		var rg_coil := MeshInstance3D.new()
		var rg_coil_mesh := CylinderMesh.new()
		rg_coil_mesh.top_radius    = 0.09
		rg_coil_mesh.bottom_radius = 0.09
		rg_coil_mesh.height        = 0.035
		rg_coil_mesh.radial_segments = 14
		rg_coil.mesh     = rg_coil_mesh
		rg_coil.rotation = Vector3(deg_to_rad(90), 0, 0)
		rg_coil.position = Vector3(0, 0, coil_z)
		var mat_rg_coil := StandardMaterial3D.new()
		mat_rg_coil.albedo_color            = Color(0.6, 0.15, 0.9)
		mat_rg_coil.emission_enabled        = true
		mat_rg_coil.emission                = Color(0.7, 0.2, 1.0)
		mat_rg_coil.emission_energy_multiplier = 3.0
		mat_rg_coil.metallic  = 0.6
		mat_rg_coil.roughness = 0.25
		rg_coil.material_override = mat_rg_coil
		railgun_node.add_child(rg_coil)

	# -- Charge crystal (back of receiver)
	var rg_crystal := MeshInstance3D.new()
	var rg_crystal_mesh := SphereMesh.new()
	rg_crystal_mesh.radius = 0.068
	rg_crystal_mesh.height = 0.14
	rg_crystal.mesh     = rg_crystal_mesh
	rg_crystal.position = Vector3(0, 0.0, 0.25)
	var mat_rg_crystal := StandardMaterial3D.new()
	mat_rg_crystal.albedo_color            = Color(0.9, 0.4, 1.0)
	mat_rg_crystal.emission_enabled        = true
	mat_rg_crystal.emission                = Color(1.0, 0.35, 1.0)
	mat_rg_crystal.emission_energy_multiplier = 6.0
	rg_crystal.material_override = mat_rg_crystal
	railgun_node.add_child(rg_crystal)

	# -- Grip
	var rg_grip := MeshInstance3D.new()
	var rg_grip_mesh := BoxMesh.new()
	rg_grip_mesh.size = Vector3(0.08, 0.22, 0.10)
	rg_grip.mesh     = rg_grip_mesh
	rg_grip.rotation = Vector3(deg_to_rad(-10), 0, 0)
	rg_grip.position = Vector3(0, -0.20, 0.05)
	var mat_rg_grip := StandardMaterial3D.new()
	mat_rg_grip.albedo_color = Color(0.08, 0.05, 0.12)
	mat_rg_grip.metallic     = 0.2
	mat_rg_grip.roughness    = 0.88
	rg_grip.material_override = mat_rg_grip
	railgun_node.add_child(rg_grip)

	railgun_node.transform = Transform3D(Basis(), Vector3(0.38, 0.92, -0.36))
	mount.add_child(railgun_node)
	weapon_models[WeaponData.WeaponType.RAILGUN] = railgun_node

	# ══════════════════════════════════════════════════════════════════════════
	# 6. SPEAR-LANCE — Espalanza de Mikeura (signature)
	#    Long magical lance: ornate shaft with rune bands, wide leaf-shaped tip,
	#    twin side prongs, glowing emerald core.
	# ══════════════════════════════════════════════════════════════════════════
	var spear_node := Node3D.new()

	# -- Main shaft (long, slightly tapered)
	var sp_shaft := MeshInstance3D.new()
	var sp_shaft_mesh := CylinderMesh.new()
	sp_shaft_mesh.top_radius    = 0.022
	sp_shaft_mesh.bottom_radius = 0.034
	sp_shaft_mesh.height        = 2.0
	sp_shaft_mesh.radial_segments = 10
	sp_shaft.mesh     = sp_shaft_mesh
	sp_shaft.position = Vector3(0, 0.4, 0)
	var mat_sp_shaft := StandardMaterial3D.new()
	mat_sp_shaft.albedo_color = Color(0.12, 0.20, 0.14)
	mat_sp_shaft.metallic     = 0.55
	mat_sp_shaft.roughness    = 0.45
	sp_shaft.material_override = mat_sp_shaft
	spear_node.add_child(sp_shaft)

	# -- Rune bands (3 glowing rings along shaft)
	for band_y in [0.1, 0.55, 0.95]:
		var sp_band := MeshInstance3D.new()
		var sp_band_mesh := CylinderMesh.new()
		sp_band_mesh.top_radius    = 0.040
		sp_band_mesh.bottom_radius = 0.040
		sp_band_mesh.height        = 0.045
		sp_band_mesh.radial_segments = 12
		sp_band.mesh     = sp_band_mesh
		sp_band.position = Vector3(0, band_y, 0)
		var mat_sp_band := StandardMaterial3D.new()
		mat_sp_band.albedo_color            = Color(0.2, 0.9, 0.45)
		mat_sp_band.emission_enabled        = true
		mat_sp_band.emission                = Color(0.1, 1.0, 0.4)
		mat_sp_band.emission_energy_multiplier = 3.5
		mat_sp_band.metallic  = 0.6
		mat_sp_band.roughness = 0.2
		sp_band.material_override = mat_sp_band
		spear_node.add_child(sp_band)

	# -- Crossguard disc
	var sp_guard := MeshInstance3D.new()
	var sp_guard_mesh := CylinderMesh.new()
	sp_guard_mesh.top_radius    = 0.15
	sp_guard_mesh.bottom_radius = 0.12
	sp_guard_mesh.height        = 0.04
	sp_guard_mesh.radial_segments = 14
	sp_guard.mesh     = sp_guard_mesh
	sp_guard.position = Vector3(0, 1.28, 0)
	var mat_sp_guard := StandardMaterial3D.new()
	mat_sp_guard.albedo_color            = Color(0.18, 0.72, 0.38)
	mat_sp_guard.emission_enabled        = true
	mat_sp_guard.emission                = Color(0.1, 0.85, 0.4)
	mat_sp_guard.emission_energy_multiplier = 2.5
	mat_sp_guard.metallic  = 0.7
	mat_sp_guard.roughness = 0.2
	sp_guard.material_override = mat_sp_guard
	spear_node.add_child(sp_guard)

	# -- Blade (long leaf point)
	var sp_blade := MeshInstance3D.new()
	var sp_blade_mesh := CylinderMesh.new()
	sp_blade_mesh.top_radius    = 0.005
	sp_blade_mesh.bottom_radius = 0.062
	sp_blade_mesh.height        = 0.55
	sp_blade_mesh.radial_segments = 8
	sp_blade.mesh     = sp_blade_mesh
	sp_blade.position = Vector3(0, 1.60, 0)
	var mat_sp_blade := StandardMaterial3D.new()
	mat_sp_blade.albedo_color            = Color(0.78, 1.0, 0.88)
	mat_sp_blade.emission_enabled        = true
	mat_sp_blade.emission                = Color(0.4, 1.0, 0.55)
	mat_sp_blade.emission_energy_multiplier = 3.5
	mat_sp_blade.metallic  = 0.5
	mat_sp_blade.roughness = 0.12
	sp_blade.material_override = mat_sp_blade
	spear_node.add_child(sp_blade)

	# -- Side prongs (2 small spikes at crossguard)
	for prong_x in [-0.16, 0.16]:
		var sp_prong := MeshInstance3D.new()
		var sp_prong_mesh := CylinderMesh.new()
		sp_prong_mesh.top_radius    = 0.005
		sp_prong_mesh.bottom_radius = 0.022
		sp_prong_mesh.height        = 0.22
		sp_prong_mesh.radial_segments = 6
		sp_prong.mesh     = sp_prong_mesh
		sp_prong.position = Vector3(prong_x, 1.30, 0)
		sp_prong.rotation = Vector3(0, 0, deg_to_rad(90) * sign(prong_x))
		var mat_sp_prong := StandardMaterial3D.new()
		mat_sp_prong.albedo_color            = Color(0.6, 1.0, 0.7)
		mat_sp_prong.emission_enabled        = true
		mat_sp_prong.emission                = Color(0.3, 1.0, 0.5)
		mat_sp_prong.emission_energy_multiplier = 2.8
		mat_sp_prong.metallic  = 0.5
		mat_sp_prong.roughness = 0.15
		sp_prong.material_override = mat_sp_prong
		spear_node.add_child(sp_prong)

	# -- Pommel spike
	var sp_pommel := MeshInstance3D.new()
	var sp_pommel_mesh := CylinderMesh.new()
	sp_pommel_mesh.top_radius    = 0.005
	sp_pommel_mesh.bottom_radius = 0.038
	sp_pommel_mesh.height        = 0.18
	sp_pommel_mesh.radial_segments = 8
	sp_pommel.mesh     = sp_pommel_mesh
	sp_pommel.rotation = Vector3(0, 0, deg_to_rad(180))
	sp_pommel.position = Vector3(0, -0.85, 0)
	var mat_sp_pommel := StandardMaterial3D.new()
	mat_sp_pommel.albedo_color            = Color(0.4, 0.9, 0.5)
	mat_sp_pommel.emission_enabled        = true
	mat_sp_pommel.emission                = Color(0.2, 1.0, 0.4)
	mat_sp_pommel.emission_energy_multiplier = 2.5
	mat_sp_pommel.metallic  = 0.6
	mat_sp_pommel.roughness = 0.15
	sp_pommel.material_override = mat_sp_pommel
	spear_node.add_child(sp_pommel)

	# -- Slash Shader Effect --
	var sp_slash := MeshInstance3D.new()
	var sp_slash_mesh := QuadMesh.new()
	sp_slash_mesh.size = Vector2(2.5, 2.5)
	sp_slash.mesh = sp_slash_mesh
	sp_slash.position = Vector3(0, 1.5, 0)
	var mat_sp_slash := ShaderMaterial.new()
	mat_sp_slash.shader = load("res://assets/shaders/sword_slash.gdshader")
	mat_sp_slash.set_shader_parameter("emission_color", Color(0.3, 1.0, 0.5))
	mat_sp_slash.set_shader_parameter("energy", 3.0)
	mat_sp_slash.set_shader_parameter("progress", 0.0) # Animar en ataque
	sp_slash.material_override = mat_sp_slash
	spear_node.add_child(sp_slash)

	spear_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)),
		Vector3(0.42, 0.88, -0.35))
	mount.add_child(spear_node)
	weapon_models[WeaponData.WeaponType.SPEAR_LANCE] = spear_node

	# ══════════════════════════════════════════════════════════════════════════
	# 7. LANZALLAMAS — Flamethrower (Vangry's signature)
	#    Industrial flamethrower: thick receiver body, large round fuel drum,
	#    wide ribbed barrel with heat vents, pilot light gem at muzzle.
	# ══════════════════════════════════════════════════════════════════════════
	var flamer_node := Node3D.new()

	# -- Receiver body (chunky metal box)
	var fl_body := MeshInstance3D.new()
	var fl_body_mesh := BoxMesh.new()
	fl_body_mesh.size = Vector3(0.13, 0.18, 0.38)
	fl_body.mesh     = fl_body_mesh
	fl_body.position = Vector3(0, 0, -0.02)
	var mat_fl_body := StandardMaterial3D.new()
	mat_fl_body.albedo_color = Color(0.28, 0.32, 0.30)
	mat_fl_body.metallic     = 0.80
	mat_fl_body.roughness    = 0.35
	fl_body.material_override = mat_fl_body
	flamer_node.add_child(fl_body)

	# -- Fuel drum (big cylinder side-mounted)
	var fl_drum := MeshInstance3D.new()
	var fl_drum_mesh := CylinderMesh.new()
	fl_drum_mesh.top_radius    = 0.09
	fl_drum_mesh.bottom_radius = 0.09
	fl_drum_mesh.height        = 0.34
	fl_drum_mesh.radial_segments = 14
	fl_drum.mesh     = fl_drum_mesh
	fl_drum.rotation = Vector3(deg_to_rad(90), 0, 0)
	fl_drum.position = Vector3(0, 0.14, -0.05)
	var mat_fl_drum := StandardMaterial3D.new()
	mat_fl_drum.albedo_color            = Color(0.72, 0.22, 0.06)
	mat_fl_drum.metallic                = 0.65
	mat_fl_drum.roughness               = 0.38
	mat_fl_drum.emission_enabled        = true
	mat_fl_drum.emission                = Color(0.9, 0.2, 0.0)
	mat_fl_drum.emission_energy_multiplier = 1.8
	fl_drum.material_override = mat_fl_drum
	flamer_node.add_child(fl_drum)

	# -- Drum cap rings (2 metal rings capping the drum)
	for cap_z in [-0.175, 0.175]:
		var fl_cap := MeshInstance3D.new()
		var fl_cap_mesh := CylinderMesh.new()
		fl_cap_mesh.top_radius    = 0.093
		fl_cap_mesh.bottom_radius = 0.093
		fl_cap_mesh.height        = 0.022
		fl_cap_mesh.radial_segments = 14
		fl_cap.rotation = Vector3(deg_to_rad(90), 0, 0)
		fl_cap.position = Vector3(0, 0.14, -0.05 + cap_z)
		var mat_fl_cap := StandardMaterial3D.new()
		mat_fl_cap.albedo_color = Color(0.42, 0.40, 0.38)
		mat_fl_cap.metallic     = 0.9
		mat_fl_cap.roughness    = 0.22
		fl_cap.material_override = mat_fl_cap
		flamer_node.add_child(fl_cap)

	# -- Main barrel (ribbed wide tube)
	var fl_barrel := MeshInstance3D.new()
	var fl_barrel_mesh := CylinderMesh.new()
	fl_barrel_mesh.top_radius    = 0.035
	fl_barrel_mesh.bottom_radius = 0.055
	fl_barrel_mesh.height        = 0.60
	fl_barrel_mesh.radial_segments = 12
	fl_barrel.mesh     = fl_barrel_mesh
	fl_barrel.rotation = Vector3(deg_to_rad(90), 0, 0)
	fl_barrel.position = Vector3(0, -0.02, -0.55)
	var mat_fl_barrel := StandardMaterial3D.new()
	mat_fl_barrel.albedo_color = Color(0.22, 0.25, 0.24)
	mat_fl_barrel.metallic     = 0.85
	mat_fl_barrel.roughness    = 0.28
	fl_barrel.material_override = mat_fl_barrel
	flamer_node.add_child(fl_barrel)

	# -- Heat vent ribs (3 rings along barrel)
	for rib_z in [-0.36, -0.52, -0.68]:
		var fl_rib := MeshInstance3D.new()
		var fl_rib_mesh := CylinderMesh.new()
		fl_rib_mesh.top_radius    = 0.062
		fl_rib_mesh.bottom_radius = 0.062
		fl_rib_mesh.height        = 0.028
		fl_rib_mesh.radial_segments = 12
		fl_rib.mesh     = fl_rib_mesh
		fl_rib.rotation = Vector3(deg_to_rad(90), 0, 0)
		fl_rib.position = Vector3(0, -0.02, rib_z)
		var mat_fl_rib := StandardMaterial3D.new()
		mat_fl_rib.albedo_color            = Color(0.6, 0.35, 0.1)
		mat_fl_rib.emission_enabled        = true
		mat_fl_rib.emission                = Color(0.8, 0.3, 0.0)
		mat_fl_rib.emission_energy_multiplier = 1.8
		mat_fl_rib.metallic  = 0.6
		mat_fl_rib.roughness = 0.35
		fl_rib.material_override = mat_fl_rib
		flamer_node.add_child(fl_rib)

	# -- Pilot light / muzzle gem
	var fl_pilot := MeshInstance3D.new()
	var fl_pilot_mesh := SphereMesh.new()
	fl_pilot_mesh.radius = 0.040
	fl_pilot_mesh.height = 0.08
	fl_pilot.mesh     = fl_pilot_mesh
	fl_pilot.position = Vector3(0, -0.02, -0.87)
	var mat_fl_pilot := StandardMaterial3D.new()
	mat_fl_pilot.albedo_color            = Color(1.0, 0.82, 0.18)
	mat_fl_pilot.emission_enabled        = true
	mat_fl_pilot.emission                = Color(1.0, 0.75, 0.0)
	mat_fl_pilot.emission_energy_multiplier = 6.0
	fl_pilot.material_override = mat_fl_pilot
	flamer_node.add_child(fl_pilot)

	# -- Pistol grip
	var fl_grip := MeshInstance3D.new()
	var fl_grip_mesh := BoxMesh.new()
	fl_grip_mesh.size = Vector3(0.08, 0.20, 0.10)
	fl_grip.mesh     = fl_grip_mesh
	fl_grip.rotation = Vector3(deg_to_rad(-14), 0, 0)
	fl_grip.position = Vector3(0, -0.18, 0.14)
	var mat_fl_grip := StandardMaterial3D.new()
	mat_fl_grip.albedo_color = Color(0.08, 0.07, 0.06)
	mat_fl_grip.metallic     = 0.15
	mat_fl_grip.roughness    = 0.9
	fl_grip.material_override = mat_fl_grip
	flamer_node.add_child(fl_grip)

	flamer_node.transform = Transform3D(Basis(), Vector3(0.38, 0.92, -0.36))
	mount.add_child(flamer_node)
	weapon_models[WeaponData.WeaponType.FLAME_THROWER] = flamer_node

	# ══════════════════════════════════════════════════════════════════════════
	# 8. SPORE BAZOOKA — Bazuca de Esporas (Bronch's signature)
	#    Bio-organic launcher: mossy textured tube, bulbous spore pod, vine
	#    tendrils (approximated as thin rods), pulsing green muzzle mouth.
	# ══════════════════════════════════════════════════════════════════════════
	var bazooka_node := Node3D.new()

	# -- Main launch tube (wide cylinder)
	var bz_tube := MeshInstance3D.new()
	var bz_tube_mesh := CylinderMesh.new()
	bz_tube_mesh.top_radius    = 0.082
	bz_tube_mesh.bottom_radius = 0.088
	bz_tube_mesh.height        = 1.1
	bz_tube_mesh.radial_segments = 14
	bz_tube.mesh     = bz_tube_mesh
	bz_tube.position = Vector3(0, 0.12, 0)
	var mat_bz_tube := StandardMaterial3D.new()
	mat_bz_tube.albedo_color = Color(0.25, 0.35, 0.14)
	mat_bz_tube.metallic     = 0.35
	mat_bz_tube.roughness    = 0.72
	bz_tube.material_override = mat_bz_tube
	bazooka_node.add_child(bz_tube)

	# -- Tube reinforcement bands
	for band_y in [0.35, -0.1]:
		var bz_band := MeshInstance3D.new()
		var bz_band_mesh := CylinderMesh.new()
		bz_band_mesh.top_radius    = 0.096
		bz_band_mesh.bottom_radius = 0.096
		bz_band_mesh.height        = 0.055
		bz_band_mesh.radial_segments = 14
		bz_band.mesh     = bz_band_mesh
		bz_band.position = Vector3(0, band_y, 0)
		var mat_bz_band := StandardMaterial3D.new()
		mat_bz_band.albedo_color = Color(0.32, 0.42, 0.18)
		mat_bz_band.metallic     = 0.55
		mat_bz_band.roughness    = 0.5
		bz_band.material_override = mat_bz_band
		bazooka_node.add_child(bz_band)

	# -- Muzzle bell (flared front)
	var bz_bell := MeshInstance3D.new()
	var bz_bell_mesh := CylinderMesh.new()
	bz_bell_mesh.top_radius    = 0.13
	bz_bell_mesh.bottom_radius = 0.088
	bz_bell_mesh.height        = 0.18
	bz_bell_mesh.radial_segments = 16
	bz_bell.mesh     = bz_bell_mesh
	bz_bell.position = Vector3(0, 0.76, 0)
	var mat_bz_bell := StandardMaterial3D.new()
	mat_bz_bell.albedo_color            = Color(0.65, 0.90, 0.22)
	mat_bz_bell.emission_enabled        = true
	mat_bz_bell.emission                = Color(0.55, 0.95, 0.18)
	mat_bz_bell.emission_energy_multiplier = 2.8
	mat_bz_bell.metallic  = 0.3
	mat_bz_bell.roughness = 0.45
	bz_bell.material_override = mat_bz_bell
	bazooka_node.add_child(bz_bell)

	# -- Spore pod (large bulbous canister, organic sphere)
	var bz_pod := MeshInstance3D.new()
	var bz_pod_mesh := SphereMesh.new()
	bz_pod_mesh.radius = 0.17
	bz_pod_mesh.height = 0.34
	bz_pod_mesh.rings  = 14
	bz_pod.mesh     = bz_pod_mesh
	bz_pod.position = Vector3(0, -0.14, -0.12)
	var mat_bz_pod := StandardMaterial3D.new()
	mat_bz_pod.albedo_color            = Color(0.68, 0.92, 0.22)
	mat_bz_pod.emission_enabled        = true
	mat_bz_pod.emission                = Color(0.6, 0.95, 0.18)
	mat_bz_pod.emission_energy_multiplier = 3.0
	mat_bz_pod.metallic  = 0.1
	mat_bz_pod.roughness = 0.8
	bz_pod.material_override = mat_bz_pod
	bazooka_node.add_child(bz_pod)

	# -- Vine tendril rods (3 thin rods wrapping around body)
	for t in range(3):
		var bz_tendril := MeshInstance3D.new()
		var bz_tendril_mesh := CylinderMesh.new()
		bz_tendril_mesh.top_radius    = 0.012
		bz_tendril_mesh.bottom_radius = 0.012
		bz_tendril_mesh.height        = 0.55
		bz_tendril_mesh.radial_segments = 6
		bz_tendril.mesh     = bz_tendril_mesh
		var angle_t := deg_to_rad(t * 120 + 30)
		bz_tendril.position = Vector3(sin(angle_t) * 0.1, 0.12 + t * 0.05, cos(angle_t) * 0.1)
		bz_tendril.rotation = Vector3(deg_to_rad(12 * (t - 1)), angle_t, 0)
		var mat_bz_tendril := StandardMaterial3D.new()
		mat_bz_tendril.albedo_color = Color(0.15, 0.28, 0.10)
		mat_bz_tendril.metallic     = 0.05
		mat_bz_tendril.roughness    = 0.95
		bz_tendril.material_override = mat_bz_tendril
		bazooka_node.add_child(bz_tendril)

	# -- Rear grip
	var bz_grip := MeshInstance3D.new()
	var bz_grip_mesh := BoxMesh.new()
	bz_grip_mesh.size = Vector3(0.09, 0.28, 0.10)
	bz_grip.mesh     = bz_grip_mesh
	bz_grip.rotation = Vector3(deg_to_rad(-10), 0, 0)
	bz_grip.position = Vector3(0, -0.60, 0.06)
	var mat_bz_grip := StandardMaterial3D.new()
	mat_bz_grip.albedo_color = Color(0.14, 0.20, 0.10)
	mat_bz_grip.metallic     = 0.2
	mat_bz_grip.roughness    = 0.88
	bz_grip.material_override = mat_bz_grip
	bazooka_node.add_child(bz_grip)

	bazooka_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)),
		Vector3(0.42, 0.88, -0.35))
	mount.add_child(bazooka_node)
	weapon_models[WeaponData.WeaponType.SPORE_BAZOOKA] = bazooka_node

	# ══════════════════════════════════════════════════════════════════════════
	# 9. DUAL DAGGERS — Dagas Gemelas de Crane (signature)
	#    Paired combat knives: narrow tapered blades with ricasso, angular
	#    guards, wrapped grips. Left blade = crimson, right = sapphire.
	# ══════════════════════════════════════════════════════════════════════════
	var daggers_node := Node3D.new()

	for dagger_idx in range(2):
		var side_sign: float = 1.0 if dagger_idx == 0 else -1.0
		var dagger_color_blade: Color = Color(1.0, 0.12, 0.12) if dagger_idx == 0 else Color(0.12, 0.38, 1.0)
		var dagger_emit_blade: Color  = Color(1.0, 0.08, 0.05) if dagger_idx == 0 else Color(0.05, 0.28, 1.0)

		var single_dagger := Node3D.new()
		single_dagger.position = Vector3(side_sign * 0.115, 0.0, 0.0)

		# Blade (slim tapered box)
		var dd_blade := MeshInstance3D.new()
		var dd_blade_mesh := CylinderMesh.new()
		dd_blade_mesh.top_radius    = 0.004
		dd_blade_mesh.bottom_radius = 0.025
		dd_blade_mesh.height        = 0.58
		dd_blade_mesh.radial_segments = 6
		dd_blade.mesh     = dd_blade_mesh
		dd_blade.position = Vector3(0, 0.44, 0)
		var mat_dd_blade := StandardMaterial3D.new()
		mat_dd_blade.albedo_color            = dagger_color_blade
		mat_dd_blade.emission_enabled        = true
		mat_dd_blade.emission                = dagger_emit_blade
		mat_dd_blade.emission_energy_multiplier = 3.0
		mat_dd_blade.metallic  = 0.7
		mat_dd_blade.roughness = 0.12
		dd_blade.material_override = mat_dd_blade
		single_dagger.add_child(dd_blade)

		# Blade flat face highlight
		var dd_edge := MeshInstance3D.new()
		var dd_edge_mesh := BoxMesh.new()
		dd_edge_mesh.size = Vector3(0.006, 0.52, 0.032)
		dd_edge.mesh     = dd_edge_mesh
		dd_edge.position = Vector3(0, 0.44, 0)
		var mat_dd_edge := StandardMaterial3D.new()
		mat_dd_edge.albedo_color            = Color(0.95, 0.98, 1.0)
		mat_dd_edge.emission_enabled        = true
		mat_dd_edge.emission                = Color(0.8, 0.9, 1.0)
		mat_dd_edge.emission_energy_multiplier = 2.0
		mat_dd_edge.metallic  = 0.9
		mat_dd_edge.roughness = 0.05
		dd_edge.material_override = mat_dd_edge
		single_dagger.add_child(dd_edge)

		# Guard (angular cross piece)
		var dd_guard := MeshInstance3D.new()
		var dd_guard_mesh := BoxMesh.new()
		dd_guard_mesh.size = Vector3(0.165, 0.038, 0.042)
		dd_guard.mesh     = dd_guard_mesh
		dd_guard.position = Vector3(0, 0.13, 0)
		var mat_dd_guard := StandardMaterial3D.new()
		mat_dd_guard.albedo_color = Color(0.22, 0.24, 0.28)
		mat_dd_guard.metallic     = 0.75
		mat_dd_guard.roughness    = 0.30
		dd_guard.material_override = mat_dd_guard
		single_dagger.add_child(dd_guard)

		# Grip (textured cylinder)
		var dd_grip := MeshInstance3D.new()
		var dd_grip_mesh := CylinderMesh.new()
		dd_grip_mesh.top_radius    = 0.022
		dd_grip_mesh.bottom_radius = 0.025
		dd_grip_mesh.height        = 0.24
		dd_grip_mesh.radial_segments = 8
		dd_grip.mesh     = dd_grip_mesh
		dd_grip.position = Vector3(0, -0.02, 0)
		var mat_dd_grip := StandardMaterial3D.new()
		mat_dd_grip.albedo_color = Color(0.10, 0.11, 0.14)
		mat_dd_grip.metallic     = 0.15
		mat_dd_grip.roughness    = 0.88
		dd_grip.material_override = mat_dd_grip
		single_dagger.add_child(dd_grip)

		# Pommel cap
		var dd_pommel := MeshInstance3D.new()
		var dd_pommel_mesh := SphereMesh.new()
		dd_pommel_mesh.radius = 0.030
		dd_pommel_mesh.height = 0.06
		dd_pommel.mesh     = dd_pommel_mesh
		dd_pommel.position = Vector3(0, -0.165, 0)
		var mat_dd_pommel := StandardMaterial3D.new()
		mat_dd_pommel.albedo_color            = dagger_color_blade
		mat_dd_pommel.emission_enabled        = true
		mat_dd_pommel.emission                = dagger_emit_blade
		mat_dd_pommel.emission_energy_multiplier = 2.5
		mat_dd_pommel.metallic  = 0.6
		mat_dd_pommel.roughness = 0.2
		dd_pommel.material_override = mat_dd_pommel
		single_dagger.add_child(dd_pommel)

		daggers_node.add_child(single_dagger)

	daggers_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)),
		Vector3(0.42, 0.88, -0.35))
	mount.add_child(daggers_node)
	weapon_models[WeaponData.WeaponType.DUAL_DAGGERS] = daggers_node

	# ══════════════════════════════════════════════════════════════════════════
	# 10. DUSTS — Polvos Alquímicos (Tatan)  — alchemy flask with glowing dust.
	# ══════════════════════════════════════════════════════════════════════════
	var dust_node := Node3D.new()
	var dust_flask := MeshInstance3D.new()
	var dust_flask_mesh := SphereMesh.new()
	dust_flask_mesh.radius = 0.09
	dust_flask_mesh.height = 0.2
	dust_flask.mesh = dust_flask_mesh
	dust_flask.position = Vector3(0, 0.05, 0)
	var mat_dust_flask := StandardMaterial3D.new()
	mat_dust_flask.albedo_color = Color(0.75, 0.2, 0.85)
	mat_dust_flask.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_dust_flask.albedo_color.a = 0.55
	mat_dust_flask.emission_enabled = true
	mat_dust_flask.emission = Color(0.7, 0.15, 0.9)
	mat_dust_flask.emission_energy_multiplier = 2.5
	dust_flask.material_override = mat_dust_flask
	dust_node.add_child(dust_flask)
	var dust_neck := MeshInstance3D.new()
	var dust_neck_mesh := CylinderMesh.new()
	dust_neck_mesh.top_radius = 0.03
	dust_neck_mesh.bottom_radius = 0.045
	dust_neck_mesh.height = 0.12
	dust_neck.mesh = dust_neck_mesh
	dust_neck.position = Vector3(0, 0.2, 0)
	dust_neck.material_override = mat_dust_flask
	dust_node.add_child(dust_neck)
	dust_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)),
		Vector3(0.42, 0.88, -0.35))
	mount.add_child(dust_node)
	weapon_models[WeaponData.WeaponType.DUSTS] = dust_node

	# ══════════════════════════════════════════════════════════════════════════
	# 11. AIR FISTS — Puños de Aire (Kaionz) — pair of glowing arcane gauntlets.
	# ══════════════════════════════════════════════════════════════════════════
	var fists_node := Node3D.new()
	for fi in range(2):
		var fist := MeshInstance3D.new()
		var fist_mesh := BoxMesh.new()
		fist_mesh.size = Vector3(0.14, 0.2, 0.12)
		fist.mesh = fist_mesh
		var fist_mat := StandardMaterial3D.new()
		fist_mat.albedo_color = Color(0.5, 0.85, 1.0)
		fist_mat.emission_enabled = true
		fist_mat.emission = Color(0.3, 0.75, 1.0)
		fist_mat.emission_energy_multiplier = 2.2
		fist.material_override = fist_mat
		fist.position = Vector3((0.12 if fi == 0 else -0.12), 0.05, 0)
		fists_node.add_child(fist)
		var fist_glow := MeshInstance3D.new()
		var glow_mesh := SphereMesh.new()
		glow_mesh.radius = 0.06
		glow_mesh.height = 0.1
		fist_glow.mesh = glow_mesh
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.8, 0.95, 1.0)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(0.5, 0.9, 1.0)
		glow_mat.emission_energy_multiplier = 3.0
		fist_glow.material_override = glow_mat
		fist_glow.position = fist.position + Vector3(0, 0.16, 0)
		fists_node.add_child(fist_glow)
	fists_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)),
		Vector3(0.42, 0.88, -0.35))
	mount.add_child(fists_node)
	weapon_models[WeaponData.WeaponType.AIR_FISTS] = fists_node

	# ══════════════════════════════════════════════════════════════════════════
	# 12. SERPENTS — Serpientes de Joel — esmeralda enroscada alrededor del brazo.
	# ══════════════════════════════════════════════════════════════════════════
	var serpent_node := Node3D.new()

	var sn_body_mat := StandardMaterial3D.new()
	sn_body_mat.albedo_color = Color(0.25, 0.85, 0.4)
	sn_body_mat.emission_enabled = true
	sn_body_mat.emission = Color(0.1, 0.9, 0.35)
	sn_body_mat.emission_energy_multiplier = 2.0
	sn_body_mat.metallic = 0.4
	sn_body_mat.roughness = 0.4

	# Cuerpo enroscado: espiral de esferas alrededor del antebrazo (eje Z).
	var coils := 9
	for i in range(coils):
		var seg := MeshInstance3D.new()
		var seg_mesh := SphereMesh.new()
		var r := lerpf(0.055, 0.035, float(i) / float(coils - 1))
		seg_mesh.radius = r
		seg_mesh.height = r * 2.0
		seg.mesh = seg_mesh
		seg.material_override = sn_body_mat
		var angle := float(i) / float(coils) * TAU
		seg.position = Vector3(cos(angle) * 0.09, sin(angle) * 0.09, -0.3 + float(i) / float(coils) * 0.55)
		serpent_node.add_child(seg)

	# Cabeza erguida mirando hacia delante (-Z del jugador).
	var sn_head := MeshInstance3D.new()
	var sn_head_mesh := SphereMesh.new()
	sn_head_mesh.radius = 0.085
	sn_head_mesh.height = 0.17
	sn_head.mesh = sn_head_mesh
	sn_head.material_override = sn_body_mat
	sn_head.position = Vector3(0, 0.13, -0.32)
	serpent_node.add_child(sn_head)

	# Ojos brillantes.
	for side in [-0.045, 0.045]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.02
		eye_mesh.height = 0.04
		eye.mesh = eye_mesh
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(1.0, 0.92, 0.4)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.85, 0.25)
		eye_mat.emission_energy_multiplier = 2.5
		eye.material_override = eye_mat
		eye.position = Vector3(side, 0.16, -0.38)
		serpent_node.add_child(eye)

	serpent_node.transform = Transform3D(
		Basis().rotated(Vector3.RIGHT, deg_to_rad(-10)),
		Vector3(0.35, 0.85, -0.35))
	mount.add_child(serpent_node)
	weapon_models[WeaponData.WeaponType.SERPENTS] = serpent_node
