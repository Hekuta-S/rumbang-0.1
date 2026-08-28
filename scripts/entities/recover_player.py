import json

transcript_path = r'C:\Users\cabeu\.gemini\antigravity-cli\brain\1ee1a537-7ecc-4444-9977-2b7aac039067\.system_generated\logs\transcript_full.jsonl'
output_path = r'D:\GodotProjects\tesis\scripts\entities\player.gd'

lines_found = []
with open(transcript_path, 'r', encoding='utf-8') as f:
    for line in f:
        if 'Total Lines: 820' in line and 'extends CharacterBody3D' in line:
            try:
                data = json.loads(line)
                content = data.get('content', '')
                if 'Total Lines: 820' in content:
                    lines = content.split('\n')
                    capturing = False
                    for l in lines:
                        if '1: extends CharacterBody3D' in l:
                            capturing = True
                        if capturing:
                            if 'The above content does NOT show' in l:
                                break
                            parts = l.split(': ', 1)
                            if len(parts) == 2 and parts[0].isdigit():
                                lines_found.append(parts[1])
                    if len(lines_found) > 0:
                        break
            except:
                pass

tail_lines = """func get_weapon_ammo(w_type: int) -> int:
	return combat_controller.get_weapon_ammo(w_type)

func start_reload() -> void:
	combat_controller.start_reload()

func auto_attack(target: Node3D) -> void:
	combat_controller.auto_attack(target)

func attack() -> void:
	combat_controller.attack()
	
func throw_spear() -> void:
	combat_controller.throw_spear()

func _on_alt_attack_pressed() -> void:
	if current_weapon() == WeaponData.WeaponType.DUAL_DAGGERS:
		combat_controller.attack_dual_daggers_heavy(0.5 if is_berserk else 1.0)
	elif current_weapon() == WeaponData.WeaponType.DUSTS:
		combat_controller.cycle_dust_mode()
	else:
		throw_spear()

func _on_toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_spawn_debug_enemy() -> void:
	var enemy_scene = load("res://scenes/entities/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	get_parent().add_child(enemy)
	var forward_dir = -global_transform.basis.z
	enemy.global_position = global_position + forward_dir * 10.0 + Vector3(0, 1, 0)
"""

with open(output_path, 'w', encoding='utf-8') as out:
    for l in lines_found:
        if 'func _on_alt_attack_pressed() -> void:' in l:
            break
        out.write(l.strip('\r') + '\n')
    out.write(tail_lines)

print(f'Recovered {len(lines_found)} lines and appended tail.')
