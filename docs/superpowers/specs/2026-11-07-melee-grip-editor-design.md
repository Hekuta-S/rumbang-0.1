# Especificación de Diseño: Editor Unificado de Agarre Cuerpo a Cuerpo (`melee_grip_editor`) con Pose Estática

## 1. Contexto y Objetivos

Actualmente existe la herramienta `tools/greatsword_grip_editor.tscn` / `.gd`, que internamente ya contiene la lógica de datos para espadones, dagas y mazas, pero presenta dos problemas para el flujo de trabajo:
1. **Confusión en nombres**: El archivo se denomina `greatsword_grip_editor`, dando la impresión de ser exclusivo para espadones.
2. **Movimiento molesto del personaje en reposo**: La animación *idle* se mantiene en reproducción continua, balanceando el torso, cabeza y brazos del modelo, lo cual dificulta ajustar con precisión milimétrica la posición y rotación del agarre del arma.

### Objetivos
- Unificar formalmente la herramienta bajo el nombre **`tools/melee_grip_editor.tscn`** y **`tools/melee_grip_editor.gd`**, manteniendo `tools/greatsword_grip_editor.tscn` como alias para no romper accesos existentes.
- **Congelar de forma absoluta el modelo del jugador exclusivamente en el modo edición**: el personaje debe permanecer completamente quieto (como una estatua) en la postura base del arma seleccionada. El juego normal (mazmorra, supervivencia, multijugador) no sufrirá ninguna modificación en sus animaciones.
- Proveer soporte completo e intuitivo para las tres familias de armas cuerpo a cuerpo (Espadones, Dagas Gemelas con mano derecha/izquierda y Mazas), con comodidades como copiar ajustes entre manos en las dagas.

---

## 2. Congelado de Pose (Solo Modo Edición)

### 2.1. Causa del movimiento actual
En `greatsword_grip_editor.gd`, al iniciar solo se desactivaba el input del jugador (`input_controller`), pero `_player.animation_controller`, su `anim_tree` y el nodo `anim_player` continuaban ejecutando su ciclo de actualización cada fotograma.

### 2.2. Mecanismo de congelado en el editor
En `tools/melee_grip_editor.gd`, se implementará una rutina de congelamiento estricta:
```gdscript
func _freeze_player_pose(frozen: bool) -> void:
    if not is_instance_valid(_player):
        return
    # Detener controladores físicos para eliminar cualquier deriva
    if _player.movement_controller:
        _player.movement_controller.set_physics_process(false)
    if _player.combat_controller:
        _player.combat_controller.set_physics_process(false)
        _player.combat_controller.set_process(false)
    
    var anim_ctrl = _player.animation_controller
    if anim_ctrl:
        anim_ctrl.set_process(!frozen)
        anim_ctrl.set_physics_process(!frozen)
        if is_instance_valid(anim_ctrl.anim_tree):
            anim_ctrl.anim_tree.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
            anim_ctrl.anim_tree.active = !frozen
        if is_instance_valid(anim_ctrl.anim_player):
            if frozen:
                anim_ctrl.anim_player.pause()
            else:
                anim_ctrl.anim_player.play()
```

### 2.3. Transición al cambiar de arma o modelo
Cuando el usuario selecciona otra arma en el desplegable (ej. de Espadones a Dagas o Mazas):
1. Se reactiva temporalmente el controlador de animación por 1-2 fotogramas para que `set_held_weapon()` aplique la nueva postura en el esqueleto (guardia baja para dagas, maza al hombro para mazas, reposo para espadón).
2. Se vuelve a congelar la pose de inmediato.
3. El usuario cuenta en la UI con una casilla de verificación **`[x] Congelar pose`** (o tecla rápida `Espacio`) por si desea reanudar la animación para previsualizar movimiento y volver a congelarla a voluntad. Por defecto arrancará siempre **congelado**.

---

## 3. Arquitectura del Editor Unificado

### 3.1. Archivos
- **`tools/melee_grip_editor.gd`**: Script principal del editor con la lógica de UI, cámara orbital, selección de arma/modelo/mano, congelado de pose y persistencia JSON.
- **`tools/melee_grip_editor.tscn`**: Escena ejecutable con F6 en Godot vinculada a `melee_grip_editor.gd`.
- **`tools/greatsword_grip_editor.tscn`**: Escena wrapper que referencia o instancia `melee_grip_editor.tscn` para compatibilidad retroactiva.

### 3.2. Categorías de Armas y Datos
1. **Espadones (`CAT_GS = 0`)**:
   - Modelos: Gótico, Gran Ola, Matadragones, Obsidiana.
   - Anclaje: Mano derecha (`mixamorig_RightHand`).
   - Archivo destino: `resources/greatsword_grip.json`.
2. **Dagas (`CAT_DAGGER = 1`)**:
   - Modelos: China, Camuflaje, Acero, Rúnica.
   - Anclaje dual: Mano derecha (`mixamorig_RightHand`) y Mano izquierda (`mixamorig_LeftHand`).
   - Selector de mano: `Derecha` / `Izquierda`.
   - Botón: `"Copiar a la otra mano"`.
   - Archivo destino: `resources/dagger_grip.json` (claves `<id>_right` y `<id>_left`).
3. **Mazas (`CAT_MACE = 2`)**:
   - Modelos: Hueso, Mekka, Hierro, Calavera, Negro.
   - Anclaje: Mano derecha (`mixamorig_RightHand`).
   - Archivo destino: `resources/mace_grip.json`.

---

## 4. Interfaz de Usuario (UI)

Panel acoplado en esquina superior izquierda con:
1. **Título**: `"Rumbang · Ajuste de Agarre Cuerpo a Cuerpo"`.
2. **Control de Pose**: Casilla `[x] Congelar pose (Espacio)` (activa por defecto).
3. **Fila Arma**: OptionButton con `Espadones`, `Dagas`, `Mazas`.
4. **Fila Mano (solo Dagas)**:
   - OptionButton `Derecha` / `Izquierda`.
   - Botón `Copiar a la otra mano`.
5. **Fila Modelo**: OptionButton con los nombres de las apariencias disponibles.
6. **Posición (metros)**: 3 SpinBoxes (X, Y, Z) con rango [-1.0, 1.0], paso 0.005 m (5 mm).
7. **Rotación (grados)**: 3 SpinBoxes (X, Y, Z) con rango [-180.0, 180.0], paso 1.0°.
8. **Acciones**:
   - `Restablecer`: vuelve a los valores por defecto del agarre.
   - `Guardar`: persiste en disco (Ctrl+S).
   - `Recargar`: descarta cambios sin guardar y relee los JSONs.
   - `Cerrar`: sale del editor.
9. **Cámara orbital**: Arrastrar con ratón para orbitar, rueda para zoom, botón central para recentrar el objetivo de la cámara sobre la mano activa.

---

## 5. Garantías de Aislamiento y No Regresión

- **Cero impacto en gameplay**: Las funciones de congelamiento se ejecutan únicamente dentro del ciclo de vida de `melee_grip_editor.gd`. En una partida normal de mazmorra o supervivencia, el jugador conserva intactas sus animaciones, mezclas de locomoción e IK.
- **Robustez de inventario**: Al alternar entre armas en el editor, si el inventario estuviera lleno, el script del editor sustituye el slot 0 de forma segura para garantizar que el modelo visual se equipe y renderice sin errores.
- **Preservación de configuraciones previas**: Las modificaciones existentes en `greatsword_grip.json` se preservan intactas.

---

## 6. Plan de Verificación

1. **Prueba de estática**: Iniciar la escena con F6 y comprobar que el modelo del personaje permanece completamente inmóvil.
2. **Prueba de categorías**:
   - Seleccionar `Espadones`: verificar que se muestra el espadón y se cargan sus modelos.
   - Seleccionar `Dagas`: verificar que aparece la fila de selección de mano, se muestran ambas dagas y la cámara apunta a la mano activa. Probar el botón de copiar a la otra mano.
   - Seleccionar `Mazas`: verificar que se muestra la maza al hombro y sus modelos correspondientes.
3. **Prueba de persistencia**: Modificar valores, pulsar Guardar, verificar la escritura correcta en los 3 JSONs y comprobar que `PlayerWeaponVisuals` los recarga.
4. **Prueba de no regresión en partida**: Ejecutar el juego normal para comprobar que el movimiento e idle del personaje no fueron alterados.
