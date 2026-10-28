# Combate Mazmorras - Fase 2 ("El Combate que Queremos") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar la experiencia de combate deliberada, legible y contundente para el modo mazmorra de Rumbang según la Sección 1 de `AUDITORIA_COMBATE_MAZMORRAS.md` (hitboxes ligadas a la animación y al jugador, búfer y enlace de combo, apuntado suave, esquiva con invulnerabilidad, feedback diferenciado y un goblin de mazmorra con telegrafía completa).

**Architecture:** Se desacopla el combate de mazmorra del bucle global de hordas: las animaciones de Mikeura dirigen el momento exacto del impacto (`hit_on`/`hit_off`) y la hitbox viaja pegada al mesh del jugador. El enemigo de mazmorra (`DungeonEnemy`) es un nodo `CharacterBody3D` con máquina de estados independiente (anticipación con telegrafía, ataque, recuperación, reacción y muerte) que respeta el contrato neutral de `EnemyRegistry` sin alterar el rendimiento ni el código de supervivencia.

**Tech Stack:** Godot 4.7.1, GDScript, AnimationTree, AnimationLibrary (method tracks), Area3D, CharacterBody3D.

## Global Constraints

- Compatibilidad total con el modo supervivencia: `game_mode == "survival"` no debe verse alterado ni arrojar errores de script.
- Los assets en `assets/` no están versionados en git; no se deben borrar ni mover modelos ni texturas existentes.
- Sin ataque automático en mazmorra: en `game_mode == "dungeon"`, cada ataque debe nacer de la acción manual del jugador.
- Hitbox sincronizada con animación: el daño ocurre únicamente dentro de las ventanas activas (`ATTACK_WINDOWS`), nunca en `t=0` del clic.
- La orientación del jugador queda fija durante la ventana activa del golpe (salvo corrección suave previa al inicio del ataque).

---

### Task 1: Desactivar auto-ataque en mazmorra, apuntado suave y control de carga

**Files:**
- Modify: `scripts/entities/player.gd:263-268`
- Modify: `scripts/components/player_combat_controller.gd:150-180, 215-245`
- Test: `tests/test_dungeon_combat_manual.gd`

**Interfaces:**
- Consumes: `GameData.game_mode`, `EnemyRegistry.all()`, `player.mesh`
- Produces: `player.orient_soft_aim(target_dir: Vector3)`

- [ ] **Step 1: Escribir el script de prueba para validar que auto_combat no se crea en mazmorra y que el apuntado suave orienta hacia el enemigo en cono**

```gdscript
# tests/test_dungeon_combat_manual.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 1: AUTO COMBAT & SOFT AIM ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	
	# Verificar que AutoCombatController no existe en modo dungeon
	var auto_node = player.get_node_or_null("AutoCombatController")
	assert(auto_node == null, "AutoCombatController NO debe instanciarse en modo dungeon")
	print("CHECK 1 PASSED: AutoCombatController deshabilitado en mazmorra")
	
	# Probar bloqueo de combo durante carga de lanza
	player.combat_controller.spear_charge = 0.5
	var cd_before = player.combat_controller.attack_cooldown
	player.combat_controller.attack()
	assert(player.combat_controller.spear_charge == 0.5, "Attack no debe romper la carga")
	player.combat_controller.spear_charge = -1.0
	print("CHECK 2 PASSED: Carga de lanza protege contra ataques simultáneos")
	
	player.queue_free()
	print("ALL TASK 1 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y confirmar que falla**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dungeon_combat_manual.gd
```
Expected: FAIL porque `AutoCombatController` aún se crea incondicionalmente en `player.gd:263`.

- [ ] **Step 3: Modificar `player.gd` y `player_combat_controller.gd`**

En `scripts/entities/player.gd`:
```gdscript
	# Solo activar auto combat si está habilitado y NO estamos en la mazmorra
	if combat_controller.is_auto_combat_enabled and GameData.game_mode != "dungeon":
		var auto_combat_script = load("res://scripts/components/auto_combat_controller.gd")
		var auto_combat_node = auto_combat_script.new()
		auto_combat_node.name = "AutoCombatController"
		add_child(auto_combat_node)
```

En `scripts/components/player_combat_controller.gd`:
Añadir soporte para apuntado suave hacia enemigos cercanos en el cono frontal antes de atacar y bloquear el ataque manual si `spear_charge >= 0.0`:
```gdscript
func get_soft_aim_direction(max_angle_deg: float = 60.0, max_dist: float = 8.0) -> Vector3:
	var forward: Vector3 = -player.mesh.global_transform.basis.z.normalized()
	forward.y = 0.0
	forward = forward.normalized()
	
	var best_dir := forward
	var best_dot := cos(deg_to_rad(max_angle_deg))
	var enemies = EnemyRegistry.all()
	var p_pos = player.global_position
	
	for e in enemies:
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var to_e = (e.global_position - p_pos)
		to_e.y = 0.0
		var d = to_e.length()
		if d > max_dist or d < 0.2:
			continue
		var dir = to_e / d
		var dot = forward.dot(dir)
		if dot > best_dot:
			best_dot = dot
			best_dir = dir
	return best_dir
```
En `attack()`:
```gdscript
	if attack_cooldown > 0: return
	if spear_charge >= 0.0: return # Bloqueado durante carga
```

- [ ] **Step 4: Ejecutar el test y confirmar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dungeon_combat_manual.gd
```
Expected: `ALL TASK 1 CHECKS PASSED` con exit code 0.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/entities/player.gd scripts/components/player_combat_controller.gd tests/test_dungeon_combat_manual.gd
git commit -m "feat(combat): desactivar auto combat en mazmorra y anadir apuntado suave"
```

---

### Task 2: Ventanas de impacto sincronizadas con la animación y hitbox ligada al jugador

**Files:**
- Modify: `scripts/components/player_animation_controller.gd`
- Modify: `scripts/components/weapon_strategy.gd`
- Modify: `scripts/objects/melee_hitbox.gd`
- Test: `tests/test_hitbox_sync.gd`

**Interfaces:**
- Consumes: `ATTACK_WINDOWS = { "attack1": [0.20, 0.36], "attack2": [0.22, 0.55], "attack3": [0.45, 0.60] }`
- Produces: Señales `hit_window_opened(attack_id: int, anim_name: String)` y `hit_window_closed(attack_id: int)` en `player_animation_controller`

- [ ] **Step 1: Escribir el test de sincronización de ventanas de método y fijación de hitbox al jugador**

```gdscript
# tests/test_hitbox_sync.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 2: HITBOX SYNC & MESH ATTACHMENT ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	
	var anim_ctrl = player.animation_controller
	assert(anim_ctrl != null, "Player debe tener animation_controller")
	assert(anim_ctrl.has_user_signal("hit_window_opened") or anim_ctrl.has_signal("hit_window_opened"), "Debe emitir hit_window_opened")
	
	# Verificar inyección de pistas de método
	var lib = anim_ctrl.anim_player.get_animation_library("")
	for a_name in ["attack1", "attack2", "attack3"]:
		if lib.has_animation(a_name):
			var a = lib.get_animation(a_name)
			var has_method_track := false
			for i in a.get_track_count():
				if a.track_get_type(i) == Animation.TYPE_METHOD:
					has_method_track = true
					break
			assert(has_method_track, "La animación %s debe tener pista de método" % a_name)
	print("CHECK: Pistas de método inyectadas en animaciones de ataque")
	
	player.queue_free()
	print("ALL TASK 2 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y verificar que falla**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_hitbox_sync.gd
```
Expected: FAIL porque aún no se inyectan las pistas de método ni existe la señal `hit_window_opened`.

- [ ] **Step 3: Implementar la inyección de pistas de método y el despacho de hitbox**

En `scripts/components/player_animation_controller.gd`:
- Declarar señales:
  ```gdscript
  signal hit_window_opened(attack_id: int, anim_name: String)
  signal hit_window_closed(attack_id: int)
  ```
- Constante con los tiempos de ventana:
  ```gdscript
  const ATTACK_WINDOWS := {
  	"attack1": [0.20, 0.36],
  	"attack2": [0.22, 0.55],
  	"attack3": [0.45, 0.60]
  }
  var current_attack_id: int = 0
  var active_attack_name: String = ""
  ```
- En `_merge_first_animation_from_scene` o tras cargar los ataques, agregar la pista de método al `Animation`:
  ```gdscript
  func _inject_hit_method_tracks(anim: Animation, anim_name: String) -> void:
  	if not ATTACK_WINDOWS.has(anim_name): return
  	var window: Array = ATTACK_WINDOWS[anim_name]
  	var track_idx = anim.add_track(Animation.TYPE_METHOD)
  	anim.track_set_path(track_idx, "CharacterModel/..:animation_controller") # o nodo controlador
  	# Claves de método:
  	anim.track_insert_key(track_idx, window[0], {"method": "_on_anim_hit_on", "args": [anim_name]})
  	anim.track_insert_key(track_idx, window[1], {"method": "_on_anim_hit_off", "args": [anim_name]})
  ```
- Implementar los métodos llamados por la pista:
  ```gdscript
  func _on_anim_hit_on(anim_name: String) -> void:
  	current_attack_id += 1
  	active_attack_name = anim_name
  	# Disparar dash coordinado con el impacto
  	_trigger_hit_dash(anim_name)
  	hit_window_opened.emit(current_attack_id, anim_name)

  func _on_anim_hit_off(_anim_name: String) -> void:
  	hit_window_closed.emit(current_attack_id)
  	active_attack_name = ""
  ```
- En `scripts/components/weapon_strategy.gd` (`SpearLanceStrategy`):
  Conectar `hit_window_opened` y `hit_window_closed` en modo mazmorra:
  Cuando abre la ventana: instanciar la hitbox como **hija de `c.player.mesh`** para que acompañe el movimiento:
  - `attack1`: pasillo frontal (escala Z alargada hacia delante).
  - `attack2`: barrido 360° (caja o cilindro centrado en el jugador).
  - `attack3`: impacto en área frontal con mayor knockback y daño.
  Cuando cierra la ventana: liberar la hitbox activa de forma limpia.
  Fallback: si es modo supervivencia (`game_mode == "survival"`), mantener el spawn estático actual en el mundo sin alterar nada.

- [ ] **Step 4: Ejecutar el test y confirmar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_hitbox_sync.gd
```
Expected: `ALL TASK 2 CHECKS PASSED`.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/components/player_animation_controller.gd scripts/components/weapon_strategy.gd scripts/objects/melee_hitbox.gd tests/test_hitbox_sync.gd
git commit -m "feat(combat): ventanas de impacto sincronizadas con animacion y hitbox en player.mesh"
```

---

### Task 3: Búfer de entrada y ventana de enlace del combo

**Files:**
- Modify: `scripts/components/player_combat_controller.gd`
- Modify: `scripts/components/player_animation_controller.gd`
- Test: `tests/test_combo_buffer.gd`

**Interfaces:**
- Consumes: Clics del usuario (`attack_pressed`), estados del combo (`_combo_index`, `_combo_timer`)
- Produces: Búfer de entrada (`_attack_buffered`), ventana de enlace (`_in_combo_link_window`)

- [ ] **Step 1: Escribir el test para el búfer de entrada y transición del combo**

```gdscript
# tests/test_combo_buffer.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 3: COMBO BUFFER & LINK WINDOW ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	
	var combat = player.combat_controller
	var anim = player.animation_controller
	
	# Simular clic en buffer
	combat.buffer_attack()
	assert(combat.is_attack_buffered(), "El ataque debe estar en el buffer")
	
	player.queue_free()
	print("ALL TASK 3 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y confirmar que falla**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_combo_buffer.gd
```
Expected: FAIL porque `buffer_attack` no existe aún.

- [ ] **Step 3: Implementar búfer de entrada y ventana de enlace**

En `scripts/components/player_combat_controller.gd`:
```gdscript
const INPUT_BUFFER_TIME: float = 0.28
var _attack_buffer_timer: float = 0.0

func buffer_attack() -> void:
	if spear_charge >= 0.0: return
	_attack_buffer_timer = INPUT_BUFFER_TIME
	_try_consume_buffered_attack()

func is_attack_buffered() -> bool:
	return _attack_buffer_timer > 0.0

func _try_consume_buffered_attack() -> void:
	if _attack_buffer_timer <= 0.0: return
	if player.animation_controller and player.animation_controller.is_in_link_window():
		_attack_buffer_timer = 0.0
		player.animation_controller.advance_combo()
	elif attack_cooldown <= 0.0 and not (player.animation_controller and player.animation_controller.is_attacking()):
		_attack_buffer_timer = 0.0
		attack()
```
En `scripts/components/player_animation_controller.gd`:
- Definir ventanas de enlace por cada golpe (ej. para `attack1`, entre 0.30s y 0.65s).
- Si se llama `advance_combo()`, pasa directamente al siguiente golpe del combo (1 -> 2 -> 3).
- Al expirar la animación sin input en la ventana de enlace, el combo vuelve a `attack1`.

- [ ] **Step 4: Ejecutar el test y confirmar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_combo_buffer.gd
```
Expected: `ALL TASK 3 CHECKS PASSED`.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/components/player_combat_controller.gd scripts/components/player_animation_controller.gd tests/test_combo_buffer.gd
git commit -m "feat(combat): implementar bufer de entrada y ventana de enlace de combo"
```

---

### Task 4: Esquiva básica con invulnerabilidad (Roll / Dodge)

**Files:**
- Modify: `scripts/components/player_input_controller.gd`
- Modify: `scripts/components/player_movement_controller.gd`
- Modify: `scripts/components/health_component.gd`
- Modify: `scripts/components/player_combat_controller.gd`
- Test: `tests/test_dodge.gd`

**Interfaces:**
- Consumes: Input `dodge` (Shift / botón gamepad), `player.roll_speed`
- Produces: `movement_controller.perform_dodge()`, `health_comp.is_invincible()`

- [ ] **Step 1: Escribir el test de esquiva e invulnerabilidad**

```gdscript
# tests/test_dodge.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 4: DODGE & I-FRAMES ---")
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	
	var mc = player.movement_controller
	assert(mc.has_method("perform_dodge"), "MovementController debe tener perform_dodge")
	
	mc.perform_dodge()
	assert(mc.is_dodging(), "Debe reportar estado de esquiva activo")
	assert(player.health_comp.is_invincible, "Durante la esquiva el jugador debe tener I-frames")
	
	player.queue_free()
	print("ALL TASK 4 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y confirmar que falla**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dodge.gd
```
Expected: FAIL porque `perform_dodge` no existe aún.

- [ ] **Step 3: Implementar esquiva e invulnerabilidad**

En `scripts/components/player_input_controller.gd`:
- Detectar tecla Shift (`KEY_SHIFT`) o botón correspondiente para emitir señal `dodge_pressed`.
En `scripts/components/player_movement_controller.gd`:
- Implementar `perform_dodge()`:
  - Cooldown de esquiva (ej. 0.6s).
  - Duración del dash de esquiva (0.35s) con velocidad `player.roll_speed` (18.0 m/s).
  - Dirección: vector de movimiento actual (`wish`) o frente del jugador si está quieto.
  - Llamar a `player.health_comp.set_invincibility(0.28)` para otorgar I-frames.
  - Reproducir `AudioManager.play("dodge")` o sonido equivalente.
  - Cancelar carga de lanza y recuperación de ataques 1 y 2.

- [ ] **Step 4: Ejecutar el test y confirmar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dodge.gd
```
Expected: `ALL TASK 4 CHECKS PASSED`.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/components/player_input_controller.gd scripts/components/player_movement_controller.gd scripts/components/health_component.gd scripts/components/player_combat_controller.gd tests/test_dodge.gd
git commit -m "feat(combat): implementar esquiva con i-frames y cancelacion de recuperacion"
```

---

### Task 5: Feedback diferenciado de acierto, fallo, daño recibido y pausa

**Files:**
- Modify: `scripts/core/hit_feedback.gd`
- Modify: `scripts/entities/player.gd`
- Test: `tests/test_hit_feedback.gd`

**Interfaces:**
- Consumes: Parámetro de arma explícito en `take_damage(amount, kb_dir, info)`
- Produces: `HitFeedback.play_whoosh(pos)`, `HitFeedback.on_player_damaged()`

- [ ] **Step 1: Escribir el test de hit feedback y restauración de pausa**

```gdscript
# tests/test_hit_feedback.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 5: HIT FEEDBACK DIFFERENTIATION ---")
	GameData.game_mode = "dungeon"
	var fb = HitFeedback.new()
	root.add_child(fb)
	
	# Verificar restauración de time_scale si pausa
	Engine.time_scale = 0.04
	fb.restore_time_scale()
	assert(Engine.time_scale == 1.0, "time_scale debe restaurarse a 1.0")
	
	fb.queue_free()
	print("ALL TASK 5 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y verificar resultado**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_hit_feedback.gd
```

- [ ] **Step 3: Implementar métodos en `hit_feedback.gd`**

- Añadir función para sonido de viento/fallo al inicio del golpe: `play_whoosh(pos: Vector3)`.
- Si la ventana activa concluye sin registrar ningún impacto (`hit_enemies.is_empty()`), no disparar hitstop ni shake de acierto.
- Añadir `on_player_damaged()`: viñeta roja breve en UI / shake de cámara corto y sfx característico.
- Añadir manejo de pausa: cuando se pausa el juego o `restore_time_scale()`, asegurar `Engine.time_scale = 1.0`.

- [ ] **Step 4: Ejecutar el test y verificar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_hit_feedback.gd
```
Expected: `ALL TASK 5 CHECKS PASSED`.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/core/hit_feedback.gd scripts/entities/player.gd tests/test_hit_feedback.gd
git commit -m "feat(combat): feedback diferenciado de acierto vs fallo y restauracion de time_scale"
```

---

### Task 6: DungeonEnemy — Enemigo goblin de mazmorra con telegrafía y combate completo

**Files:**
- Create: `scripts/entities/dungeon_enemy.gd`
- Create: `scenes/entities/dungeon_enemy.tscn`
- Test: `tests/test_dungeon_enemy.gd`

**Interfaces:**
- Consumes: Contrato `EnemyRegistry`: `global_position`, `take_damage(amount, kb_dir, info)`
- Produces: `DungeonEnemy` (`CharacterBody3D`), máquina de estados `IDLE`, `APPROACH`, `WINDUP`, `ATTACK`, `RECOVER`, `HURT`, `DEAD`

- [ ] **Step 1: Escribir el test para el ciclo de vida y estados de DungeonEnemy**

```gdscript
# tests/test_dungeon_enemy.gd
extends SceneTree

func _init() -> void:
	print("--- TEST TASK 6: DUNGEON ENEMY STATE MACHINE & CONTRACT ---")
	var enemy_scene = load("res://scenes/entities/dungeon_enemy.tscn")
	assert(enemy_scene != null, "La escena dungeon_enemy.tscn debe existir")
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	
	# Verificar registro en EnemyRegistry
	assert(EnemyRegistry.all().has(enemy), "DungeonEnemy debe registrarse en EnemyRegistry")
	
	# Verificar contrato de daño
	var initial_hp = enemy.hp
	enemy.take_damage(20.0, Vector3(0, 0, 1))
	assert(enemy.hp < initial_hp, "take_damage debe reducir la vida del enemigo")
	assert(enemy.state == enemy.State.HURT or enemy.state == enemy.State.APPROACH, "Debe reaccionar al daño")
	
	enemy.queue_free()
	print("ALL TASK 6 CHECKS PASSED")
	quit(0)
```

- [ ] **Step 2: Ejecutar el test y confirmar que falla**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dungeon_enemy.gd
```
Expected: FAIL porque la escena y el script no existen aún.

- [ ] **Step 3: Crear `scripts/entities/dungeon_enemy.gd` y `scenes/entities/dungeon_enemy.tscn`**

- Script `scripts/entities/dungeon_enemy.gd`:
  - `class_name DungeonEnemy extends CharacterBody3D`
  - Estados: `enum State { IDLE, APPROACH, WINDUP, ATTACK, RECOVER, HURT, DEAD }`
  - Propiedades: `hp = 60.0`, `max_hp = 60.0`, `attack_range = 2.2`, `detection_range = 14.0`, `windup_time = 0.5`, `attack_time = 0.15`, `recover_time = 0.45`
  - Telegrafía en `WINDUP`:
    - Indicador de impacto visual (mesh plano de advertencia en el suelo, color rojo semitransparente).
    - Destello en modelo y sonido de alerta (`AudioManager.play_at("impact_zap", ...)`).
    - Congelar orientación hacia el final de la telegrafía para permitir esquiva lateral.
  - Ataque en `ATTACK`:
    - Raycast de comprobación de paredes (capa 1) para no golpear a través de columnas/rocas.
    - Si el jugador está dentro del rango y ángulo de golpe, y no tiene I-frames, invocar `player.take_damage(15.0)`.
  - Reacción y muerte:
    - `HURT`: retroceso por `knockback_velocity`.
    - `DEAD`: emitir sonido de muerte, dar de baja en `EnemyRegistry`, desvanecer/liberar.
- Escena `scenes/entities/dungeon_enemy.tscn`:
  - `CharacterBody3D` (capa de colisión 4 = enemigos, mask = 1 suelo/paredes + 2 jugador).
  - `CollisionShape3D` (cápsula).
  - Modelo visual (reutiliza el mesh de goblin con material visible).
  - Indicador de telegrafía en el suelo (`Decal` o `MeshInstance3D` plano).

- [ ] **Step 4: Ejecutar el test y confirmar que pasa**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_dungeon_enemy.gd
```
Expected: `ALL TASK 6 CHECKS PASSED`.

- [ ] **Step 5: Commit del cambio**

```bash
git add scripts/entities/dungeon_enemy.gd scenes/entities/dungeon_enemy.tscn tests/test_dungeon_enemy.gd
git commit -m "feat(dungeon): implementar DungeonEnemy con estados, telegrafia y contrato EnemyRegistry"
```

---

### Task 7: Integración en la arena de mazmorra y suite de regresión

**Files:**
- Modify: `scripts/world/dungeon_map.gd`
- Modify: `scripts/core/game_start_facade.gd`
- Create: `tests/test_full_dungeon_combat_suite.gd`

**Interfaces:**
- Consumes: Todas las tareas previas 1-6
- Produces: Arena funcional en la primera caverna conectada al spawn con 1 goblin activo

- [ ] **Step 1: Escribir la suite de verificación completa de la experiencia de combate y regresión de supervivencia**

```gdscript
# tests/test_full_dungeon_combat_suite.gd
extends SceneTree

func _init() -> void:
	print("=== SUITE COMPLETA DE COMBATE DE MAZMORRA Y REGRESION ===")
	
	# 1. Verificar Mazmorra
	GameData.game_mode = "dungeon"
	var dungeon_scene = load("res://scenes/core/main_dungeon.tscn").instantiate()
	root.add_child(dungeon_scene)
	
	# Confirmar que la mazmorra genera salas y coloca el enemigo de prueba
	assert(dungeon_scene.has_node("DungeonMap"), "Debe tener DungeonMap")
	var enemies = EnemyRegistry.all()
	print("Enemigos registrados en la mazmorra: ", enemies.size())
	assert(enemies.size() >= 1, "Debe haber al menos 1 enemigo en la arena de mazmorra")
	dungeon_scene.queue_free()
	
	# 2. Regresión del modo supervivencia (R-S)
	GameData.game_mode = "survival"
	var surv_scene = load("res://scenes/core/main_procedural.tscn").instantiate()
	root.add_child(surv_scene)
	assert(Engine.time_scale == 1.0, "time_scale debe mantenerse en 1.0")
	surv_scene.queue_free()
	
	print("=== TODAS LAS PRUEBAS DE LA SUITE COMPLETADAS CON EXITO ===")
	quit(0)
```

- [ ] **Step 2: Ejecutar la suite y verificar que falla antes de la integración**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_full_dungeon_combat_suite.gd
```

- [ ] **Step 3: Conectar el spawn del goblin en la primera caverna de mazmorra**

En `scripts/world/dungeon_map.gd` o `main_dungeon.gd`:
- Al completar `generate()`, en la caverna vecina a la sala inicial (índice 1, tipo almacén con barriles), instanciar un `DungeonEnemy` en el centro de la sala.
- Asegurar que al pulsar la tecla `T` en mazmorra (o morir el goblin), se pueda reaparecer para pruebas.
- Asegurar que en supervivencia no se instancie ningún `DungeonEnemy`.

- [ ] **Step 4: Ejecutar la suite completa y confirmar que pasa al 100%**

Run:
```powershell
& "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless -s tests/test_full_dungeon_combat_suite.gd
```
Expected: `=== TODAS LAS PRUEBAS DE LA SUITE COMPLETADAS CON EXITO ===` con exit 0.

- [ ] **Step 5: Commit final de la fase**

```bash
git add scripts/world/dungeon_map.gd scripts/core/game_start_facade.gd tests/test_full_dungeon_combat_suite.gd
git commit -m "feat(dungeon): integracion de arena de combate con primer goblin y suite de pruebas"
```
