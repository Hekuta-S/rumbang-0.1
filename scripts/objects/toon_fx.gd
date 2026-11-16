class_name ToonFX
extends RefCounted

## Nubes de polvo y humo DIBUJADAS (cómic) para las partículas: una textura con 4 nubes entintadas
## (res://assets/textures/toon/fx/puff.png, de tools/make_toon_fx.py) en lugar de la mancha difuminada.
## Uso: ToonFX.puff_material(mat) en el material (billboard de partículas, mezcla alfa) y ToonFX.vary(p) en
## el emisor, para que cada partícula salga con una de las cuatro nubes.

const PUFF_PATH := "res://assets/textures/toon/fx/puff.png"
const FRAMES := 2                 ## rejilla 2×2

static var _puff: Texture2D
static var _checked := false

## La textura de nubes, o null si no está (se queda la mancha suave de siempre).
static func puff_texture() -> Texture2D:
	if not _checked:
		_checked = true
		_puff = load(PUFF_PATH) if ResourceLoader.exists(PUFF_PATH) else null
	return _puff

## Pone las nubes dibujadas en un material de partículas. Devuelve si lo hizo.
static func puff_material(mat: BaseMaterial3D) -> bool:
	var tex := puff_texture()
	if tex == null:
		return false
	mat.albedo_texture = tex
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX      # la tinta no existe en mezcla aditiva
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = FRAMES
	mat.particles_anim_v_frames = FRAMES
	mat.particles_anim_loop = false
	return true

## Cada partícula del emisor usa una de las cuatro nubes (sin animar).
static func vary(p: CPUParticles3D) -> void:
	p.anim_speed_min = 0.0
	p.anim_speed_max = 0.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
