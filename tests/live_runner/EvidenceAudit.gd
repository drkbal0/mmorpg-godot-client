extends RefCounted
## EvidenceAudit.gd — Auditoría de capturas del LivePlayerRunner (sin autoloads).
## Reglas: 1280x720, > 50 KB y luminancia media > 0.08 (descarta frames negros).

const TARGET_SIZE := Vector2i(1280, 720)
const MIN_PNG_BYTES := 50 * 1024
const MIN_MEAN_LUMA := 0.08


## Luminancia relativa media (Rec. 709 sobre valores sRGB en [0,1]) muestreando
## una rejilla de 1 de cada 4x4 píxeles (57.600 muestras en 1280x720).
static func mean_luma(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var acc := 0.0
	var n := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return acc / maxf(1.0, float(n))


## Auditoría de una imagen en disco.
static func audit_png(path: String) -> Dictionary:
	var res := {"pass": false, "width": 0, "height": 0, "bytes": 0, "mean_luma": 0.0}
	if not FileAccess.file_exists(path):
		return res
	var f := FileAccess.open(path, FileAccess.READ)
	res["bytes"] = f.get_length()
	f.close()
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return res
	res["width"] = img.get_width()
	res["height"] = img.get_height()
	res["mean_luma"] = mean_luma(img)
	res["pass"] = (img.get_size() == TARGET_SIZE and int(res["bytes"]) > MIN_PNG_BYTES
		and float(res["mean_luma"]) > MIN_MEAN_LUMA)
	return res
