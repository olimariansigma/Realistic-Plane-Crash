extends SceneTree
## Paints the shared 1024x1024 texture atlas (assets/atlas.png). Every airframe,
## cabin and dummy mesh samples this one texture through one material; vertex
## colour supplies the paint, the atlas supplies windows, panel lines and
## surface detail. The import settings store it VRAM-compressed (ASTC on
## Android) with mipmaps.
##
## Run: godot --headless --path . -s res://tools/gen_atlas.gd
##
## Layout (pixels):
##   y   0..127  fuselage strip with cabin windows  (24 m long, crown -> belly)
##   y 128..255  fuselage strip, plain panels
##   then 256 px tiles, (column, row):
##   (0,1) nose + windscreen  (1,1) wing skin   (2,1) engine cowl  (3,1) fan face
##   (0,2) tyre               (1,2) bare metal  (2,2) seat fabric  (3,2) cabin floor
##   (0,3) dummy markings     (1,3) bulkhead    (2,3) primer       (3,3) plain

const SIZE := 1024
const GLASS := Color(0.07, 0.09, 0.12)
const LINE := Color(0.72, 0.73, 0.75)

var _img: Image
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 7
	_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	_img.fill(Color.WHITE)
	_fuselage_strip(0, true)
	_fuselage_strip(128, false)
	_nose(_tile(0, 1))
	_wing(_tile(1, 1))
	_cowl(_tile(2, 1))
	_fan(_tile(3, 1))
	_tyre(_tile(0, 2))
	_metal(_tile(1, 2))
	_fabric(_tile(2, 2), Color(0.86, 0.88, 0.92), Color(0.74, 0.77, 0.83))
	_fabric(_tile(3, 2), Color(0.8, 0.82, 0.86), Color(0.68, 0.7, 0.76))
	_dummy(_tile(0, 3))
	_bulkhead(_tile(1, 3))
	_noise(_tile(2, 3), 0.06)
	DirAccess.make_dir_recursive_absolute("res://assets")
	var err := _img.save_png("res://assets/atlas.png")
	print("ATLAS PASS" if err == OK else "ATLAS FAIL")
	quit(0 if err == OK else 1)


func _tile(col: int, row: int) -> Rect2i:
	return Rect2i(col * 256, row * 256, 256, 256)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	_img.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, SIZE, SIZE)), c)


func _noise(r: Rect2i, amount: float) -> void:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var c := _img.get_pixel(x, y)
			var n := 1.0 - amount * _rng.randf()
			_img.set_pixel(x, y, Color(c.r * n, c.g * n, c.b * n))


func _fuselage_strip(y0: int, windows: bool) -> void:
	# 1024 px = 24 m. Skin joints every 1.2 m, stringer lines, grime on the belly.
	for i: int in 20:
		_rect(int(float(i) * 51.2), y0, 1, 128, LINE)
	for v: int in [18, 44, 86, 108]:
		_rect(0, y0 + v, SIZE, 1, LINE.lightened(0.3))
	for y: int in range(y0 + 96, y0 + 128):
		var shade := 1.0 - 0.22 * float(y - y0 - 96) / 32.0
		for x: int in SIZE:
			var c := _img.get_pixel(x, y)
			_img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	if windows:
		# 45 windows: 0.53 m pitch, a little above the fuselage centreline.
		for i: int in 45:
			var x := 6 + int(float(i) * 22.75)
			_rect(x, y0 + 53, 9, 13, Color(0.6, 0.62, 0.66))
			_rect(x + 1, y0 + 54, 7, 11, GLASS)
			_rect(x + 1, y0 + 54, 1, 1, Color(0.6, 0.62, 0.66))
			_rect(x + 7, y0 + 54, 1, 1, Color(0.6, 0.62, 0.66))
			_rect(x + 1, y0 + 64, 1, 1, Color(0.6, 0.62, 0.66))
			_rect(x + 7, y0 + 64, 1, 1, Color(0.6, 0.62, 0.66))
		# One door outline per strip.
		for edge: int in [40, 78]:
			_rect(edge, y0 + 40, 1, 52, LINE.darkened(0.2))
		_rect(40, y0 + 40, 39, 1, LINE.darkened(0.2))
		_rect(40, y0 + 92, 39, 1, LINE.darkened(0.2))
		_rect(54, y0 + 52, 9, 13, GLASS)
	_noise(Rect2i(0, y0, SIZE, 128), 0.035)


func _nose(r: Rect2i) -> void:
	# u = along the nose cap (tip at left), v = crown (top) to belly.
	var x0 := r.position.x
	var y0 := r.position.y
	for v: int in [60, 150, 210]:
		_rect(x0, y0 + v, 256, 1, LINE.lightened(0.3))
	_rect(x0 + 44, y0, 1, 256, LINE)
	_rect(x0 + 200, y0, 1, 256, LINE)
	# Windscreen: a band wrapping the crown, split into panes.
	_rect(x0 + 122, y0, 76, 92, Color(0.55, 0.57, 0.6))
	_rect(x0 + 126, y0, 68, 88, GLASS)
	for pane: int in [36, 66]:
		_rect(x0 + 122, y0 + pane, 76, 3, Color(0.55, 0.57, 0.6))
	_rect(x0 + 160, y0 + 36, 3, 56, Color(0.55, 0.57, 0.6))
	_noise(r, 0.035)


func _wing(r: Rect2i) -> void:
	# u = chord (leading edge at left), v = span.
	var x0 := r.position.x
	var y0 := r.position.y
	_rect(x0, y0, 14, 256, Color(0.86, 0.87, 0.9))
	for u: int in [14, 46, 96, 174]:
		_rect(x0 + u, y0, 1, 256, LINE)
	for v: int in range(0, 256, 32):
		_rect(x0, y0 + v, 256, 1, LINE.lightened(0.25))
	# Spoiler panels ahead of the flap hinge line.
	for v: int in range(8, 248, 64):
		_rect(x0 + 142, y0 + v, 30, 1, LINE.darkened(0.15))
		_rect(x0 + 142, y0 + v + 48, 30, 1, LINE.darkened(0.15))
		_rect(x0 + 142, y0 + v, 1, 48, LINE.darkened(0.15))
	_noise(r, 0.04)


func _cowl(r: Rect2i) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	_rect(x0, y0, 22, 256, Color(0.8, 0.82, 0.86))
	for u: int in [22, 96, 180]:
		_rect(x0 + u, y0, 1, 256, LINE)
	for v: int in [64, 128, 192]:
		_rect(x0 + 22, y0 + v, 234, 1, LINE.lightened(0.2))
	_rect(x0 + 180, y0, 76, 256, Color(0.62, 0.63, 0.66))
	_noise(r, 0.05)


func _fan(r: Rect2i) -> void:
	# Radial fan face: dark disc, lighter blades, spinner with a spiral mark.
	var c := Vector2(r.position) + Vector2(128.0, 128.0)
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var d := Vector2(float(x), float(y)) - c
			var radius := d.length() / 124.0
			var angle := atan2(d.y, d.x)
			var col := Color(0.05, 0.05, 0.06)
			if radius < 1.0:
				var blade := 0.5 + 0.5 * sin(angle * 22.0 + radius * 5.0)
				col = Color(0.1, 0.1, 0.11).lerp(Color(0.34, 0.35, 0.38), blade * blade)
			if radius < 0.3:
				col = Color(0.5, 0.52, 0.55)
				if absf(wrapf(angle - radius * 16.0, -PI, PI)) < 0.35:
					col = Color(0.92, 0.92, 0.92)
			_img.set_pixel(x, y, col)


func _tyre(r: Rect2i) -> void:
	_img.fill_rect(r, Color(0.3, 0.3, 0.32))
	for u: int in range(0, 256, 36):
		_rect(r.position.x + u, r.position.y, 5, 256, Color(0.16, 0.16, 0.17))
	_noise(r, 0.12)


func _metal(r: Rect2i) -> void:
	_img.fill_rect(r, Color(0.92, 0.93, 0.95))
	for v: int in range(0, 256, 3):
		_rect(r.position.x, r.position.y + v, 256, 1, Color(0.84, 0.85, 0.88))
	_noise(r, 0.05)


func _fabric(r: Rect2i, a: Color, b: Color) -> void:
	_img.fill_rect(r, a)
	for v: int in range(0, 256, 8):
		for u: int in range(0, 256, 8):
			if ((u + v) / 8) % 2 == 0:
				_rect(r.position.x + u, r.position.y + v, 8, 8, b)
	_noise(r, 0.08)


func _dummy(r: Rect2i) -> void:
	# Calibration quadrants and bands, as on a real test dummy.
	_img.fill_rect(r, Color.WHITE)
	_rect(r.position.x, r.position.y + 100, 256, 18, Color(0.08, 0.08, 0.08))
	_rect(r.position.x + 96, r.position.y + 150, 64, 64, Color(0.08, 0.08, 0.08))
	_rect(r.position.x + 96, r.position.y + 150, 32, 32, Color.WHITE)
	_rect(r.position.x + 128, r.position.y + 182, 32, 32, Color.WHITE)
	_noise(r, 0.04)


func _bulkhead(r: Rect2i) -> void:
	_img.fill_rect(r, Color(0.7, 0.72, 0.74))
	for u: int in range(0, 256, 32):
		_rect(r.position.x + u, r.position.y, 2, 256, Color(0.5, 0.52, 0.54))
		_rect(r.position.x, r.position.y + u, 256, 2, Color(0.5, 0.52, 0.54))
	_noise(r, 0.06)
