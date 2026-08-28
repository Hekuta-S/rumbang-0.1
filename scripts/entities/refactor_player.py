import re
import sys

def main():
    file_path = "D:/GodotProjects/soul-knight-3d---third-person-roguelike-(copy) - copia/scripts/entities/player.gd"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Enum and export var for character selection
    enum_code = """
enum CharacterClass { MIKEURA, TATAN, KNIGHT }
@export var selected_character: CharacterClass = CharacterClass.MIKEURA

"""
    # Preload TATAN
    tatan_preload = """
const TATAN_IDLE_SCENE  = preload("res://assets/models/tatan/idle.fbx")
const TATAN_WALK_SCENE  = preload("res://assets/models/tatan/caminar.fbx")
const TATAN_ATTACK_SCENE = preload("res://assets/models/tatan/basic_atack.fbx")
"""
    
    # We will rename the constants and variables where appropriate
    content = content.replace("var mikeura_model: Node3D = null", "var character_model: Node3D = null")
    content = content.replace("var mikeura_anim: AnimationPlayer = null", "var character_anim: AnimationPlayer = null")
    content = content.replace("var mikeura_tree: AnimationTree = null", "var character_tree: AnimationTree = null")
    content = content.replace("var mikeura_playback: AnimationNodeStateMachinePlayback = null", "var character_playback: AnimationNodeStateMachinePlayback = null")
    
    # Rename references to these variables
    content = content.replace("mikeura_model", "character_model")
    content = content.replace("mikeura_anim", "character_anim")
    content = content.replace("mikeura_tree", "character_tree")
    content = content.replace("mikeura_playback", "character_playback")

    # Rename setup functions
    content = content.replace("setup_mikeura_model", "setup_character_model")
    content = content.replace("_fit_mikeura_model", "_fit_character_model")
    content = content.replace("_advance_mikeura_combo", "_advance_character_combo")
    content = content.replace("_update_mikeura_walk_blend", "_update_character_walk_blend")
    content = content.replace("mikeura_combo_last_press_ms", "character_combo_last_press_ms")
    content = content.replace("MIKEURA_COMBO_WINDOW_MS", "CHARACTER_COMBO_WINDOW_MS")
    content = content.replace("_handle_mikeura_combo_input", "_handle_character_combo_input")
    content = content.replace("_mikeura_input_buffer", "_character_input_buffer")

    # Add Enum to the top after signals
    if "signal player_died" in content:
        content = content.replace("signal player_died", "signal player_died\n" + enum_code)

    # Add TATAN preloads after MIKEURA preloads
    if "const MIKEURA_2HANDS_SCENE = preload(\"res://assets/models/mikeura/ataque_2manos.fbx\")" in content:
        content = content.replace("const MIKEURA_2HANDS_SCENE = preload(\"res://assets/models/mikeura/ataque_2manos.fbx\")", 
                                  "const MIKEURA_2HANDS_SCENE = preload(\"res://assets/models/mikeura/ataque_2manos.fbx\")\n" + tatan_preload)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
        
    print("Variables renamed.")

if __name__ == "__main__":
    main()
