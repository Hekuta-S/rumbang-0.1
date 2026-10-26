# Plan: Joel el druida — animales espirituales + estados alterados

Reemplaza `SerpentsStrategy` (3 serpientes en cono) por un arma de **espíritus animales**. Se entrega por fases; cada fase termina con test y captura.

## 0. Estado actual (verificado)
- `SerpentsStrategy` (weapon_strategy.gd) dispara 3 `serpent_projectile`. `WeaponType.SERPENTS` en weapon_data.gd.
- **No existe sistema de estados**: `enemy.gd` solo tiene throttling visual de daño continuo (DOT_THRESHOLD). Las nubes/llamas hacen daño por tick directo.
- Blender MCP conectado (5.2 LTS) pero sin generadores de IA ni librerías (Tripo/Meshy/Sketchfab off) → **los modelos se construyen proceduralmente con bpy** (low-poly estilizado, ideal para espíritus). El addon avisa protocolo 13 vs 14: funciona por fallbacks.

## 1. Sistema de estados alterados (base, va primero)
Componente reutilizable `StatusEffectsComponent` (nodo hijo de Enemy y de Player).
- Efectos: **Veneno** (daño/s, acumula stacks, ignora armadura), **Sangrado** (daño/s alto que aumenta si el objetivo se mueve), **Quemadura** (daño/s fuerte, corta, se refresca sin acumular). Diseño abierto para añadir Lentitud/Aturdimiento.
- API: `apply(effect_id, dps, duration, source, stacks=1)`, `has(id)`, `clear(id)`; señal `effect_changed`.
- Los ticks llaman a `take_damage` con `is_dot` (reutiliza el throttling de números/flash ya hecho) y cuentan para `on_damage_dealt` (lifesteal).
- Visual barato: tinte/partículas por efecto (verde burbujas, rojo gotas, naranja chispas) con materiales compartidos (sin shaders pesados). Icono sobre la barra de vida del enemigo y en el HUD del player.
- En el Player: aplica a su `HealthComponent`; resistencias futuras vía `PlayerStatBlock`.
- Migración: llama/Flame/spore cloud/radiación pueden usar quemadura/veneno sin cambiar su balance.
- Test: stacks, duración, refresco, muerte por DoT, lifesteal, efecto en player.

## 2. Pipeline de modelos (Blender → Godot)
- Construcción procedural en bpy: malla low-poly, sin texturas; material base blanco-cian translúcido.
- **Look espiritual** (shader Godot, un solo shader compartido `spirit.gdshader`): fresnel de borde brillante, alfa bajo en el centro, ruido de scroll ligero, emisión cian/verde, `unshaded`, sin FBM pesado. Estela de partículas billboard baratas (reusa estilo `DustVFX`).
- Animaciones por **huesos/shape keys en Blender** exportadas en GLB (clips: `idle`, `attack`, `spawn`), o animación por tween en Godot si el rig no vale la pena (decidir al ver el primer modelo).
- Export: `assets/models/spirits/*.glb`; script de importación + test de carga.

## 3. Fases de animales (uno por fase, en este orden)
1. **Dragón de Komodo — melee, golpea con la cola.** Aparece junto al player, gira y azota en arco frontal (hitbox tipo `melee_hitbox`, knockback, aplica **Sangrado**). Anim: idle, latigazo de cola. *(Empezamos aquí.)*
2. **Búho — a distancia, ataque en picada.** Vuela hacia el enemigo más cercano en el cono, embiste y regresa; aplica **Veneno** (o sangrado leve). Anim: aleteo, picada.
3. **Hipopótamo — melee, devora enemigos.** Embiste y traga N enemigos según su tamaño: pequeños cuentan 1, medianos 2, grandes/elites 3 de capacidad (capacidad base 3, mejorable). Debuff de ejecución sobre lo que cabe; el resto recibe daño. Anim: abrir la boca/morder.
4. **Puercoespín — a distancia, lanza púas.** Ráfaga de púas (varias, en abanico) con timing independiente escalonado (patrón ya usado); púas aplican **Veneno**.

## 4. Integración como arma (cómo se elige el animal)
- Una sola arma **"Espíritus de Joel"** (reemplaza SERPENTS): cada ataque invoca un espíritu del conjunto desbloqueado, rotando entre ellos (cada uno con su propio cooldown/timing independiente). Alternativa a confirmar: un espíritu por nivel de arma.
- `AnimalSpiritStrategy` + escena base `spirit_animal.tscn` (malla, AnimationPlayer, hitbox, shader) y un recurso de datos por animal (rango, daño, efecto, cooldown).
- Mejoras por nivel en `WeaponUpgrades`: daño, tamaño/alcance, velocidad de ataque, duración/potencia del estado, cantidad de espíritus, y por animal una específica (p. ej. capacidad del hipopótamo, púas del puercoespín).
- Cartas en `UpgradeChoiceUI` y balance con las constantes globales de `WeaponData` (arma inicial floja, como las demás).

## 5. Verificación
- `test_status_effects`, `test_komodo`, y uno por animal (daño, estado aplicado, timing, mejoras).
- Capturas de cada espíritu y FPS (objetivo: sin caída vs. baseline; prewarm del shader/partículas en `GameStartFacade._prewarm_effects`).
- Regresión: test_balance, test_upgrade_cards, test_weapon_upgrades.

## 6. Preguntas abiertas
1. ¿Los animales se **desbloquean con niveles** (1.º komodo → …) o rotan todos desde el inicio?
2. ¿Qué estado por animal? Propuesta: Komodo = sangrado, Búho = veneno, Hipopótamo = ninguno (devora), Puercoespín = veneno/sangrado.
3. ¿Los estados también deben aplicarlos **enemigos al player** (p. ej. ciertos enemigos envenenan)? Dejo el componente listo; falta decidir qué enemigos.
4. ¿Mantenemos las serpientes como un quinto espíritu o se eliminan?

## Orden propuesto
Fase 1 (estados) → Fase 2 (pipeline + shader espiritual) → Komodo completo con test → Búho → Hipopótamo → Puercoespín → mejoras por nivel.
