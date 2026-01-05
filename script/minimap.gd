# FILE: res://script/minimap.gd
class_name MinimapController
extends Node

var host = null        # OpenTower
var build = null       # TowerBuild

var cfg: Dictionary = {
	"size": 256,
	"margin": 16,
	"frustum_color": Color(1, 0, 0, 1),
	"border": 4,
	"border_bg": Color(0, 0, 0, 0.5),
	"border_color": Color(1, 1, 1, 1),
	"viewbox_border": 2,
	"viewbox_color": Color(1, 1, 1, 1),
	"home_text": "Home",
	"grid_alpha": 0.25,
	"axis_alpha": 0.60,
	"right_click_zoom": true,
	"toggle_zoom_a": 0.8,
	"toggle_zoom_b": 1.4,

	# Debug
	"debug": false,
	"debug_font_size": 12,
	"debug_color": Color(1, 1, 1, 1),
}

# UI nodes
var layer: CanvasLayer
var border_panel: Panel
var texture_rect: TextureRect
var overlay: Control
var viewbox: Panel
var home_btn: Button
var debug_label: Label

# SubViewport + world
var viewport: SubViewport
var mini_world: Node2D
var mini_camera: Camera2D

# Draw layers
var _dl_bg: Node2D
var _dl_build: Node2D
var _dl_grid: Node2D
var _dl_frustum: Node2D

var dragging: bool = false

func setup(_host, _build, p_cfg: Dictionary) -> void:
	host = _host
	build = _build

	for k in p_cfg.keys():
		cfg[k] = p_cfg[k]

	_build_nodes()
	set_process(true)
	_relayout()
	update_viewbox()

	var win: Window = null
	if host != null:
		win = host.get_window()
	if win != null:
		if not win.is_connected("size_changed", Callable(self, "_on_screen_resized")):
			win.connect("size_changed", Callable(self, "_on_screen_resized"))

func _process(_delta: float) -> void:
	update_viewbox()

	if _dl_bg != null: _dl_bg.queue_redraw()
	if _dl_build != null: _dl_build.queue_redraw()
	if _dl_grid != null: _dl_grid.queue_redraw()
	if _dl_frustum != null: _dl_frustum.queue_redraw()

func update_viewbox() -> void:
	if host == null or texture_rect == null or viewbox == null:
		return

	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var b := _world_bounds_y_up()
	if b.is_empty():
		return

	var world_w: float = b.w
	var world_h: float = b.h
	if world_w <= 0.0 or world_h <= 0.0:
		return

	var mm_w: float = texture_rect.size.x
	var mm_h: float = texture_rect.size.y

	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size
	var view_w: float = vp_size.x / cam.zoom.x
	var view_h: float = vp_size.y / cam.zoom.y

	var cx: float = cam.position.x
	var cy: float = -cam.position.y

	var left: float = clampf(cx - view_w * 0.5, b.left, b.right)
	var right: float = clampf(cx + view_w * 0.5, b.left, b.right)
	var bottom: float = clampf(cy - view_h * 0.5, b.bottom, b.top)
	var top: float = clampf(cy + view_h * 0.5, b.bottom, b.top)

	var rx0: float = (left - b.left) / world_w * mm_w
	var rx1: float = (right - b.left) / world_w * mm_w

	var ry0: float = (b.top - top) / world_h * mm_h
	var ry1: float = (b.top - bottom) / world_h * mm_h

	viewbox.position = Vector2(rx0, ry0)
	viewbox.size = Vector2(max(2.0, rx1 - rx0), max(2.0, ry1 - ry0))

func is_point_over_minimap(global_pos: Vector2) -> bool:
	if border_panel == null:
		return false
	return border_panel.get_global_rect().has_point(global_pos)

func _world_bounds_y_up() -> Dictionary:
	if host == null:
		return {}

	var wx0: float = float(host.call("_world_left_px"))
	var wx1: float = float(host.call("_world_right_px"))
	var wy0: float = float(host.call("_world_bottom_px"))
	var wy1: float = float(host.call("_world_top_px"))

	var left: float = minf(wx0, wx1)
	var right: float = maxf(wx0, wx1)
	var bottom: float = minf(wy0, wy1)
	var top: float = maxf(wy0, wy1)

	return {
		"left": left,
		"right": right,
		"bottom": bottom,
		"top": top,
		"w": right - left,
		"h": top - bottom,
	}

func _build_nodes() -> void:
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Critical: give it a size BEFORE we ever take viewport.get_texture()
	var mm_size: int = int(cfg.get("size", 256))
	viewport.size = Vector2i(mm_size, mm_size)

	add_child(viewport)

	mini_world = Node2D.new()
	mini_world.name = "MinimapWorld"
	mini_world.scale = Vector2(1.0, -1.0)
	viewport.add_child(mini_world)

	_dl_bg = Node2D.new()
	_dl_bg.name = "MiniBg"
	mini_world.add_child(_dl_bg)
	_dl_bg.connect("draw", Callable(self, "_on_draw_bg").bind(_dl_bg))

	_dl_build = Node2D.new()
	_dl_build.name = "MiniBuild"
	mini_world.add_child(_dl_build)
	_dl_build.connect("draw", Callable(self, "_on_draw_build").bind(_dl_build))

	_dl_grid = Node2D.new()
	_dl_grid.name = "MiniGrid"
	mini_world.add_child(_dl_grid)
	_dl_grid.connect("draw", Callable(self, "_on_draw_grid").bind(_dl_grid))

	_dl_frustum = Node2D.new()
	_dl_frustum.name = "MiniFrustum"
	mini_world.add_child(_dl_frustum)
	_dl_frustum.connect("draw", Callable(self, "_on_draw_frustum").bind(_dl_frustum))

	mini_camera = Camera2D.new()
	mini_camera.enabled = true
	mini_world.add_child(mini_camera)
	mini_camera.make_current()

	layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	border_panel = Panel.new()
	var sb := StyleBoxFlat.new()

	var bg: Color = Color(0, 0, 0, 0.5)
	var vbg: Variant = cfg.get("border_bg")
	if vbg is Color:
		bg = vbg
	sb.bg_color = bg

	var bc: Color = Color(1, 1, 1, 1)
	var vbc: Variant = cfg.get("border_color")
	if vbc is Color:
		bc = vbc
	sb.border_color = bc

	sb.border_width_top = int(cfg.get("border", 4))
	sb.border_width_bottom = int(cfg.get("border", 4))
	sb.border_width_left = int(cfg.get("border", 4))
	sb.border_width_right = int(cfg.get("border", 4))

	border_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(border_panel)

	texture_rect = TextureRect.new()
	texture_rect.texture = viewport.get_texture()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	border_panel.add_child(texture_rect)

	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	border_panel.add_child(overlay)

	viewbox = Panel.new()
	var vb := StyleBoxFlat.new()
	vb.bg_color = Color(0, 0, 0, 0)
	vb.border_width_top = int(cfg.get("viewbox_border", 2))
	vb.border_width_bottom = int(cfg.get("viewbox_border", 2))
	vb.border_width_left = int(cfg.get("viewbox_border", 2))
	vb.border_width_right = int(cfg.get("viewbox_border", 2))

	var vcol: Color = Color(1, 1, 1, 1)
	var vv: Variant = cfg.get("viewbox_color")
	if vv is Color:
		vcol = vv
	vb.border_color = vcol

	viewbox.add_theme_stylebox_override("panel", vb)
	overlay.add_child(viewbox)

	home_btn = Button.new()
	home_btn.text = str(cfg.get("home_text", "Home"))
	home_btn.focus_mode = Control.FOCUS_NONE
	home_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	border_panel.add_child(home_btn)

	# Debug overlay label
	if bool(cfg.get("debug", false)):
		debug_label = Label.new()
		debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		debug_label.add_theme_font_size_override("font_size", int(cfg.get("debug_font_size", 12)))
		debug_label.add_theme_color_override("font_color", cfg.get("debug_color", Color(1, 1, 1, 1)))
		border_panel.add_child(debug_label)

	overlay.gui_input.connect(Callable(self, "_on_gui_input"))
	texture_rect.gui_input.connect(Callable(self, "_on_gui_input"))
	home_btn.pressed.connect(Callable(self, "_on_home_pressed"))

func _on_screen_resized() -> void:
	_relayout()

func _relayout() -> void:
	if host == null or border_panel == null or texture_rect == null or viewport == null:
		return

	var mm_size: int = int(cfg.get("size", 256))
	var border: int = int(cfg.get("border", 4))
	var margin: int = int(cfg.get("margin", 16))

	viewport.size = Vector2i(mm_size, mm_size)
	texture_rect.texture = viewport.get_texture() # critical: keep it bound after resize

	texture_rect.custom_minimum_size = Vector2(mm_size, mm_size)
	texture_rect.size = Vector2(mm_size, mm_size)
	texture_rect.position = Vector2(float(border), float(border))

	overlay.custom_minimum_size = Vector2(mm_size, mm_size)
	overlay.size = Vector2(mm_size, mm_size)
	overlay.position = Vector2(float(border), float(border))

	border_panel.custom_minimum_size = Vector2(mm_size + border * 2, mm_size + border * 2)

	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size
	border_panel.position = Vector2(vp_size.x - border_panel.custom_minimum_size.x - float(margin), float(margin))

	home_btn.custom_minimum_size = Vector2(64, 22)
	home_btn.size = Vector2(64, 22)
	home_btn.position = Vector2(float(border) + 6.0, float(border) + float(mm_size) - 28.0)

	if debug_label != null:
		debug_label.position = Vector2(float(border) + 6.0, float(border) + 6.0)

	_fit_minimap_camera_to_world(mm_size)
	if mini_camera != null:
		mini_camera.make_current()

	update_viewbox()

func _fit_minimap_camera_to_world(mm_size: int) -> void:
	if host == null or mini_camera == null:
		return

	var b := _world_bounds_y_up()
	if b.is_empty() or b.w <= 0.0 or b.h <= 0.0:
		return

	mini_camera.position = Vector2((b.left + b.right) * 0.5, (b.bottom + b.top) * 0.5)

	# Godot zoom: >1 zooms IN, <1 zooms OUT, so we want pixels/world_units here.
	var z_x: float = float(mm_size) / b.w
	var z_y: float = float(mm_size) / b.h
	var fit: float = minf(z_x, z_y) # uniform fit so the whole world is visible

	var mult: float = float(cfg.get("zoom_mult", 1.0))
	mini_camera.zoom = Vector2(fit, fit) * mult

func _on_home_pressed() -> void:
	if host == null:
		return
	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return
	cam.position = Vector2.ZERO
	host.call("_clamp_camera_to_world")
	update_viewbox()

func _on_gui_input(event: InputEvent) -> void:
	if host == null or texture_rect == null:
		return

	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_main_at_mouse(0.9)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_main_at_mouse(1.1)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
			if mb.pressed:
				_set_main_camera_to_mouse()
			return

		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_main_camera_to_mouse()

			var do_toggle: bool = bool(cfg.get("right_click_zoom", true))
			if do_toggle:
				var a: float = float(cfg.get("toggle_zoom_a", 0.8))
				var b2: float = float(cfg.get("toggle_zoom_b", 1.4))
				var mid: float = (a + b2) * 0.5
				var target: float = a if cam.zoom.x > mid else b2

				var minz: float = float(host.get("MIN_ZOOM"))
				var maxz: float = float(host.get("MAX_ZOOM"))
				target = clampf(target, minz, maxz)

				cam.zoom = Vector2(target, target)
				host.call("_clamp_camera_to_world")
			return

	elif event is InputEventMouseMotion and dragging:
		_set_main_camera_to_mouse()

	update_viewbox()

func _set_main_camera_to_mouse() -> void:
	if host == null or texture_rect == null:
		return
	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var mm_pos: Vector2 = texture_rect.get_local_mouse_position()
	var mm_size: Vector2 = texture_rect.size
	if mm_pos.x < 0.0 or mm_pos.y < 0.0 or mm_pos.x > mm_size.x or mm_pos.y > mm_size.y:
		return

	var b := _world_bounds_y_up()
	if b.is_empty() or b.w <= 0.0 or b.h <= 0.0:
		return

	var target_x: float = b.left + (mm_pos.x / mm_size.x) * b.w
	var target_y: float = b.top - (mm_pos.y / mm_size.y) * b.h

	cam.position = Vector2(target_x, -target_y)
	host.call("_clamp_camera_to_world")

func _zoom_main_at_mouse(factor: float) -> void:
	if host == null or texture_rect == null:
		return
	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var mm_pos: Vector2 = texture_rect.get_local_mouse_position()
	var mm_size: Vector2 = texture_rect.size
	if mm_pos.x < 0.0 or mm_pos.y < 0.0 or mm_pos.x > mm_size.x or mm_pos.y > mm_size.y:
		return

	var b := _world_bounds_y_up()
	if b.is_empty() or b.w <= 0.0 or b.h <= 0.0:
		return

	var focus_x: float = b.left + (mm_pos.x / mm_size.x) * b.w
	var focus_y: float = b.top - (mm_pos.y / mm_size.y) * b.h

	var new_zoom: Vector2 = cam.zoom * factor
	var minz: float = float(host.get("MIN_ZOOM"))
	var maxz: float = float(host.get("MAX_ZOOM"))
	var clamped: float = clampf(new_zoom.x, minz, maxz)
	cam.zoom = Vector2(clamped, clamped)

	cam.position = Vector2(focus_x, -focus_y)
	host.call("_clamp_camera_to_world")

func _on_draw_bg(n: Node2D) -> void:
	if host == null:
		return

	var b := _world_bounds_y_up()
	if b.is_empty() or b.w <= 0.0 or b.h <= 0.0:
		return

	var sky_h: float = maxf(0.0, b.top - 0.0)
	if sky_h > 0.0:
		n.draw_rect(Rect2(Vector2(b.left, 0.0), Vector2(b.w, sky_h)), host.SKY_COLOR, true)

	var ground_h: float = maxf(0.0, 0.0 - b.bottom)
	if ground_h > 0.0:
		n.draw_rect(Rect2(Vector2(b.left, b.bottom), Vector2(b.w, ground_h)), host.GROUND_COLOR, true)

func _mm_draw_cell(n: Node2D, cell: Vector2i, color: Color) -> void:
	var cs: int = int(host.CELL_SIZE)
	var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
	n.draw_rect(Rect2(tl, Vector2(float(cs), float(cs))), color, true)

func _mm_draw_elevator(n: Node2D, cell: Vector2i, color: Color) -> void:
	var cs: int = int(host.CELL_SIZE)
	var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
	var w: float = float(cs) * 0.25
	var rect_pos := Vector2(tl.x + (float(cs) - w) * 0.5, tl.y)
	n.draw_rect(Rect2(rect_pos, Vector2(w, float(cs))), color, true)

func _mm_draw_stairs(n: Node2D, cell: Vector2i, color: Color) -> void:
	var cs: int = int(host.CELL_SIZE)
	var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
	var s: float = float(cs)
	n.draw_colored_polygon(PackedVector2Array([tl, tl + Vector2(s, 0), tl + Vector2(0, s)]), color)

func _mm_draw_escalator(n: Node2D, cell: Vector2i, color: Color) -> void:
	var cs: int = int(host.CELL_SIZE)
	var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
	var w: float = float(cs) * 0.6
	var h: float = float(cs) * 0.25
	var pos := Vector2(tl.x + (float(cs) - w) * 0.5, tl.y + (float(cs) - h) * 0.5)
	n.draw_rect(Rect2(pos, Vector2(w, h)), color, true)

func _on_draw_build(n: Node2D) -> void:
	if host == null or build == null:
		return

	for key in build.floors.keys():
		var cell: Vector2i = key
		var c: Color = host.FLOOR_GROUND_COLOR if cell.y == 0 else (host.FLOOR_UP_COLOR if cell.y > 0 else host.FLOOR_DOWN_COLOR)
		_mm_draw_cell(n, cell, c)

	for key_e in build.elevators.keys():
		_mm_draw_elevator(n, key_e, host.ELEVATOR_COLOR)

	for key_s in build.stairs.keys():
		_mm_draw_stairs(n, key_s, host.STAIRS_COLOR)

	for key_u in build.escalators_up.keys():
		_mm_draw_escalator(n, key_u, host.ESCALATOR_UP_COLOR)

	for key_d in build.escalators_down.keys():
		_mm_draw_escalator(n, key_d, host.ESCALATOR_DOWN_COLOR)

	for key_m2 in build.mezz2_cells.keys():
		_mm_draw_cell(n, key_m2, host.MEZZ2_COLOR)

	for key_m3 in build.mezz3_cells.keys():
		_mm_draw_cell(n, key_m3, host.MEZZ3_COLOR)

func _on_draw_grid(n: Node2D) -> void:
	if host == null:
		return

	var b := _world_bounds_y_up()
	if b.is_empty() or b.w <= 0.0 or b.h <= 0.0:
		return

	var cs: float = float(host.CELL_SIZE)

	# --- keep line thickness ~1 screen pixel even when minimap camera is zoomed way out
	var z: float = 1.0
	if mini_camera != null:
		z = mini_camera.zoom.x
	z = maxf(z, 0.0001)
	var line_w: float = 1.0 / z
	var axis_w: float = 1.5 / z

	var grid_col: Color = host.GRID_COLOR
	grid_col.a = float(cfg.get("grid_alpha", 0.25))

	var x: float = floor(b.left / cs) * cs
	while x <= b.right + 0.001:
		n.draw_line(Vector2(x, b.bottom), Vector2(x, b.top), grid_col, line_w)
		x += cs

	var y: float = floor(b.bottom / cs) * cs
	while y <= b.top + 0.001:
		n.draw_line(Vector2(b.left, y), Vector2(b.right, y), grid_col, line_w)
		y += cs

	var show_axis: bool = true
	var axis_v: Variant = host.get("GRID_SHOW_AXIS_LINES")
	if axis_v is bool:
		show_axis = axis_v

	if show_axis:
		var axis_col: Color = host.AXIS_COLOR
		axis_col.a = float(cfg.get("axis_alpha", 0.60))

		if b.left <= 0.0 and 0.0 <= b.right:
			n.draw_line(Vector2(0.0, b.bottom), Vector2(0.0, b.top), axis_col, axis_w)
		if b.bottom <= 0.0 and 0.0 <= b.top:
			n.draw_line(Vector2(b.left, 0.0), Vector2(b.right, 0.0), axis_col, axis_w)

func _on_draw_frustum(n: Node2D) -> void:
	if host == null:
		return

	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size

	# Must match update_viewbox(): world view size = pixels / zoom
	var view_w: float = vp_size.x / cam.zoom.x
	var view_h: float = vp_size.y / cam.zoom.y
	var half: Vector2 = Vector2(view_w, view_h) * 0.5

	# Main camera is in y-down space; minimap is y-up
	var cam_y_up: Vector2 = Vector2(cam.position.x, -cam.position.y)

	var top_left: Vector2 = cam_y_up - half
	var top_right: Vector2 = top_left + Vector2(view_w, 0.0)
	var bottom_left: Vector2 = top_left + Vector2(0.0, view_h)
	var bottom_right: Vector2 = top_left + Vector2(view_w, view_h)

	var fc: Color = Color(1, 0, 0, 1)
	var v: Variant = cfg.get("frustum_color")
	if v is Color:
		fc = v

	n.draw_line(top_left, top_right, fc, 1.5)
	n.draw_line(top_right, bottom_right, fc, 1.5)
	n.draw_line(bottom_right, bottom_left, fc, 1.5)
	n.draw_line(bottom_left, top_left, fc, 1.5)
