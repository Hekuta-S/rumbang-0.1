import os
import re

path = r'D:\GodotProjects\tesis\scripts\core\main.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove music/sfx vars
content = re.sub(r'var bg_music: AudioStreamPlayer\nvar level_up_sfx: AudioStreamPlayer\n', '', content)

# 2. Refactor _ready()
# Remove old audio and connections in _ready()
_ready_pattern = r'func _ready\(\) -> void:.*?hud\.restart_pressed\.connect\(_on_restart_pressed\)\n\n\tvar pause_menu = preload\("res://scenes/ui/pause_menu\.tscn"\)\.instantiate\(\)\n\tadd_child\((pause_menu)\)'
def _ready_replacement(m):
    return """func _ready() -> void:
	var ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	ui_manager.initialize(hud, player)
	ui_manager.restart_pressed.connect(start_game)
	player.player_died.connect(_on_player_died)"""
content = re.sub(_ready_pattern, _ready_replacement, content, flags=re.DOTALL)

# 3. Modify start_game()
start_game_pattern = r'func start_game\(\) -> void:(.*?)refresh_weapon_ui\(\)'
def start_game_replacement(m):
    body = m.group(1)
    body = body.replace('hud.update_floor(sub_level)', '$UIManager.update_floor(sub_level)')
    body = body.replace('hud.update_gold(gold)', '$UIManager.update_gold(gold)')
    body = body.replace('hud.game_over_screen.visible = false', '$UIManager.reset_screens()')
    body = body.replace('hud.victory_screen.visible = false', '')
    return f"func start_game() -> void:{body}$UIManager.refresh_weapon_ui()"
content = re.sub(start_game_pattern, start_game_replacement, content, flags=re.DOTALL)

# 4. Remove UI functions
content = re.sub(r'^func show_item_choice\(\).*?^func _on_enemy_died', 'func _on_enemy_died', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^func _on_player_stats_changed\(.*?^func _on_player_died\(\) -> void:\n', 'func _on_player_died() -> void:\n', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^func _on_player_weapon_attacked\(.*?^func _on_restart_pressed', 'func _on_restart_pressed', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^func _on_restart_pressed\(\) -> void:\n\tstart_game\(\)\n', '', content, flags=re.MULTILINE | re.DOTALL)

# 5. Modify _on_player_died to only save
old_player_died = """func _on_player_died() -> void:
	hud.show_game_over()
	SaveManager.set_best_floor(_char_id(), sub_level)"""
new_player_died = """func _on_player_died() -> void:
	SaveManager.set_best_floor(_char_id(), sub_level)"""
content = content.replace(old_player_died, new_player_died)

# 6. Update HUD references in _on_enemy_died, _on_wave_cleared, _on_boss_died
content = content.replace('hud.update_gold(gold)', '$UIManager.update_gold(gold)')
content = content.replace('hud.update_floor(sub_level)', '$UIManager.update_floor(sub_level)')
content = content.replace('hud.show_victory()', '$UIManager.show_victory()')

# cleanup double blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done!')
