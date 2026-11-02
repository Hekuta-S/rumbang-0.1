@tool
extends EditorExportPlugin

## Solo en la exportación Web. Las texturas importadas con compresión VRAM llevan DOS copias en el paquete
## (S3TC para PC y ETC2 para móvil). Aquí cada una se guarda UNA vez como PortableCompressedTexture2D en
## Basis Universal, que el navegador convierte al formato de su GPU al cargarla; además las de más de
## MAX_SIZE px se reducen a MAX_SIZE (en un móvil no se nota y ahorra descarga y memoria).
## PC y Android no cambian: sus exportaciones no pasan por aquí.

const MAX_SIZE := 1024
const VERSION := 3                    ## súbelo si cambias la conversión (invalida la caché de exportación)

var _active := false
var _count := 0

func _get_name() -> String:
	return "WebTextureLimit"

func _begin_customize_resources(platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	_active = platform.get_os_name() == "Web"
	_count = 0
	return _active

func _get_customization_configuration_hash() -> int:
	return hash("web_texture_limit_%d_%d" % [MAX_SIZE, VERSION])

func _customize_resource(resource: Resource, path: String) -> Resource:
	if not _active or not (resource is CompressedTexture2D) or path == "":
		return null
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK or int(cfg.get_value("params", "compress/mode", 0)) != 2:
		return null   # solo las de compresión VRAM (las de UI sin pérdida se quedan igual)
	var img := (resource as CompressedTexture2D).get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var had_mipmaps := img.has_mipmaps()
	if had_mipmaps:
		img.clear_mipmaps()
	var side := maxi(img.get_width(), img.get_height())
	if side > MAX_SIZE:
		var k := float(MAX_SIZE) / float(side)
		img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_LANCZOS)
	if had_mipmaps:
		img.generate_mipmaps()
	var out := PortableCompressedTexture2D.new()
	out.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL,
		int(cfg.get_value("params", "compress/normal_map", 0)) == 1)
	_count += 1
	return out

func _end_customize_resources() -> void:
	if _active:
		print("[WebTextureLimit] texturas convertidas: %d" % _count)
