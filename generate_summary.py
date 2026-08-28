import json
import re

game_data_path = r'D:\GodotProjects\tesis\scripts\core\game_data.gd'
weapon_data_path = r'D:\GodotProjects\tesis\scripts\entities\player_weapons\weapon_data.gd'

output = []
output.append('=== RESUMEN DEL JUEGO RUNBANG ===\n')

output.append('--- MECÁNICAS PRINCIPALES ---')
output.append('- Progresión por Oleadas (WaveManager): Enemigos aparecen progresivamente en anillos alrededor del jugador. El tamaño de la oleada escala con el nivel. Cada 3 niveles se spawnea un Jefe.')
output.append('- Entorno Procedural (EnvironmentManager): El terreno usa operaciones CSG3D para generar colinas, montañas, rocas y árboles con posiciones aleatorias, calculando su colisión para que no floten.')
output.append('- Botín y Drops (LootManager): Al morir, los enemigos sueltan oro y orbes de experiencia (XP). Al empezar cada nivel o completar una oleada, aparecen armas o items coleccionables regados en el mapa.')
output.append('--- ATRIBUTOS DEL JUGADOR Y ESTADÍSTICAS ---')
output.append('Actualmente, el jugador se rige por el componente `StatsComponent` y `Player.gd`, que controlan:')
output.append('- Salud (HP y max_hp): La vida base. Si llega a 0, mueres.')
output.append('- Escudo (Shield y max_shield): Capa de vida extra. Se regenera automáticamente si pasas varios segundos sin recibir daño (shield_regen_delay).')
output.append('- Energía (Energy y max_energy): Recurso para usar armas a distancia y habilidades. Se regenera pasivamente con el tiempo (15 pts/segundo).')
output.append('- Velocidad de Movimiento (move_speed): Rapidez al correr por el mapa.')
output.append('- Velocidad de Esquive (roll_speed): Rapidez de la animación de rodar/dash.')
output.append('- Tiempo de Invulnerabilidad (i-frames): Tiempo breve de inmunidad tras recibir un golpe.')
output.append('- Nivel y Experiencia (level, experience): Aumentan al recolectar XP. La XP requerida escala un 1.5x por nivel.\n')

output.append('--- IDEAS PARA NUEVAS ESTADÍSTICAS (PARA MEJORAR EL ROL) ---')
output.append('Si quieres expandir el juego con objetos (Items) o un árbol de habilidades, podrías agregar:')
output.append('1. Probabilidad de Crítico (Crit Chance %): Porcentaje de que un ataque inflija daño extra.')
output.append('2. Multiplicador de Daño Crítico (Crit Damage): Por defecto 1.5x o 2.0x, aumentable con mejoras.')
output.append('3. Robo de Vida (Lifesteal %): Porcentaje del daño infligido a los enemigos que regresa como Salud.')
output.append('4. Suerte (Luck): Aumenta la rareza de los cofres y la cantidad de oro/orbes de XP que caen de los monstruos.')
output.append('5. Aceleración (Haste / Cooldown Reduction): Reduce el tiempo de recarga y el cooldown de todas las armas.')
output.append('6. Radio Magnético (Pickup Radius): Rango invisible que atrae el oro y la XP hacia el jugador sin tener que pisarlos directamente (estilo Vampire Survivors).')
output.append('7. Armadura / Mitigación de Daño (Armor): Reduce un % fijo de todo el daño que logre atravesar tu Escudo.')
output.append('8. Espinas (Thorns): Devuelve un porcentaje del daño cuerpo a cuerpo recibido al atacante.')
output.append('9. Cargas de Esquive (Dash Charges): Cuántas veces seguidas puedes rodar antes de tener que esperar un enfriamiento.\n')

output.append('--- PERSONAJES Y SUS PASIVAS ---')
with open(game_data_path, 'r', encoding='utf-8') as f:
    gd_content = f.read()

chars = re.findall(r'\{\s*"id":\s*"([^"]+)".*?"name":\s*"([^"]+)".*?"passive_name":\s*"([^"]+)".*?"passive_desc":\s*"([^"]+)"', gd_content, flags=re.DOTALL)
for c in chars:
    output.append(f'* {c[1]} ({c[0]}) - Pasiva: {c[2]}')
    output.append(f'  Descripción: {c[3]}\n')

output.append('\n--- TODAS LAS ARMAS (15) ---')
with open(weapon_data_path, 'r', encoding='utf-8') as f:
    wd_content = f.read()

weapons = re.findall(r'WeaponType\.([A-Z_]+):\s*WeaponData\.make\(\s*\d+,\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)",\s*(\d+),\s*([0-9\.]+),\s*([0-9\.]+),\s*([0-9\.]+),\s*([0-9\.]+),\s*(\d+),\s*([0-9\.]+)', wd_content, flags=re.DOTALL)

for w in weapons:
    output.append(f'* {w[1]} {w[2]} ({w[3].upper()})')
    output.append(f'  Daño: {w[5]} | Cooldown: {w[6]}s | Coste Energía: {w[4]} | Proyectil Vel: {w[8]} | Rango: {w[10]}m\n')

output.append('\n--- SISTEMA DE MEJORAS DE ARMAS (UPGRADES) ---')
output.append('1. Recolección de XP: Las orbes suben la barra de experiencia del jugador.')
output.append('2. Nivel Nuevo: El tiempo se pausa y aparece una interfaz (UpgradeChoiceUI) dando a elegir opciones aleatorias.')
output.append('3. Conseguir un ARMA NUEVA: Desbloquea un arma en un slot vacío.')
output.append('4. MEJORAR UN ARMA: Incrementa el nivel del arma (get_weapon_level) y le otorga Bonificadores Automáticos según su categoría (Melee, Ranged, Special):')
output.append('   - Nivel 2: +15% Daño Base.')
output.append('   - Nivel 3: Si es Melee/Especial -> +10% Tamaño de Ataque (Hitbox/Rango). Si es Ranged -> +1 Proyectil Extra (Multi-shot).')
output.append('   - Nivel 4: +15% Velocidad de Ataque (-15% Cooldown / Tiempo de Recarga).')
output.append('   - Nivel 5: +15% Daño Base (Total +30%).')
output.append('   - Nivel 6: Si es Ranged -> +1 Perforación (Las balas atraviesan un enemigo más). Si es Melee/Especial -> +1 Cantidad (Ej. más golpes o combos).')
output.append('   - Nivel 7: +15% Tamaño de Ataque Adicional.')
output.append('5. Rareza de Items: A lo largo del mapa y en cofres se pueden encontrar objetos (Común, Raro, Épico, Legendario) que otorgan buffs pasivos al personaje.\n')

with open(r'D:\GodotProjects\tesis\resumen_runbang.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(output))

print('File written!')
