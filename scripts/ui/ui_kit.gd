class_name UiKit
extends RefCounted
## Shared UI builders for TACTERRA RPG screens.
## Dark theme, light text, touch-friendly minimum sizes. All screens build
## their widgets programmatically; the .tscn files only hold a root Control.

const BG := Color(0.05, 0.07, 0.11)
const PANEL := Color(0.10, 0.14, 0.20, 0.97)
const PANEL_BORDER := Color(0.26, 0.34, 0.46)
const BTN := Color(0.17, 0.24, 0.34)
const BTN_HOVER := Color(0.24, 0.32, 0.44)
const BTN_PRESS := Color(0.11, 0.16, 0.25)
const BTN_DISABLED := Color(0.09, 0.11, 0.15)
const ACCENT := Color(0.95, 0.71, 0.24)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.66, 0.72, 0.80)
const DANGER := Color(0.96, 0.42, 0.42)
const GOOD := Color(0.45, 0.86, 0.55)

const MIN_TOUCH := 48.0


static func _btn_box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = PANEL_BORDER
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_box(BTN))
	b.add_theme_stylebox_override("hover", _btn_box(BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_box(BTN_PRESS))
	b.add_theme_stylebox_override("disabled", _btn_box(BTN_DISABLED))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.53))
	b.add_theme_color_override("font_focus_color", TEXT)


static func make_button(text: String, min_h: float = 56.0, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b)
	return b


static func make_small_button(text: String) -> Button:
	return make_button(text, MIN_TOUCH, 17)


static func make_label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func make_title(text: String, font_size: int = 64) -> Label:
	var l := make_label(text, font_size, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = PANEL_BORDER
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 12.0
	s.content_margin_bottom = 12.0
	p.add_theme_stylebox_override("panel", s)
	return p


static func background(bg_color: Color = BG) -> ColorRect:
	var r := ColorRect.new()
	r.color = bg_color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func vbox(separation: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(min_size: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(min_size, min_size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## Floating transient message. Parent should be a CanvasLayer.
static func toast(layer: CanvasLayer, text: String, color: Color = TEXT) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = 80
	lbl.offset_left = 40
	lbl.offset_right = -40
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)
