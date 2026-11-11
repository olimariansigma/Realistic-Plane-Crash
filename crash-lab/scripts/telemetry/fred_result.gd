class_name FredResult
extends RefCounted
## One FRED dummy's recorded loads. Plain data.

var seat_label: String = ""
var limb_names: PackedStringArray     ## 9 entries
var limb_peak_g: PackedFloat32Array   ## same length
var hic: float = 0.0
var belt_peak_kn: float = 0.0
var stroke_m: float = 0.0
var bottomed: bool = false
var ejected: bool = false
var survival: float = 1.0
