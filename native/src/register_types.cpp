// Registro de la extensi√≥n nativa de Rumbang.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "enemy_motion_native.h"
#include "enemy_sim_native.h"
#include "terrain_native.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>

using namespace godot;

static void initialize_rumbang_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	// FastNoiseLite llega como argumento (TerrainNative.build): su registro autom·tico de godot-cpp no
	// siempre se emite (variable inline sin usar) y Godot avisaba "Cannot find instance binding callbacks".
	internal::register_engine_class(FastNoiseLite::get_class_static(), &FastNoiseLite::_gde_binding_callbacks);
	// Los EnemyData (RefCounted de GDScript) llegan como Object* a EnemySimNative.add: mismo problema.
	internal::register_engine_class(RefCounted::get_class_static(), &RefCounted::_gde_binding_callbacks);
	GDREGISTER_CLASS(EnemyMotionNative);
	GDREGISTER_CLASS(EnemySimNative);
	GDREGISTER_CLASS(TerrainNative);
}

static void uninitialize_rumbang_native(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT rumbang_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_rumbang_native);
	init_obj.register_terminator(uninitialize_rumbang_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
