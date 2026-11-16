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


## Minimum distance (canvas units) kept clear on every screen edge.
const SAFE_MIN: float = 24.0


## Inset of the display's safe area (notch, rounded corners, gesture bars) as
## Largest share of a display edge a cutout margin may take.
const SAFE_MAX_FRACTION := 0.07

## (left, top, right, bottom) in canvas units, never below SAFE_MIN. The OS
## reports the safe area in physical pixels, so it is divided by the canvas
## scale (window px per canvas unit). Falls back to SAFE_MIN when the safe area
## is unavailable, covers the whole screen, or the window is not full screen.
static func safe_margins(control: Control) -> Vector4:
	var result := Vector4(SAFE_MIN, SAFE_MIN, SAFE_MIN, SAFE_MIN)
	if control == null or not control.is_inside_tree():
		return result
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var window: Window = control.get_window()
	var screen: int = window.current_screen
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	if safe.size.x <= 0 or safe.size.y <= 0 or screen_size.x <= 0 or screen_size.y <= 0:
		return result
	# A desktop window smaller than its screen has no cutout of its own.
	var win_size: Vector2i = window.size
	if win_size.x < screen_size.x - 2 or win_size.y < screen_size.y - 2:
		return result
	var scale: Vector2 = control.get_viewport().get_final_transform().get_scale()
	if scale.x <= 0.0 or scale.y <= 0.0:
		return result
	var left: float = float(safe.position.x - screen_pos.x)
	var top: float = float(safe.position.y - screen_pos.y)
	var right: float = float(screen_pos.x + screen_size.x - safe.end.x)
	var bottom: float = float(screen_pos.y + screen_size.y - safe.end.y)
	# Some devices report the safe area for the wrong orientation while the
	# display is rotating; a margin that large would push the controls off the
	# screen, so no margin may exceed a real cutout's share of the display.
	var cap_x: float = float(screen_size.x) * SAFE_MAX_FRACTION
	var cap_y: float = float(screen_size.y) * SAFE_MAX_FRACTION
	result.x = maxf(SAFE_MIN, clampf(left, 0.0, cap_x) / scale.x)
	result.y = maxf(SAFE_MIN, clampf(top, 0.0, cap_y) / scale.y)
	result.z = maxf(SAFE_MIN, clampf(right, 0.0, cap_x) / scale.x)
	result.w = maxf(SAFE_MIN, clampf(bottom, 0.0, cap_y) / scale.y)
	return result



## Gives a Button the translucent panel look used by the touch widgets.
static func style_button(button: Button, accent: Color = Color(0, 0, 0, 0)) -> void:
	var tinted: bool = accent.a > 0.0
	var normal: StyleBoxFlat = panel_box(accent.darkened(0.15) if tinted else PANEL_BG, OUTLINE)
	var hover: StyleBoxFlat = panel_box(accent if tinted else ACTIVE_BG, TEXT)
	var pressed: StyleBoxFlat = panel_box(ACTIVE_BG if not tinted else accent.darkened(0.35), ACCENT)
	var disabled: StyleBoxFlat = panel_box(Color(PANEL_BG, 0.4), Color(OUTLINE, 0.2))
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", disabled)
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.add_theme_color_override(&"font_color", TEXT)
	button.add_theme_color_override(&"font_hover_color", TEXT)
	button.add_theme_color_override(&"font_pressed_color", TEXT)
