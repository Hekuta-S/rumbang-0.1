class_name MovementSource extends RefCounted

## PATRÓN ADAPTER (estructural) — rol: Target
## Problema previo: PlayerInputController.get_movement_vector() conocía a la vez el autoload
## VirtualInput (táctil), las teclas WASD y los ejes del mando, mezclando tres APIs distintas.
## Target: interfaz única que espera el Client (PlayerInputController).
##   Adaptee  : VirtualInput (táctil), Input.is_key_pressed (teclado), Input.get_joy_axis (mando)
##   Adapter  : TouchMovementAdapter, KeyboardMovementAdapter, GamepadMovementAdapter

func get_movement_vector() -> Vector2:
	return Vector2.ZERO
