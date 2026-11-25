extends SceneTree
## Generates every sound in the game: engine, airflow, tyre, scrape and fire
## loops and impact, tear, debris and gear one-shots, synthesised from noise,
## filters and envelopes (no recorded audio). Writes them as AudioStreamWAV
## resources to assets/sounds/, loops flagged as loops. Re-run after changing
## a recipe:  godot --headless --path . -s res://tools/gen_sounds.gd

const RATE := 22050
const OUT := "res://assets/sounds/"

var _seed: int = 1
var _total_samples: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_usec()
	var bank := {
		"fan_tone": _fan_tone(),
		"core_whine": _core_whine(),
		"jet_roar": _jet_roar(),
		"afterburner": _afterburner(),
		"wind_low": _wind(false),
		"wind_high": _wind(true),
		"buffet": _buffet(),
		"tyre_roll": _tyre_roll(),
		"scrape_metal": _scrape_metal(),
		"scrape_soil": _scrape_soil(),
		"fire_roar": _fire_roar(),
		"thud": _thud(),
		"clang_a": _clang(11),
		"clang_b": _clang(29),
		"crunch": _crunch(),
		"tear_long": _tear(1.3, 5),
		"tear_short": _tear(0.35, 9),
		"debris_panel": _debris_panel(),
		"debris_chunk": _debris_chunk(),
		"chirp": _chirp(),
		"strut_thump": _strut_thump(),
		"gear_clunk": _gear_clunk(),
		"explosion": _explosion(),
		"ab_whump": _ab_whump(),
		"creak": _creak(),
	}
	var us := Time.get_ticks_usec() - t0
	print("baked %d sounds, %.1f s of audio, %.0f ms (%.2f us/sample)" % [bank.size(), float(_total_samples) / RATE,
			us / 1000.0, float(us) / maxf(_total_samples, 1)])
	var t1 := Time.get_ticks_usec()
	var bytes_total := 0
	for key: String in bank:
		var x: PackedFloat32Array = bank[key]
		var loop := key in ["fan_tone", "core_whine", "jet_roar", "afterburner", "wind_low", "wind_high", "buffet",
				"tyre_roll", "scrape_metal", "scrape_soil", "fire_roar"]
		var wav := _to_wav(x, loop)
		bytes_total += wav.data.size()
		ResourceSaver.save(wav, OUT + key + ".res")
		var peak := 0.0
		var rms := 0.0
		for v: float in x:
			peak = maxf(peak, absf(v))
			rms += v * v
		rms = sqrt(rms / x.size())
		var seam := absf(x[x.size() - 1] - x[0]) if loop else 0.0
		print("  %-13s %5.2f s peak %.2f rms %.3f%s" % [key, float(x.size()) / RATE, peak, rms,
				("  seam step %.4f" % seam) if loop else ""])
	print("encode %.0f ms, %d KB PCM" % [(Time.get_ticks_usec() - t1) / 1000.0, bytes_total / 1024])
	quit(0)


# ------------------------------------------------------------ primitives

func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 1073741823.5 - 1.0


## One-pole low-pass coefficient for cutoff fc.
static func _k(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


func _buf(seconds: float) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	x.resize(int(seconds * RATE))
	_total_samples += x.size()
	return x


## Normalises to `peak` and, for loops, crossfades the last `fade` seconds
## into the start so the seam is continuous.
func _finish(x: PackedFloat32Array, peak: float, loop: bool, fade: float = 0.08) -> PackedFloat32Array:
	if loop:
		var n := int(fade * RATE)
		var len := x.size() - n
		var out := PackedFloat32Array()
		out.resize(len)
		for i: int in len:
			out[i] = x[i]
		for i: int in n:
			var w := float(i) / float(n)
			# Equal-power crossfade of the tail over the head.
			out[i] = x[len + i] * cos(w * PI * 0.5) + x[i] * sin(w * PI * 0.5)
		x = out
	var m := 0.0
	for v: float in x:
		m = maxf(m, absf(v))
	var g := peak / maxf(m, 1.0e-6)
	for i: int in x.size():
		x[i] *= g
	return x


## RBJ band-pass (constant 0 dB peak) state-variable form, in place.
func _bandpass(x: PackedFloat32Array, fc: float, q: float) -> void:
	var w := TAU * fc / RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i: int in x.size():
		var xi := x[i]
		var y := b0 * xi - b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = y
		x[i] = y


func _to_wav(x: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(x.size() * 2)
	for i: int in x.size():
		b.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = x.size()
	return w


# ------------------------------------------------------------ loops

## Fan blade-passing tone. 1 s loop, integer-Hz partials: seamless by
## construction. f_bpf = N1 * blades; pitch_scale = N1 at runtime.
func _fan_tone() -> PackedFloat32Array:
	var x := _buf(1.0)
	var f := [1150.0, 2300.0, 3450.0, 96.0, 192.0, 288.0, 384.0]  # BPF, 2xBPF, 3xBPF, buzzsaw shaft orders
	var a := [0.5, 0.22, 0.08, 0.05, 0.04, 0.035, 0.03]
	var lp := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var s := 0.0
		for k: int in f.size():
			s += a[k] * sin(TAU * f[k] * t + float(k))
		lp += (_noise() - lp) * _k(3000.0)
		# Blade-tone "wobble": the tone is modulated by inflow turbulence.
		x[i] = s * (1.0 + 0.25 * lp) + 0.04 * _noise()
	return _finish(x, 0.8, false)


func _core_whine() -> PackedFloat32Array:
	var x := _buf(1.0)
	for i: int in x.size():
		var t := float(i) / RATE
		x[i] = 0.5 * sin(TAU * 4100.0 * t) + 0.3 * sin(TAU * 5470.0 * t + 1.0) + 0.15 * sin(TAU * 6830.0 * t + 2.0)
	return _finish(x, 0.6, false)


## Jet mixing noise: band-limited 1/f-ish noise, peak near 250 Hz.
func _jet_roar() -> PackedFloat32Array:
	var x := _buf(2.08)
	var l1 := 0.0
	var l2 := 0.0
	var l3 := 0.0
	var k1 := _k(1100.0)
	var k2 := _k(70.0)
	var k3 := _k(3500.0)
	for i: int in x.size():
		var n := _noise()
		l1 += (n - l1) * k1
		l2 += (l1 - l2) * k2
		l3 += (n - l3) * k3
		x[i] = (l1 - l2) + 0.12 * (l3 - l1)
	return _finish(x, 0.85, true)


## Afterburner: low rumble plus Poisson "crackle" (skewed shock pops).
func _afterburner() -> PackedFloat32Array:
	var x := _buf(2.08)
	var l1 := 0.0
	var l2 := 0.0
	var pop := 0.0
	var hp := 0.0
	var k1 := _k(260.0)
	var k2 := _k(25.0)
	var rate := 320.0 / RATE
	for i: int in x.size():
		var n := _noise()
		l1 += (n - l1) * k1
		l2 += (l1 - l2) * k2
		if absf(_noise()) < rate:
			var u := absf(_noise())
			pop += u * u * u * 3.0  # heavy-tailed amplitudes
		pop *= 0.86
		var c := pop - hp
		hp += c * _k(250.0)
		x[i] = (l1 - l2) * 1.4 + c * 0.6
	return _finish(x, 0.9, true)


func _wind(bright: bool) -> PackedFloat32Array:
	var x := _buf(2.08)
	var l1 := 0.0
	var l2 := 0.0
	var am := 0.0
	var ka := _k(4000.0 if bright else 500.0)
	var kb := _k(900.0 if bright else 40.0)
	for i: int in x.size():
		var n := _noise()
		l1 += (n - l1) * ka
		l2 += (l1 - l2) * kb
		am += (_noise() - am) * _k(1.5)
		x[i] = (l1 - l2) * (1.0 + 2.5 * am)
	return _finish(x, 0.8, true)


## Stall / overspeed buffet: sub-bass rumble with 6-14 Hz irregular beating.
func _buffet() -> PackedFloat32Array:
	var x := _buf(2.08)
	var l := 0.0
	var am := 0.0
	for i: int in x.size():
		l += (_noise() - l) * _k(70.0)
		am += (_noise() - am) * _k(9.0)
		x[i] = l * maxf(am * 6.0, 0.0)
	return _finish(x, 0.9, true)


func _tyre_roll() -> PackedFloat32Array:
	var x := _buf(1.08)
	var l := 0.0
	var l2 := 0.0
	for i: int in x.size():
		var n := _noise()
		l += (n - l) * _k(240.0)
		l2 += (l - l2) * _k(30.0)
		x[i] = l - l2
	return _finish(x, 0.8, true)


## Metal on concrete: bright friction noise exciting a few resonant
## squeals, amplitude-modulated by stick-slip at 25-70 Hz.
func _scrape_metal() -> PackedFloat32Array:
	var x := _buf(2.08)
	var stick := 0.0
	var lpn := 0.0
	for i: int in x.size():
		stick += (_noise() - stick) * _k(45.0)
		lpn += (_noise() - lpn) * _k(6000.0)
		x[i] = lpn * (0.35 + maxf(stick * 4.0, 0.0))
	var dry := x.duplicate()
	var wet := PackedFloat32Array()
	wet.resize(x.size())
	for f: float in [1870.0, 3120.0, 4480.0, 760.0]:
		var r := dry.duplicate()
		_bandpass(r, f, 18.0)
		for i: int in wet.size():
			wet[i] += r[i]
	for i: int in x.size():
		x[i] = 0.45 * dry[i] + 2.2 * wet[i]
	return _finish(x, 0.85, true)


## Dirt and grass: low ploughing rumble plus gravel grains.
func _scrape_soil() -> PackedFloat32Array:
	var x := _buf(2.08)
	var l := 0.0
	var l2 := 0.0
	var grain := 0.0
	for i: int in x.size():
		var n := _noise()
		l += (n - l) * _k(320.0)
		l2 += (l - l2) * _k(35.0)
		if absf(_noise()) < 500.0 / RATE:
			grain += _noise() * 0.8
		grain *= 0.7
		x[i] = (l - l2) * 1.6 + grain
	return _finish(x, 0.85, true)


## Fuel fire: turbulent low roar with slow flicker, plus crackle.
func _fire_roar() -> PackedFloat32Array:
	var x := _buf(3.08)
	var l := 0.0
	var l2 := 0.0
	var flick := 0.0
	var crack := 0.0
	for i: int in x.size():
		var n := _noise()
		l += (n - l) * _k(420.0)
		l2 += (l - l2) * _k(30.0)
		flick += (_noise() - flick) * _k(3.0)
		if absf(_noise()) < 18.0 / RATE:
			crack = _noise()
		crack *= 0.93
		x[i] = (l - l2) * (1.0 + 3.0 * flick) + crack * 0.5
	return _finish(x, 0.85, true)


# ------------------------------------------------------------ one-shots

## Body of a heavy impact: a pitch-dropping sub thump plus a dull noise burst.
func _thud() -> PackedFloat32Array:
	var x := _buf(0.9)
	var ph := 0.0
	var l := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var f := 32.0 + 38.0 * exp(-t / 0.06)
		ph += TAU * f / RATE
		l += (_noise() - l) * _k(380.0)
		var env := (1.0 - exp(-t / 0.002)) * exp(-t / 0.22)
		x[i] = (sin(ph) * 0.8 + l * 2.0 * exp(-t / 0.07)) * env
	return _finish(x, 0.95, false)


## Struck aircraft structure: inharmonic modal partials (thin-shell ratios),
## high modes dying first.
func _clang(seed: int) -> PackedFloat32Array:
	_seed = seed
	var x := _buf(1.2)
	var base := 140.0 + absf(_noise()) * 80.0
	var ratios := [1.0, 1.59, 2.14, 2.3, 2.65, 2.92, 3.5, 4.15, 5.4]
	var amps := PackedFloat32Array()
	var decays := PackedFloat32Array()
	var freqs := PackedFloat32Array()
	for r: float in ratios:
		freqs.append(base * r * (1.0 + 0.03 * _noise()))
		amps.append((0.6 + 0.4 * absf(_noise())) / sqrt(r))
		decays.append(0.9 / pow(r, 0.9))
	for i: int in x.size():
		var t := float(i) / RATE
		var s := 0.0
		for k: int in freqs.size():
			s += amps[k] * exp(-t / decays[k]) * sin(TAU * freqs[k] * t)
		x[i] = s * (1.0 - exp(-t / 0.0007)) + _noise() * 0.5 * exp(-t / 0.012)
	return _finish(x, 0.9, false)


## Buckling: a rattle of short resonant clicks whose rate decays as the
## structure finishes folding.
func _crunch() -> PackedFloat32Array:
	var x := _buf(0.7)
	var click := 0.0
	var l := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var rate := 900.0 * exp(-t / 0.15)
		if absf(_noise()) < rate / RATE:
			click += _noise() * 1.5
		click *= 0.8
		l += (click - l) * _k(2600.0)
		x[i] = l
	_bandpass(x, 1400.0, 1.2)
	return _finish(x, 0.9, false)


## Sheet metal tearing: band-passed noise whose centre sweeps down as the
## crack runs, with rivets popping along it.
func _tear(seconds: float, seed: int) -> PackedFloat32Array:
	_seed = seed
	var x := _buf(seconds)
	var y1 := 0.0
	var y2 := 0.0
	var pop := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var u := t / seconds
		var fc := 3800.0 * pow(0.25, u)
		var w := TAU * fc / RATE
		var r := 0.985
		# Two-pole resonator at the sweeping centre.
		var n := _noise()
		var y := n * (1.0 - r) * 4.0 + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		var rate := 160.0 * (0.4 + u) * exp(-u * 2.0)
		if absf(_noise()) < rate / RATE:
			pop = 1.0
		pop *= 0.75
		var env := minf(t / 0.01, 1.0) * pow(1.0 - u, 1.5) * (0.6 + 0.4 * absf(sin(t * 37.0)))
		x[i] = y * env + pop * _noise() * 0.6
	return _finish(x, 0.85, false)


func _debris_panel() -> PackedFloat32Array:
	_seed = 77
	var x := _buf(0.3)
	var f := [620.0, 1130.0, 1790.0, 2610.0]
	for i: int in x.size():
		var t := float(i) / RATE
		var s := 0.0
		for k: int in f.size():
			s += exp(-t / (0.09 / (k + 1))) * sin(TAU * f[k] * t)
		x[i] = s + _noise() * exp(-t / 0.004)
	return _finish(x, 0.8, false)


func _debris_chunk() -> PackedFloat32Array:
	var x := _buf(0.35)
	var l := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		l += (_noise() - l) * _k(900.0)
		x[i] = (sin(TAU * 160.0 * t) * 0.7 + l * 1.5) * exp(-t / 0.05)
	return _finish(x, 0.8, false)


## Tyre spin-up: rubber dragged up to speed, a squeal that falls in pitch.
func _chirp() -> PackedFloat32Array:
	var x := _buf(0.3)
	var ph := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		ph += TAU * (1250.0 - 500.0 * t / 0.3) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t / 0.08)
		x[i] = (sin(ph) * 0.5 + _noise() * 0.5) * env
	_bandpass(x, 1300.0, 1.5)
	return _finish(x, 0.8, false)


func _strut_thump() -> PackedFloat32Array:
	var x := _buf(0.45)
	for i: int in x.size():
		var t := float(i) / RATE
		x[i] = sin(TAU * 68.0 * t) * exp(-t / 0.09) + sin(TAU * 151.0 * t) * 0.3 * exp(-t / 0.04)
	return _finish(x, 0.85, false)


func _gear_clunk() -> PackedFloat32Array:
	var x := _buf(0.3)
	for i: int in x.size():
		var t := float(i) / RATE
		x[i] = sin(TAU * 118.0 * t) * exp(-t / 0.05) + sin(TAU * 2200.0 * t) * 0.3 * exp(-t / 0.01) + _noise() * 0.3 * exp(-t / 0.006)
	return _finish(x, 0.7, false)


## Fuel-air explosion: sharp onset, long low tail falling off as ~1/t.
func _explosion() -> PackedFloat32Array:
	var x := _buf(2.5)
	var l := 0.0
	var l2 := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var fc := 120.0 + 2400.0 * exp(-t / 0.05)
		l += (_noise() - l) * _k(fc)
		l2 += (l - l2) * _k(18.0)
		var env := minf(t / 0.003, 1.0) / (1.0 + t / 0.08)
		x[i] = (l - l2) * env * (1.0 - t / 2.5)
	return _finish(x, 0.98, false)


func _ab_whump() -> PackedFloat32Array:
	var x := _buf(0.6)
	var l := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		l += (_noise() - l) * _k(160.0)
		x[i] = (l * 3.0 + sin(TAU * 45.0 * t) * 0.6) * minf(t / 0.03, 1.0) * exp(-t / 0.15)
	return _finish(x, 0.9, false)


## Overloaded structure: stick-slip groan, an irregular impulse train through
## a low resonance.
func _creak() -> PackedFloat32Array:
	var x := _buf(0.9)
	var phase := 0.0
	for i: int in x.size():
		var t := float(i) / RATE
		var f := 55.0 + 40.0 * sin(t * 4.0) + 8.0 * _noise()
		phase += f / RATE
		var imp := 0.0
		if phase >= 1.0:
			phase -= 1.0
			imp = 1.0
		x[i] = imp * sin(PI * t / 0.9)
	_bandpass(x, 420.0, 6.0)
	_bandpass(x, 420.0, 2.0)
	return _finish(x, 0.8, false)
