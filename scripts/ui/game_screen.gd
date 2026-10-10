extends Control
## TACTERRA RPG — main game screen: world map, HUD, orders, dialogs.
##
## SCENE HANDOFF (no autoloads in this project): the previous screen sets
## exactly ONE of these static vars before calling
## change_scene_to_file("res://scripts/ui/game_screen.tscn"):
##   GameScreen.pending_settings : Dictionary -> GameState.create(settings)
##   GameScreen.pending_state    : GameState  -> continue a saved match
## game_screen consumes (and clears) the payload in _ready(), so a second
## visit never reuses a stale payload.
##
## GameState / SaveSystem are resolved with ResourceLoader at runtime
## (late binding) because the core module is built in parallel; only the
## documented ARCHITECTURE.md API is used.

const GS_PATH := "res://scripts/core/game_state.gd"
const SS_PATH := "res://scripts/core/save_system.gd"
const HowToPlay := preload("res://scripts/ui/how_to_play.gd")

static var pending_settings: Dictionary = {}
static var pending_state = null # GameState (late-bound)

static var _GameState: GDScript = null
static var _SaveSystem: GDScript = null

const TERRAIN_TINTS := {
	0: Color(0.35, 0.55, 0.30, 0.22), # PLAINS
	1: Color(0.45, 0.72, 0.25, 0.26), # FERTILE
	2: Color(0.13, 0.42, 0.22, 0.34), # FOREST
	3: Color(0.55, 0.47, 0.33, 0.28), # HILLS
	4: Color(0.58, 0.58, 0.62, 0.32), # MOUNTAINS
	5: Color(0.82, 0.68, 0.38, 0.28), # DESERT
}

var state = null # GameState

# --- map nodes ---
var _map_root: Node2D
var _camera: Camera2D
var _transit_layer: Node2D
var _frontier_layer: Node2D
var _fill := {} # tid -> Polygon2D
var _border := {} # tid -> Line2D
var _selection_line := {} # tid -> Line2D
var _army_marker := {} # tid -> Node2D
var _army_circle := {} # tid -> Polygon2D
var _army_label := {} # tid -> Label
var _last_owner := {} # tid -> int (for capture flash)
var _flash := {} # tid -> float 1..0 (capture feedback)
var _pulse_t := 0.0 # contested-territory pulse clock

# --- match state ---
var selected_id := -1
var target_mode := false
var paused := false
var speed_setting := 1.0
var _refresh_t := 0.0
var _last_notif := 0
var _end_shown := false

# --- HUD refs ---
var _hud: CanvasLayer
var _toast_layer: CanvasLayer
var _v_credits: Label
var _v_supplies: Label
var _v_manpower: Label
var _v_land: Label
var _v_day: Label
var _speed_btns: Array = []
var _pause_btn: Button
var _right_panel: PanelContainer
var _right_vbox: VBoxContainer
var _rp := {} # dynamic info label refs
var _ticker_labels: Array = []
var _pause_layer: CanvasLayer
var _end_layer: CanvasLayer
var _dialog_layer: CanvasLayer

# --- touch / mouse camera state ---
var _touches := {} # index -> {pos, start, time}
var _pinch_dist := 0.0


static func gs_class() -> GDScript:
	if _GameState == null and ResourceLoader.exists(GS_PATH):
		_GameState = load(GS_PATH) as GDScript
	return _GameState


static func ss_class() -> GDScript:
	if _SaveSystem == null and ResourceLoader.exists(SS_PATH):
		_SaveSystem = load(SS_PATH) as GDScript
	return _SaveSystem


func _ready() -> void:
	# The root Control must not eat mouse events or _unhandled_input (map
	# taps) will never fire. HUD widgets consume their own input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var GS := gs_class()
	if GS == null:
		_fatal("Game core is missing:\n%s was not found." % GS_PATH)
		return
	if pending_state != null:
		state = pending_state
		pending_state = null
	elif not pending_settings.is_empty():
		var s: Dictionary = pending_settings
		pending_settings = {}
		state = GS.create(s)
	else:
		# Defensive fallback: never show a dead screen.
		state = GS.create({"map_size": 1, "ai_count": 3, "difficulty": 1,
			"preset": "standard", "speed": 1.0})
	if state == null:
		_fatal("Could not create the game state.")
		return
	speed_setting = clampf(float(state.settings.get("speed", 1.0)), 0.5, 4.0)

	_build_map()
	_build_hud()
	_focus_camera_initial()
	_last_notif = (state.notifications as Array).size()
	refresh_all()


func _fatal(msg: String) -> void:
	add_child(UiKit.background())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vb := UiKit.vbox(14)
	center.add_child(vb)
	vb.add_child(UiKit.make_label(msg, 20, UiKit.DANGER))
	var back := UiKit.make_button("Back to Menu", 56, 20)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))
	vb.add_child(back)


# =====================================================================
# MAP
# =====================================================================
func _build_map() -> void:
	_map_root = Node2D.new()
	_map_root.name = "MapRoot"
	add_child(_map_root)

	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	_camera.make_current()

	_transit_layer = Node2D.new()
	_transit_layer.name = "Transits"
	_map_root.add_child(_transit_layer)

	for t in state.territories:
		_make_territory_node(t)

	_frontier_layer = Node2D.new()
	_frontier_layer.name = "Frontiers"
	_frontier_layer.z_index = 5
	_map_root.add_child(_frontier_layer)


func _make_territory_node(t: TerritoryData) -> void:
	var n := Node2D.new()
	n.name = "T%d" % t.id
	_map_root.add_child(n)

	var fill := Polygon2D.new()
	fill.polygon = t.polygon
	n.add_child(fill)
	_fill[t.id] = fill

	var tint := Polygon2D.new()
	tint.polygon = t.polygon
	tint.color = TERRAIN_TINTS.get(t.terrain, Color(0.5, 0.5, 0.5, 0.2))
	n.add_child(tint)

	var closed := PackedVector2Array(t.polygon)
	if closed.size() > 0:
		closed.append(closed[0])

	var border := Line2D.new()
	border.points = closed
	border.width = 2.5
	border.joint_mode = Line2D.LINE_JOINT_ROUND
	n.add_child(border)
	_border[t.id] = border

	var sel := Line2D.new()
	sel.points = closed
	sel.width = 7.0
	sel.default_color = Color.WHITE
	sel.joint_mode = Line2D.LINE_JOINT_ROUND
	sel.visible = false
	sel.z_index = 6
	n.add_child(sel)
	_selection_line[t.id] = sel

	if t.has_river:
		var river := Line2D.new()
		river.points = PackedVector2Array(
			[t.center + Vector2(-46, 12), t.center + Vector2(46, -12)])
		river.width = 6.0
		river.default_color = Color(0.30, 0.56, 0.95, 0.9)
		river.z_index = 2
		n.add_child(river)

	if t.has_city or t.is_capital:
		var r := 26.0 if t.is_capital else 13.0
		var dia := Polygon2D.new()
		dia.polygon = PackedVector2Array(
			[Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
		dia.position = t.center + Vector2(0, -40)
		dia.color = Color(1.0, 0.82, 0.25) if t.is_capital else Color(0.95, 0.78, 0.42)
		dia.z_index = 3
		n.add_child(dia)
		if t.is_capital:
			# Double ring + crown tick marks: unmistakable capital marker.
			for rr in [r + 7.0, r + 14.0]:
				var ring := Line2D.new()
				ring.points = PackedVector2Array([Vector2(0, -rr), Vector2(rr, 0),
					Vector2(0, rr), Vector2(-rr, 0), Vector2(0, -rr)])
				ring.width = 3.0 if rr < r + 10.0 else 2.0
				ring.default_color = Color.WHITE
				ring.position = dia.position
				ring.z_index = 3
				n.add_child(ring)

	var marker := Node2D.new()
	marker.position = t.center
	marker.z_index = 4
	n.add_child(marker)
	_army_marker[t.id] = marker
	var circ := Polygon2D.new()
	circ.polygon = UiKit.circle_points(24.0, 12)
	marker.add_child(circ)
	_army_circle[t.id] = circ
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.position = Vector2(-50, -17)
	lbl.size = Vector2(100, 34)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(lbl)
	_army_label[t.id] = lbl


func _nation_color(nid: int) -> Color:
	if nid >= 0 and nid < (state.nations as Array).size():
		return (state.nations as Array)[nid].color
	return Tacterra.NEUTRAL_COLOR


func refresh_all() -> void:
	_refresh_map()
	_update_top_bar()
	_rebuild_right_panel()


func _refresh_map() -> void:
	if state == null:
		return
	var sel_t = state.get_territory(selected_id) if selected_id >= 0 else null
	var valid_targets := {}
	if target_mode and sel_t != null:
		for nb in sel_t.neighbors:
			valid_targets[nb] = true
	# Eligible neighbors of the selected territory, shown even outside
	# target mode: attackable (neutral/enemy) vs reinforceable (own).
	var atk_nb := {}
	var rinf_nb := {}
	if not target_mode and sel_t != null and sel_t.owner_id == 0:
		for nb_id in sel_t.neighbors:
			var nb = state.get_territory(nb_id)
			if nb == null:
				continue
			if nb.owner_id == 0:
				rinf_nb[nb_id] = true
			else:
				atk_nb[nb_id] = true
	# Territories under attack (inbound hostile transit) get a red pulse.
	var contested := {}
	for a in state.transits:
		var ta = state.get_territory(a.move_to)
		if ta != null and a.owner_id != ta.owner_id:
			contested[a.move_to] = true
	for t in state.territories:
		var ncol := _nation_color(t.owner_id)
		var is_sel: bool = t.id == selected_id
		# Capture flash: brighten briefly when ownership changes.
		if not _last_owner.has(t.id):
			_last_owner[t.id] = t.owner_id
		elif int(_last_owner[t.id]) != t.owner_id:
			_last_owner[t.id] = t.owner_id
			_flash[t.id] = 1.0
		var flash: float = float(_flash.get(t.id, 0.0))
		var fill: Polygon2D = _fill[t.id]
		var base := Color(ncol.r * 0.55, ncol.g * 0.55, ncol.b * 0.55)
		if is_sel:
			base = base.lightened(0.35)
		if flash > 0.0:
			base = base.lerp(Color.WHITE, flash * 0.7)
		fill.color = base
		var border: Line2D = _border[t.id]
		border.default_color = Color(ncol.r * 0.32, ncol.g * 0.32, ncol.b * 0.32)
		var sel: Line2D = _selection_line[t.id]
		if is_sel:
			sel.visible = true
			sel.default_color = Color.WHITE
		elif valid_targets.has(t.id):
			sel.visible = true
			sel.default_color = UiKit.ACCENT
		elif atk_nb.has(t.id):
			sel.visible = true
			sel.default_color = Color(1.0, 0.75, 0.25) # gold: attackable
		elif rinf_nb.has(t.id):
			sel.visible = true
			sel.default_color = Color(0.45, 0.75, 1.0) # blue: reinforceable
		elif contested.has(t.id):
			sel.visible = true
			var pulse := 0.55 + 0.45 * sin(_pulse_t * 6.0)
			sel.default_color = Color(1.0, 0.25, 0.2, pulse)
		else:
			sel.visible = false
		var marker: Node2D = _army_marker[t.id]
		var circ: Polygon2D = _army_circle[t.id]
		var lbl: Label = _army_label[t.id]
		var troops := 0
		var acol := ncol
		if t.army != null and t.army.troops > 0:
			troops = t.army.troops
		elif t.owner_id == -1 and t.garrison > 0:
			troops = t.garrison
			acol = Tacterra.NEUTRAL_COLOR
		if troops > 0:
			marker.visible = true
			circ.color = acol
			lbl.text = Tacterra.format_num(float(troops))
		else:
			marker.visible = false
	_refresh_transits()
	_refresh_frontiers()


## Draw a strong dark line along every edge shared by two territories with
## different owners. Internal borders stay thin; national frontiers read
## clearly without dominating the map.
func _refresh_frontiers() -> void:
	if _frontier_layer == null:
		return
	for c in _frontier_layer.get_children():
		c.queue_free()
	if state == null:
		return
	for t in state.territories:
		for nb_id in t.neighbors:
			if nb_id <= t.id:
				continue # draw each shared edge once
			var nb = state.get_territory(nb_id)
			if nb == null or nb.owner_id == t.owner_id:
				continue
			var edge := _shared_edge(t.polygon, nb.polygon)
			if edge.size() == 2:
				var line := Line2D.new()
				line.points = edge
				line.width = 5.5
				line.default_color = Color(0.04, 0.05, 0.07, 0.92)
				line.joint_mode = Line2D.LINE_JOINT_ROUND
				_frontier_layer.add_child(line)
			else:
				# Fallback: straight line between centers when the shared
				# edge can't be resolved (should be rare).
				var line2 := Line2D.new()
				line2.points = PackedVector2Array([t.center, nb.center])
				line2.width = 3.0
				line2.default_color = Color(0.04, 0.05, 0.07, 0.6)
				_frontier_layer.add_child(line2)


## The two endpoints of the edge shared by two adjacent polygons.
## Adjacent cells share identical vertex positions (same circumcenter
## computation), so a small tolerance is enough.
func _shared_edge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for va in a:
		for vb in b:
			if va.distance_squared_to(vb) < 9.0:
				pts.append(va)
				break
		if pts.size() == 2:
			break
	return pts


func _refresh_transits() -> void:
	for c in _transit_layer.get_children():
		c.queue_free()
	for a in state.transits:
		var fa = state.get_territory(a.move_from)
		var ta = state.get_territory(a.move_to)
		if fa == null or ta == null:
			continue
		var col := _nation_color(a.owner_id)
		var line := Line2D.new()
		line.points = PackedVector2Array([fa.center, ta.center])
		line.width = 4.0
		line.default_color = Color(col, 0.85)
		_transit_layer.add_child(line)
		var frac := 0.0
		if a.move_total > 0.0:
			frac = clampf(a.move_progress / a.move_total, 0.0, 1.0)
		var dot := Polygon2D.new()
		dot.polygon = UiKit.circle_points(12.0, 10)
		dot.position = fa.center.lerp(ta.center, frac)
		dot.color = col
		_transit_layer.add_child(dot)
		var dir: Vector2 = (ta.center - fa.center).normalized()
		if dir.length() > 0.01:
			var tip: Vector2 = ta.center - dir * 34.0
			var perp := Vector2(-dir.y, dir.x)
			var tri := Polygon2D.new()
			tri.polygon = PackedVector2Array(
				[tip + dir * 20.0, tip - dir * 6.0 + perp * 13.0, tip - dir * 6.0 - perp * 13.0])
			tri.color = col
			_transit_layer.add_child(tri)


# =====================================================================
# CAMERA
# =====================================================================
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _focus_camera_initial() -> void:
	var target := Vector2(Tacterra.WORLD_SIZE.x * 0.5, Tacterra.WORLD_SIZE.y * 0.5)
	var p = state.player()
	if p != null:
		var cap = state.get_territory(p.capital_id)
		if cap != null:
			target = cap.center
	_camera.position = target
	var vs := get_viewport().get_visible_rect().size
	var z := clampf(minf(vs.x / 1500.0, vs.y / 950.0), 0.35, 1.1)
	_camera.zoom = Vector2(z, z)
	_clamp_camera()


func _clamp_camera() -> void:
	var vs := get_viewport().get_visible_rect().size
	var half := vs * 0.5 / _camera.zoom.x
	var w := Tacterra.WORLD_SIZE
	var margin := 250.0
	var cx := w.x * 0.5
	var cy := w.y * 0.5
	if half.x < w.x * 0.5 + margin:
		cx = clampf(_camera.position.x, half.x - margin, w.x - half.x + margin)
	if half.y < w.y * 0.5 + margin:
		cy = clampf(_camera.position.y, half.y - margin, w.y - half.y + margin)
	_camera.position = Vector2(cx, cy)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old := _camera.zoom.x
	var new := clampf(old * factor, 0.35, 2.5)
	if is_equal_approx(old, new):
		return
	var before := _screen_to_world(screen_pos)
	_camera.zoom = Vector2(new, new)
	var after := _screen_to_world(screen_pos)
	_camera.position += before - after
	_clamp_camera()


# =====================================================================
# INPUT — tap to select, drag to pan, wheel/pinch to zoom.
# With emulate_touch_from_mouse enabled, desktop mouse input arrives as
# ScreenTouch/ScreenDrag, so one code path covers mouse AND touch.
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if state == null or _dialog_layer != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = {
				"pos": st.position,
				"start": st.position,
				"time": Time.get_ticks_msec() / 1000.0,
			}
			if _touches.size() == 2:
				var ks := _touches.keys()
				_pinch_dist = ((_touches[ks[0]] as Dictionary)["pos"] as Vector2) \
					.distance_to((_touches[ks[1]] as Dictionary)["pos"] as Vector2)
		else:
			var info: Dictionary = _touches.get(st.index, {})
			_touches.erase(st.index)
			if not info.is_empty() and _touches.is_empty():
				var dt: float = Time.get_ticks_msec() / 1000.0 - float(info["time"])
				var moved: float = st.position.distance_to(info["start"] as Vector2)
				if dt < 0.45 and moved < 26.0:
					_handle_tap(st.position)
			_pinch_dist = 0.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.has(sd.index):
			(_touches[sd.index] as Dictionary)["pos"] = sd.position
		if _touches.size() == 1:
			_camera.position -= sd.relative / _camera.zoom.x
			_clamp_camera()
		elif _touches.size() == 2:
			var ks := _touches.keys()
			var d: float = ((_touches[ks[0]] as Dictionary)["pos"] as Vector2) \
				.distance_to((_touches[ks[1]] as Dictionary)["pos"] as Vector2)
			if _pinch_dist > 0.0 and d > 0.0:
				var mid := (((_touches[ks[0]] as Dictionary)["pos"] as Vector2) \
					+ ((_touches[ks[1]] as Dictionary)["pos"] as Vector2)) * 0.5
				_zoom_at(mid, d / _pinch_dist)
			_pinch_dist = d


func _handle_tap(screen_pos: Vector2) -> void:
	var w := _screen_to_world(screen_pos)
	var best := -1
	var bestd := 110.0
	for t in state.territories:
		var d := w.distance_to(t.center)
		if d < bestd:
			bestd = d
			best = t.id
	if best == -1:
		return
	if target_mode and best != selected_id:
		var src = state.get_territory(selected_id)
		if src != null and (src.neighbors as Array).has(best):
			_open_move_dialog(selected_id, best)
		else:
			UiKit.toast(_toast_layer, "Not adjacent — tap a highlighted neighbor.", UiKit.DANGER)
		return
	select_territory(best)


func select_territory(tid: int) -> void:
	selected_id = tid
	target_mode = false
	_refresh_map()
	_rebuild_right_panel()


# =====================================================================
# HUD
# =====================================================================
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	_hud.name = "HUD"
	add_child(_hud)

	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 50
	add_child(_toast_layer)

	_build_top_bar()
	_build_right_panel()
	_build_bottom_bar()
	_build_pause_overlay()
	_build_end_overlay()


func _res_vbox(caption: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var c := UiKit.make_label(caption, 13, UiKit.TEXT_DIM)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var val := UiKit.make_label("-", 18)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size = Vector2(132, 0)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.clip_text = true
	v.add_child(val)
	return v


func _build_top_bar() -> void:
	var top := UiKit.make_panel()
	top.name = "TopBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 68
	_hud.add_child(top)

	var hb := UiKit.hbox(14)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(hb)

	_pause_btn = UiKit.make_small_button("Menu")
	_pause_btn.pressed.connect(_open_pause_menu)
	hb.add_child(_pause_btn)

	var vc := _res_vbox("Credits")
	_v_credits = vc.get_child(1)
	hb.add_child(vc)
	var vs := _res_vbox("Supplies")
	_v_supplies = vs.get_child(1)
	hb.add_child(vs)
	var vm := _res_vbox("Manpower")
	_v_manpower = vm.get_child(1)
	hb.add_child(vm)
	var vl := _res_vbox("Land")
	_v_land = vl.get_child(1)
	hb.add_child(vl)

	_v_day = UiKit.make_label("Day 1", 20, UiKit.ACCENT)
	_v_day.custom_minimum_size = Vector2(90, 0)
	_v_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(_v_day)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(spacer)

	var group := ButtonGroup.new()
	for sname in ["II", "0.5x", "1x", "2x", "4x"]:
		var b := UiKit.make_small_button(sname)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(64, UiKit.MIN_TOUCH)
		var nm: String = sname
		b.pressed.connect(func() -> void: _on_speed_pressed(nm))
		hb.add_child(b)
		_speed_btns.append(b)
	_update_speed_buttons()


func _on_speed_pressed(sname: String) -> void:
	if sname == "II":
		paused = true
	else:
		paused = false
		speed_setting = float(sname.trim_suffix("x"))
	_update_speed_buttons()


func _update_speed_buttons() -> void:
	for b in _speed_btns:
		var btn := b as Button
		var active := false
		if btn.text == "II":
			active = paused
		else:
			active = (not paused) and is_equal_approx(speed_setting, float(btn.text.trim_suffix("x")))
		btn.set_pressed_no_signal(active)


func _build_right_panel() -> void:
	_right_panel = UiKit.make_panel()
	_right_panel.name = "RightPanel"
	_right_panel.anchor_left = 1.0
	_right_panel.anchor_right = 1.0
	_right_panel.anchor_top = 0.0
	_right_panel.anchor_bottom = 1.0
	_right_panel.offset_left = -376
	_right_panel.offset_right = -12
	_right_panel.offset_top = 80
	_right_panel.offset_bottom = -12
	_right_panel.visible = false
	_hud.add_child(_right_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.add_child(scroll)
	_right_vbox = UiKit.vbox(10)
	_right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right_vbox)


func _build_bottom_bar() -> void:
	var bottom := UiKit.make_panel()
	bottom.name = "TickerPanel"
	bottom.anchor_left = 0.0
	bottom.anchor_right = 0.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 12
	bottom.offset_right = 540
	bottom.offset_top = -172
	bottom.offset_bottom = -12
	_hud.add_child(bottom)
	bottom.gui_input.connect(_on_ticker_gui_input)

	var vb := UiKit.vbox(4)
	bottom.add_child(vb)
	var cap := UiKit.make_label("LATEST (tap to expand)", 13, UiKit.TEXT_DIM)
	vb.add_child(cap)
	for _i in range(3):
		var l := UiKit.make_label("", 15)
		l.custom_minimum_size = Vector2(0, 22)
		l.clip_text = true
		vb.add_child(l)
		_ticker_labels.append(l)
	var hb := UiKit.hbox(10)
	vb.add_child(hb)
	var reports := UiKit.make_small_button("Reports")
	reports.pressed.connect(_open_reports_dialog)
	hb.add_child(reports)
	var notifs := UiKit.make_small_button("Notifications")
	notifs.pressed.connect(_open_notifications_dialog)
	hb.add_child(notifs)


func _on_ticker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_notifications_dialog()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_open_notifications_dialog()


func _build_pause_overlay() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 40
	_pause_layer.name = "PauseLayer"
	_pause_layer.visible = false
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var vb := UiKit.vbox(12)
	panel.add_child(vb)
	vb.add_child(UiKit.make_title("Paused", 40))
	var resume := UiKit.make_button("Resume", 56, 20)
	resume.pressed.connect(_close_pause_menu)
	vb.add_child(resume)
	var save := UiKit.make_button("Save Game", 56, 20)
	save.pressed.connect(_do_save)
	vb.add_child(save)
	var help := UiKit.make_button("How to Play", 56, 20)
	help.pressed.connect(_open_help_overlay)
	vb.add_child(help)
	var quit := UiKit.make_button("Quit to Menu", 56, 20)
	quit.pressed.connect(_confirm_quit)
	vb.add_child(quit)


func _open_pause_menu() -> void:
	paused = true
	_update_speed_buttons()
	_pause_layer.visible = true


func _close_pause_menu() -> void:
	_pause_layer.visible = false
	paused = false
	_update_speed_buttons()


func _confirm_quit() -> void:
	_confirm_dialog("Quit to main menu?",
		"Unsaved progress will be lost. Save first from the pause menu if needed.",
		"Quit", func() -> void:
			_pause_layer.visible = false
			pending_settings = {}
			pending_state = null
			get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))


func _build_end_overlay() -> void:
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 60
	_end_layer.name = "EndLayer"
	_end_layer.visible = false
	add_child(_end_layer)


# =====================================================================
# RIGHT PANEL — territory info + contextual actions
# =====================================================================
func _rebuild_right_panel() -> void:
	for c in _right_vbox.get_children():
		c.queue_free()
	_rp.clear()
	if selected_id < 0:
		_right_panel.visible = false
		return
	var t = state.get_territory(selected_id)
	if t == null:
		_right_panel.visible = false
		return
	_right_panel.visible = true

	var name_lbl := UiKit.make_label(t.name, 26, UiKit.ACCENT)
	_right_vbox.add_child(name_lbl)

	var owner_text := "Neutral"
	var owner_col := Tacterra.NEUTRAL_COLOR
	if t.owner_id >= 0:
		var n = state.get_nation(t.owner_id)
		owner_text = n.name + (" (You)" if t.owner_id == 0 else "")
		owner_col = n.color
	var owner_lbl := UiKit.make_label("Owner: " + owner_text, 18, owner_col)
	_right_vbox.add_child(owner_lbl)

	var flags: Array = [Tacterra.terrain_name(t.terrain)]
	if t.is_coastal:
		flags.append("Coastal")
	if t.has_city:
		flags.append("City")
	if t.is_capital:
		flags.append("Capital")
	if t.has_river:
		flags.append("River")
	_right_vbox.add_child(UiKit.make_label(" • ".join(flags), 16, UiKit.TEXT_DIM))

	for key in ["income", "pop", "def", "supply", "troops", "dev", "queue"]:
		var l := UiKit.make_label("", 17)
		_right_vbox.add_child(l)
		_rp[key] = l
	_refresh_right_panel()

	_right_vbox.add_child(UiKit.spacer(6))
	var ab := UiKit.vbox(10)
	ab.name = "ActionButtons"
	_right_vbox.add_child(ab)

	if t.owner_id == 0:
		if t.army != null and t.army.troops > 0:
			var mv := UiKit.make_button("Move / Attack", 52, 19)
			mv.pressed.connect(_enter_target_mode)
			ab.add_child(mv)
		var rec := UiKit.make_button("Recruit", 52, 19)
		rec.pressed.connect(func() -> void: _open_recruit_dialog(t.id))
		ab.add_child(rec)
		var dc: float = t.develop_cost()
		var dev := UiKit.make_button("Develop  (Lv %d/%d)" % [t.development, Tacterra.DEVELOP_MAX], 52, 19)
		dev.disabled = dc < 0.0
		dev.pressed.connect(func() -> void: _open_develop_dialog(t.id))
		ab.add_child(dev)
		var fc: float = t.fort_cost()
		var fort := UiKit.make_button("Fortify  (Lv %d/%d)" % [t.fort_level, Tacterra.FORT_MAX], 52, 19)
		fort.disabled = fc < 0.0
		fort.pressed.connect(func() -> void: _open_fortify_dialog(t.id))
		ab.add_child(fort)
	else:
		_right_vbox.add_child(UiKit.make_label(
			"Select one of your territories, then use Move / Attack and tap here — or strike directly:",
			16, UiKit.TEXT_DIM))
		for nb in t.neighbors:
			var nt = state.get_territory(nb)
			if nt != null and nt.owner_id == 0 and nt.army != null and nt.army.troops > 0:
				var from_id: int = nb
				var b := UiKit.make_small_button("Attack from %s (%s)" % [
					nt.name, Tacterra.format_num(float(nt.army.troops))])
				b.pressed.connect(func() -> void: _open_move_dialog(from_id, t.id))
				ab.add_child(b)

	var close := UiKit.make_small_button("Deselect")
	close.pressed.connect(func() -> void: select_territory(-1))
	_right_vbox.add_child(close)


func _refresh_right_panel() -> void:
	if not _right_panel.visible or selected_id < 0 or _rp.is_empty():
		return
	var t = state.get_territory(selected_id)
	if t == null:
		return
	(_rp["income"] as Label).text = "Income: %s/day" % Tacterra.format_num(t.income_per_day())
	(_rp["pop"] as Label).text = "Population: %s" % Tacterra.format_num(float(t.population))
	var dm: float = t.defense_mult()
	(_rp["def"] as Label).text = "Defense: x%.2f (%s%+d%%)" % [dm,
		"+" if dm >= 1.0 else "", int(round((dm - 1.0) * 100.0))]
	var sup: Label = _rp["supply"]
	if t.owner_id < 0:
		sup.text = "Supply: —"
		sup.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	elif t.supplied:
		sup.text = "Supply: connected"
		sup.add_theme_color_override("font_color", UiKit.GOOD)
	else:
		sup.text = "Supply: CUT OFF"
		sup.add_theme_color_override("font_color", UiKit.DANGER)
	if t.army != null and t.army.troops > 0:
		(_rp["troops"] as Label).text = "Army: %s troops" % Tacterra.format_num(float(t.army.troops))
	elif t.owner_id == -1 and t.garrison > 0:
		(_rp["troops"] as Label).text = "Garrison: %s troops" % Tacterra.format_num(float(t.garrison))
	else:
		(_rp["troops"] as Label).text = "Army: none"
	(_rp["dev"] as Label).text = "Development Lv %d/%d  •  Fort Lv %d/%d" % [
		t.development, Tacterra.DEVELOP_MAX, t.fort_level, Tacterra.FORT_MAX]
	var q: Array = (state.training_queues as Dictionary).get(t.id, [])
	if q.is_empty():
		(_rp["queue"] as Label).text = "Training: —"
	else:
		var parts: Array = []
		for e in q:
			var ed: Dictionary = e
			parts.append("%d troops (%.1fd)" % [int(ed.get("troops", 0)), float(ed.get("days_left", 0.0))])
		(_rp["queue"] as Label).text = "Training: " + ", ".join(parts)


func _enter_target_mode() -> void:
	target_mode = true
	_refresh_map()
	UiKit.toast(_toast_layer, "Tap a highlighted neighboring territory.")


# =====================================================================
# DIALOGS
# =====================================================================
func _open_dialog(title: String, width: float = 460.0) -> VBoxContainer:
	_close_dialog()
	_dialog_layer = CanvasLayer.new()
	_dialog_layer.layer = 45
	add_child(_dialog_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_layer.add_child(center)
	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var vb := UiKit.vbox(12)
	panel.add_child(vb)
	vb.add_child(UiKit.make_label(title, 26, UiKit.ACCENT))
	return vb


func _close_dialog() -> void:
	if is_instance_valid(_dialog_layer):
		_dialog_layer.queue_free()
	_dialog_layer = null


func _dialog_close_row(vb: VBoxContainer, label_text: String = "Close") -> void:
	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var b := UiKit.make_small_button(label_text)
	b.pressed.connect(_close_dialog)
	hb.add_child(b)


func _confirm_dialog(title: String, body: String, yes_text: String, on_yes: Callable) -> void:
	var vb := _open_dialog(title, 440.0)
	vb.add_child(UiKit.make_label(body, 17, UiKit.TEXT_DIM))
	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var no := UiKit.make_small_button("Cancel")
	no.pressed.connect(_close_dialog)
	hb.add_child(no)
	var yes := UiKit.make_small_button(yes_text)
	yes.pressed.connect(func() -> void:
		_close_dialog()
		on_yes.call())
	hb.add_child(yes)


func _open_move_dialog(from_id: int, to_id: int) -> void:
	var t = state.get_territory(from_id)
	var dst = state.get_territory(to_id)
	if t == null or dst == null or t.army == null or t.army.troops <= 0:
		return
	target_mode = false
	var vb := _open_dialog("Move / Attack", 480.0)
	vb.add_child(UiKit.make_label("%s  →  %s" % [t.name, dst.name], 20))
	var dist: float = t.center.distance_to(dst.center)
	var days: float = dist / Tacterra.MOVE_SPEED
	vb.add_child(UiKit.make_label("Distance: %d   •   March: %.1f days" % [int(dist), days],
		16, UiKit.TEXT_DIM))
	if dst.owner_id == -1:
		vb.add_child(UiKit.make_label("Neutral garrison: %s troops" % Tacterra.format_num(float(dst.garrison)), 17))
	elif dst.owner_id != 0:
		var en = state.get_nation(dst.owner_id)
		var dtroops: int = dst.army.troops if (dst.army != null) else 0
		vb.add_child(UiKit.make_label("Enemy %s: %s troops, defense x%.2f" % [
			en.name, Tacterra.format_num(float(dtroops)), dst.defense_mult()], 17))
	else:
		vb.add_child(UiKit.make_label("Friendly territory — armies will merge on arrival.", 17))
	if not dst.supplied and dst.owner_id == 0:
		vb.add_child(UiKit.make_label(
			"Warning: destination is CUT OFF from supply. -40% power, attrition risk.",
			17, UiKit.DANGER))
	elif not t.supplied:
		vb.add_child(UiKit.make_label(
			"Warning: this army is unsupplied. -40% power, attrition risk.",
			17, UiKit.DANGER))

	var maxv: int = t.army.troops
	var troops_lbl := UiKit.make_label("Troops: %d" % maxv, 19)
	vb.add_child(troops_lbl)
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = maxv
	slider.step = 1
	slider.value = maxv
	slider.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: troops_lbl.text = "Troops: %d" % int(v))
	vb.add_child(slider)
	vb.add_child(UiKit.make_label("Slide to leave a garrison behind.", 15, UiKit.TEXT_DIM))

	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var cancel := UiKit.make_small_button("Cancel")
	cancel.pressed.connect(_close_dialog)
	hb.add_child(cancel)
	var go := UiKit.make_small_button("Confirm March")
	go.pressed.connect(func() -> void:
		var res: Dictionary = state.order_move(0, from_id, to_id, int(slider.value))
		_close_dialog()
		if bool(res.get("ok", false)):
			UiKit.toast(_toast_layer, "March order issued.", UiKit.GOOD)
		else:
			UiKit.toast(_toast_layer, str(res.get("error", "Order rejected.")), UiKit.DANGER)
		refresh_all())
	hb.add_child(go)


func _open_recruit_dialog(tid: int) -> void:
	var t = state.get_territory(tid)
	var p = state.player()
	var vb := _open_dialog("Recruit — " + t.name, 480.0)
	var max_aff := int(minf(p.manpower, p.credits / Tacterra.RECRUIT_COST))
	if max_aff < 10:
		vb.add_child(UiKit.make_label(
			"Cannot recruit: need at least 10 manpower and %d credits." % int(10 * Tacterra.RECRUIT_COST),
			17, UiKit.DANGER))
		_dialog_close_row(vb)
		return
	var info := UiKit.make_label("", 18)
	vb.add_child(info)
	var slider := HSlider.new()
	slider.min_value = 10
	slider.max_value = max_aff
	slider.step = 10
	slider.value = minf(100.0, float(max_aff))
	slider.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(slider)
	var upd := func(v: float) -> void:
		var n := int(v)
		info.text = "%d troops\nCost: %s credits  •  %d manpower\nReady in %.0f days of training." % [
			n, Tacterra.format_num(n * Tacterra.RECRUIT_COST), n, Tacterra.RECRUIT_TRAIN_DAYS]
	slider.value_changed.connect(upd)
	upd.call(slider.value)

	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var cancel := UiKit.make_small_button("Cancel")
	cancel.pressed.connect(_close_dialog)
	hb.add_child(cancel)
	var go := UiKit.make_small_button("Recruit")
	go.pressed.connect(func() -> void:
		var res: Dictionary = state.order_recruit(0, tid, int(slider.value))
		_close_dialog()
		if bool(res.get("ok", false)):
			UiKit.toast(_toast_layer, "Recruits training — ready in %.0f days." % Tacterra.RECRUIT_TRAIN_DAYS, UiKit.GOOD)
		else:
			UiKit.toast(_toast_layer, str(res.get("error", "Recruitment failed.")), UiKit.DANGER)
		refresh_all())
	hb.add_child(go)


func _open_develop_dialog(tid: int) -> void:
	var t = state.get_territory(tid)
	var cost: float = t.develop_cost()
	var vb := _open_dialog("Develop — " + t.name, 460.0)
	if cost < 0.0:
		vb.add_child(UiKit.make_label("Already at maximum development (Lv %d)." % Tacterra.DEVELOP_MAX, 17))
		_dialog_close_row(vb)
		return
	var now_inc: float = t.income_per_day()
	var after_inc: float = t.base_income() * (1.0 + Tacterra.DEVELOP_LEVEL_BONUS * float(t.development + 1))
	vb.add_child(UiKit.make_label(
		"Raise development to Lv %d.\nIncome: %s/day  →  %s/day (+25%%).\nCost: %s credits." % [
			t.development + 1, Tacterra.format_num(now_inc),
			Tacterra.format_num(after_inc), Tacterra.format_num(cost)], 18))
	_order_confirm_row(vb, "Develop", func() -> Dictionary: return state.order_develop(0, tid),
		"Development started.")


func _open_fortify_dialog(tid: int) -> void:
	var t = state.get_territory(tid)
	var cost: float = t.fort_cost()
	var vb := _open_dialog("Fortify — " + t.name, 460.0)
	if cost < 0.0:
		vb.add_child(UiKit.make_label("Already at maximum fort level (Lv %d)." % Tacterra.FORT_MAX, 17))
		_dialog_close_row(vb)
		return
	vb.add_child(UiKit.make_label(
		"Raise fort to Lv %d.\nDefense here: x%.2f  →  x%.2f (+%d%%).\nCost: %s credits." % [
			t.fort_level + 1, t.defense_mult(),
			t.defense_mult() * (1.0 + Tacterra.FORT_DEF_BONUS),
			int(Tacterra.FORT_DEF_BONUS * 100.0), Tacterra.format_num(cost)], 18))
	_order_confirm_row(vb, "Fortify", func() -> Dictionary: return state.order_fortify(0, tid),
		"Fortification started.")


func _order_confirm_row(vb: VBoxContainer, verb: String, order: Callable, ok_text: String) -> void:
	var hb := UiKit.hbox(12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	var cancel := UiKit.make_small_button("Cancel")
	cancel.pressed.connect(_close_dialog)
	hb.add_child(cancel)
	var go := UiKit.make_small_button(verb)
	go.pressed.connect(func() -> void:
		var res: Dictionary = order.call()
		_close_dialog()
		if bool(res.get("ok", false)):
			UiKit.toast(_toast_layer, ok_text, UiKit.GOOD)
		else:
			UiKit.toast(_toast_layer, str(res.get("error", "Order rejected.")), UiKit.DANGER)
		refresh_all())
	hb.add_child(go)


func _open_reports_dialog() -> void:
	var vb := _open_dialog("Battle Reports", 520.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var reps: Array = state.battle_reports
	if reps.is_empty():
		list.add_child(UiKit.make_label("No battles yet.", 17, UiKit.TEXT_DIM))
	for i in range(reps.size() - 1, -1, -1):
		var r: Dictionary = reps[i]
		var txt := str(r.get("text", r.get("report_text", str(r))))
		list.add_child(UiKit.make_label("[Day %d] %s" % [int(r.get("day", 0)), txt], 16))
	_dialog_close_row(vb)


func _open_notifications_dialog() -> void:
	var vb := _open_dialog("Notifications", 520.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var notifs: Array = state.notifications
	if notifs.is_empty():
		list.add_child(UiKit.make_label("Nothing to report.", 17, UiKit.TEXT_DIM))
	for i in range(notifs.size() - 1, max(-1, notifs.size() - 31), -1):
		var n: Dictionary = notifs[i]
		list.add_child(UiKit.make_label("[Day %d] %s" % [int(n.get("day", 0)), str(n.get("text", ""))], 16))
	_dialog_close_row(vb)


func _open_help_overlay() -> void:
	var vb := _open_dialog("How to Play", 560.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = HowToPlay.help_text()
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.add_theme_color_override("default_color", UiKit.TEXT)
	rtl.add_theme_font_size_override("normal_font_size", 17)
	rtl.add_theme_font_size_override("bold_font_size", 19)
	rtl.scroll_active = false
	scroll.add_child(rtl)
	_dialog_close_row(vb)


# =====================================================================
# SAVE
# =====================================================================
func _do_save() -> void:
	var SS := ss_class()
	if SS == null:
		UiKit.toast(_toast_layer, "Save system unavailable.", UiKit.DANGER)
		return
	var res: Dictionary = SS.save(state, 0)
	if bool(res.get("ok", false)):
		UiKit.toast(_toast_layer, "Match saved.", UiKit.GOOD)
	else:
		UiKit.toast(_toast_layer, "Save failed: " + str(res.get("error", "?")), UiKit.DANGER)


# =====================================================================
# END SCREEN
# =====================================================================
func _show_end_screen() -> void:
	for c in _end_layer.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_layer.add_child(center)
	var panel := UiKit.make_panel()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var vb := UiKit.vbox(12)
	panel.add_child(vb)

	var p = state.player()
	var st: Dictionary = p.stats if p != null else {}

	if state.player_won:
		vb.add_child(UiKit.make_title("VICTORY!", 56))
		vb.add_child(UiKit.make_label("Every rival nation has fallen. The continent is yours.",
			19, UiKit.GOOD))
	else:
		vb.add_child(UiKit.make_title("DEFEAT", 56))
		var wname := "A rival power"
		if state.winner_id >= 0:
			var w = state.get_nation(state.winner_id)
			if w != null:
				wname = w.name
		vb.add_child(UiKit.make_label("%s rules the continent now. Your nation has fallen." % wname,
			19, UiKit.DANGER))

	var land := (state.owned_ids(0) as Array).size()
	var stats_text := "Days played: %d\nTerritories captured: %d\nTerritories held: %d\n" % [
		int(state.day), int(st.get("captured", 0)), land]
	stats_text += "Battles won: %d   •   lost: %d\n" % [
		int(st.get("battles_won", 0)), int(st.get("battles_lost", 0))]
	stats_text += "Troops lost: %s   •   enemies destroyed: %s\n" % [
		Tacterra.format_num(float(st.get("troops_lost", 0))),
		Tacterra.format_num(float(st.get("troops_killed", 0)))]
	stats_text += "Wealth earned: %s credits" % Tacterra.format_num(float(st.get("income_earned", 0.0)))
	var sl := UiKit.make_label(stats_text, 18)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sl)

	var again := UiKit.make_button("New Match", 60, 22)
	again.pressed.connect(func() -> void:
		pending_settings = {}
		pending_state = null
		get_tree().change_scene_to_file("res://scripts/ui/match_setup.tscn"))
	vb.add_child(again)
	var menu := UiKit.make_button("Main Menu", 56, 20)
	menu.pressed.connect(func() -> void:
		pending_settings = {}
		pending_state = null
		get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn"))
	vb.add_child(menu)
	_end_layer.visible = true


# =====================================================================
# MAIN LOOP
# =====================================================================
func _process(delta: float) -> void:
	if state == null:
		return
	if state.over:
		if not _end_shown:
			_end_shown = true
			paused = true
			_show_end_screen()
		return
	var eff := 0.0 if paused else speed_setting
	if eff > 0.0:
		state.tick(delta * eff * Tacterra.DAYS_PER_SECOND)
	_pulse_t += delta
	# Decay capture flashes (~0.8s).
	var done_flash: Array = []
	for tid in _flash.keys():
		_flash[tid] = float(_flash[tid]) - delta * 1.25
		if float(_flash[tid]) <= 0.0:
			done_flash.append(tid)
	for tid in done_flash:
		_flash.erase(tid)
	_refresh_t += delta
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh_map()
		_refresh_right_panel()
		_update_top_bar()
	_drain_notifications()


func _drain_notifications() -> void:
	var notifs: Array = state.notifications
	while _last_notif < notifs.size():
		var n: Dictionary = notifs[_last_notif]
		_last_notif += 1
		_push_ticker(str(n.get("text", "")))
		var kind := int(n.get("kind", Tacterra.NotifyKind.INFO))
		if kind == Tacterra.NotifyKind.BATTLE:
			UiKit.toast(_toast_layer, str(n.get("text", "")), UiKit.ACCENT)
		elif kind == Tacterra.NotifyKind.BAD:
			UiKit.toast(_toast_layer, str(n.get("text", "")), UiKit.DANGER)


func _push_ticker(text: String) -> void:
	if text.is_empty():
		return
	var lines: Array = []
	for l in _ticker_labels:
		var s := (l as Label).text
		if not s.is_empty():
			lines.append(s)
	lines.append(text)
	while lines.size() > 3:
		lines.pop_front()
	for i in range(_ticker_labels.size()):
		(_ticker_labels[i] as Label).text = str(lines[i]) if i < lines.size() else ""


func _update_top_bar() -> void:
	if state == null:
		return
	var p = state.player()
	var income := 0.0
	var upkeep := 0.0
	var sprod := 0.0
	var suse := 0.0
	var pop := 0.0
	for tid in state.owned_ids(0):
		var t = state.get_territory(tid)
		if t == null:
			continue
		income += t.income_per_day()
		pop += float(t.population)
		sprod += t.supply_production()
		if t.army != null:
			upkeep += float(t.army.troops) * Tacterra.UPKEEP_PER_SOLDIER
			suse += float(t.army.troops) * Tacterra.SUPPLY_USE_PER_SOLDIER
	for a in state.transits:
		if a.owner_id == 0:
			upkeep += float(a.troops) * Tacterra.UPKEEP_PER_SOLDIER
			suse += float(a.troops) * Tacterra.SUPPLY_USE_PER_SOLDIER
	_v_credits.text = "%s %+.0f/d" % [Tacterra.format_num(p.credits), income - upkeep]
	_v_supplies.text = "%s %+.0f/d" % [Tacterra.format_num(p.supplies), sprod - suse]
	var cap := pop / float(Tacterra.MANPOWER_CAP_DIV)
	_v_manpower.text = "%d/%d" % [int(p.manpower), int(cap)]
	_v_land.text = "%d/%d" % [(state.owned_ids(0) as Array).size(), (state.territories as Array).size()]
	_v_day.text = "Day %d" % int(state.day)
