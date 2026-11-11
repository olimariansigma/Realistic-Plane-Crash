class_name UiStyle
extends RefCounted
## Single source of truth for the touch UI look, so every widget matches.

const PANEL_BG := Color(0.07, 0.086, 0.11, 0.72)
const ACTIVE_BG := Color(0.2, 0.25, 0.32, 0.9)
const TEXT := Color(0.91, 0.93, 0.96)
const ACCENT := Color(1.0, 0.353, 0.212)
const OUTLINE := Color(0.91, 0.93, 0.96, 0.4)
const SKY := Color(0.25, 0.5, 0.82)
const GROUND := Color(0.42, 0.29, 0.18)
const OUTLINE_WIDTH: int = 2
const CORNER_RADIUS: int = 10
const FONT_SIZE: int = 22
const SMALL_FONT_SIZE: int = 16


## Builds a rounded translucent panel. Called at setup time only, never per frame.
static func panel_box(bg: Color = PANEL_BG, border: Color = OUTLINE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(OUTLINE_WIDTH)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.set_content_margin_all(10.0)
	box.anti_aliasing = true
	return box
