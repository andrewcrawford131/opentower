# res://script/minimap.gd
class_name MinimapController
extends Node

# Host (OpenTower). Keep it untyped to avoid circular load issues.
var host: Node = null

# Config passed in from OpenTower
var cfg := {
	"size": 256,
	"margin": 16,
	"frustum_color": Color(1, 0, 0, 1),
	"border": 4,
	"border_bg": Color(0, 0, 0, 0.5),
	"border_color": Color(1, 1, 1, 1),
	"viewbox_border": 2,
	"viewbox_color": Color(1, 1, 1, 1),
	"home_text": "Home",
}

# Nodes
var layer: CanvasLayer
var border_panel: Panel
var viewport: SubViewport
var mini_world: Node2D
var mini_camera: Camera2D
var texture_rect: TextureRect
var overlay: Control
var viewbox: Panel
var home_btn: Button

var dragging := false

# --- Mini draw nodes ---
class MiniBackground:
	extends Node2D
	var host_ref: Node
	func _init(h: Node) -> void:
		host_ref = h
	func _draw() -> void:
		if host_ref == null: return
		var wx0: float = host_ref._world_left_px()
		var wx1: float = host_ref._world_right_px()
		var wy0: float = host_ref._world_bottom_px()
		var wy1: float = host_ref._world_top_px()
		var world_w: float = wx1 - wx0
		# sky (0->top), ground (bottom->0)
		draw_rect(Rect2(Vector2(wx0, 0.0), Vector2(world_w, wy1 - 0.0)), Color(0.62, 0.82, 1.0), true)
		draw_rect(Rect2(Vector2(wx0, wy0), Vector2(world_w, 0.0 - wy0)), Color(0.42, 0.29, 0.14), true)

class MiniBuildLayer:
	extends Node2D
	var host_ref: Node
	func _init(h: Node) -> void:
		host_ref = h

	func _draw_cell(cell: Vector2i, color: Color) -> void:
		var cs: int = host_ref.CELL_SIZE
		var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
		draw_rect(Rect2(tl, Vector2(float(cs), float(cs))), color, true)

	func _draw_elevator(cell: Vector2i, color: Color) -> void:
		var cs: int = host_ref.CELL_SIZE
		var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
		var w := float(cs) * 0.25
		var rect_pos := Vector2(tl.x + (float(cs) - w) * 0.5, tl.y)
		draw_rect(Rect2(rect_pos, Vector2(w, float(cs))), color, true)

	func _draw_stairs(cell: Vector2i, color: Color) -> void:
		var cs: int = host_ref.CELL_SIZE
		var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
		var s := float(cs)
		var poly := PackedVector2Array([tl, tl + Vector2(s, 0), tl + Vector2(0, s)])
		draw_colored_polygon(poly, color)

	func _draw_escalator(cell: Vector2i, color: Color) -> void:
		var cs: int = host_ref.CELL_SIZE
		var tl := Vector2(float(cell.x * cs), float(cell.y * cs))
		var w := float(cs) * 0.6
		var h := float(cs) * 0.25
		var pos := Vector2(tl.x + (float(cs) - w) * 0.5, tl.y + (float(cs) - h) * 0.5)
		draw_rect(Rect2(pos, Vector2(w, h)), color, true)

	func _draw() -> void:
		if host_ref == null: return

		# Floors
		for key in host_ref._floors.keys():
			var cell: Vector2i = key
			var c: Color = host_ref.FLOOR_GROUND_COLOR if (cell.y == 0) else (host_ref.FLOOR_UP_COLOR if (cell.y > 0) else host_ref.FLOOR_DOWN_COLOR)
			_draw_cell(cell, c)

		# Elevators
		for key in host_ref._elevators.keys():
			_draw_elevator(key, host_ref.ELEVATOR_COLOR)

		# Stairs / escalators
		for key in host_ref._stairs.keys():
			_draw_stairs(key, host_ref.STAIRS_COLOR)

		for key in host_ref._escalators_up.keys():
			_draw_escalator(key, host_ref.ESCALATOR_UP_COLOR)
		for key in host_ref._escalators_down.keys():
			_draw_escalator(key, host_ref.ESCALATOR_DOWN_COLOR)

		# Mezz
		for key in host_ref._mezz2_cells.keys():
			_draw_cell(key, host_ref.MEZZ2_COLOR)
		for key in host_ref._mezz3_cells.keys():
			_draw_cell(key, host_ref.MEZZ3_COLOR)

class MiniFrustum:
	extends Node2D
	var host_ref: Node
	func _init(h: Node) -> void:
		host_ref = h
	func _draw() -> void:
		if host_ref == null:
			return

		var cam: Camera2D = host_ref.get("_camera") as Camera2D
		if cam == null:
			return

		var vp_size: Vector2 = host_ref.get_viewport().get_visible_rect().size
		var view_w: float = vp_size.x * cam.zoom.x
		var view_h: float = vp_size.y * cam.zoom.y

		var half: Vector2 = Vector2(view_w, view_h) * 0.5
		var top_left: Vector2 = cam.position - half
		var top_right: Vector2 = top_left + Vector2(view_w, 0.0)
		var bottom_left: Vector2 = top_left + Vector2(0.0, view_h)
		var bottom_right: Vector2 = top_left + Vector2(view_w, view_h)

		var c: Color = Color(1, 0, 0, 1)
		var maybe_c: Variant = host_ref.get("MINIMAP_FRUSTUM_COLOR")
		if maybe_c is Color:
			c = maybe_c

		var th: float = 2.0
		draw_line(top_left, top_right, c, th)
		draw_line(top_right, bottom_right, c, th)
		draw_line(bottom_right, bottom_left, c, th)
		draw_line(bottom_left, top_left, c, th)

# --- Public API ---
func setup(p_host: Node, p_cfg: Dictionary) -> void:
	host = p_host
	for k in p_cfg.keys():
		cfg[k] = p_cfg[k]

	_build_nodes()
	set_process(true)
	_relayout()
	update_viewbox()

	# Follow window resize
	if host != null and host.get_window() != null:
		if not host.get_window().is_connected("size_changed", Callable(self, "_on_screen_resized")):
			host.get_window().connect("size_changed", Callable(self, "_on_screen_resized"))

func update_viewbox() -> void:
	if host == null or texture_rect == null or viewbox == null:
		return

	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var wx0: float = float(host.call("_world_left_px"))
	var wx1: float = float(host.call("_world_right_px"))
	var wy0: float = float(host.call("_world_bottom_px"))
	var wy1: float = float(host.call("_world_top_px"))

	var world_w: float = wx1 - wx0
	var world_h: float = wy1 - wy0
	if world_w <= 0.0 or world_h <= 0.0:
		return

	var mm_w: float = texture_rect.size.x
	var mm_h: float = texture_rect.size.y

	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size
	var view_w: float = vp_size.x * cam.zoom.x
	var view_h: float = vp_size.y * cam.zoom.y

	var cx: float = cam.position.x
	var cy: float = cam.position.y

	var left: float = clampf(cx - view_w * 0.5, wx0, wx1)
	var right: float = clampf(cx + view_w * 0.5, wx0, wx1)
	var bottom: float = clampf(cy - view_h * 0.5, wy0, wy1)
	var top: float = clampf(cy + view_h * 0.5, wy0, wy1)

	var rx0: float = (left - wx0) / world_w * mm_w
	var rx1: float = (right - wx0) / world_w * mm_w

	# y-down in UI: y=0 corresponds to world wy1 (top)
	var ry0: float = (wy1 - top) / world_h * mm_h
	var ry1: float = (wy1 - bottom) / world_h * mm_h

	viewbox.position = Vector2(rx0, ry0)
	viewbox.size = Vector2(max(2.0, rx1 - rx0), max(2.0, ry1 - ry0))

func is_point_over_minimap(global_pos: Vector2) -> bool:
	if border_panel == null: return false
	return border_panel.get_global_rect().has_point(global_pos)

# --- Internals ---
func _process(_delta: float) -> void:
	# Keep viewbox synced and redraw minimap content
	update_viewbox()
	if mini_world != null:
		mini_world.propagate_call("queue_redraw")

func _build_nodes() -> void:
	# SubViewport
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	mini_world = Node2D.new()
	mini_world.name = "MinimapWorld"
	mini_world.scale = Vector2(1, -1) # +Y up like main world
	viewport.add_child(mini_world)

	mini_world.add_child(MiniBackground.new(host))
	mini_world.add_child(MiniBuildLayer.new(host))
	mini_world.add_child(MiniFrustum.new(host))

	mini_camera = Camera2D.new()
	mini_camera.enabled = true
	mini_camera.position = Vector2.ZERO
	viewport.add_child(mini_camera)
	mini_camera.make_current()

	# UI layer
	layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	# Border panel
	border_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = cfg["border_bg"]
	sb.border_width_top = int(cfg["border"])
	sb.border_width_bottom = int(cfg["border"])
	sb.border_width_left = int(cfg["border"])
	sb.border_width_right = int(cfg["border"])
	sb.border_color = cfg["border_color"]
	border_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(border_panel)

	# Texture
	texture_rect = TextureRect.new()
	texture_rect.texture = viewport.get_texture()
	border_panel.add_child(texture_rect)

	# Overlay (captures input)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	border_panel.add_child(overlay)

	# Viewbox outline
	viewbox = Panel.new()
	var vb := StyleBoxFlat.new()
	vb.bg_color = Color(0,0,0,0)
	vb.border_width_top = int(cfg["viewbox_border"])
	vb.border_width_bottom = int(cfg["viewbox_border"])
	vb.border_width_left = int(cfg["viewbox_border"])
	vb.border_width_right = int(cfg["viewbox_border"])
	vb.border_color = cfg["viewbox_color"]
	viewbox.add_theme_stylebox_override("panel", vb)
	overlay.add_child(viewbox)

	# Home button
	home_btn = Button.new()
	home_btn.text = str(cfg["home_text"])
	home_btn.focus_mode = Control.FOCUS_NONE
	home_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	border_panel.add_child(home_btn)

	# Input hooks
	overlay.gui_input.connect(Callable(self, "_on_gui_input"))
	texture_rect.gui_input.connect(Callable(self, "_on_gui_input"))
	home_btn.pressed.connect(Callable(self, "_on_home_pressed"))

func _on_screen_resized() -> void:
	_relayout()

func _relayout() -> void:
	if host == null or border_panel == null or texture_rect == null or viewport == null:
		return

	var mm_size := int(cfg["size"])
	var border := int(cfg["border"])
	var margin := int(cfg["margin"])

	viewport.size = Vector2i(mm_size, mm_size)

	texture_rect.custom_minimum_size = Vector2(mm_size, mm_size)
	texture_rect.size = Vector2(mm_size, mm_size)
	texture_rect.position = Vector2(border, border)

	overlay.custom_minimum_size = Vector2(mm_size, mm_size)
	overlay.size = Vector2(mm_size, mm_size)
	overlay.position = Vector2(border, border)

	border_panel.custom_minimum_size = Vector2(mm_size + border * 2, mm_size + border * 2)

	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size
	border_panel.position = Vector2(vp_size.x - border_panel.custom_minimum_size.x - float(margin), float(margin))

	home_btn.custom_minimum_size = Vector2(64, 22)
	home_btn.size = Vector2(64, 22)
	home_btn.position = Vector2(float(border) + 6.0, float(border) + float(mm_size) - 28.0)

	# Fit minimap camera to world bounds
	var wx0: float = host._world_left_px()
	var wx1: float = host._world_right_px()
	var wy0: float = host._world_bottom_px()
	var wy1: float = host._world_top_px()
	var world_w := wx1 - wx0
	var world_h := wy1 - wy0
	if world_w > 0.0 and world_h > 0.0:
		var zx := float(mm_size) / world_w
		var zy := float(mm_size) / world_h
		mini_camera.zoom = Vector2(zx, zy)
		mini_camera.position = Vector2((wx0 + wx1) * 0.5, (wy0 + wy1) * 0.5)

	update_viewbox()

func _on_home_pressed() -> void:
	if host == null or host._camera == null:
		return
	host._camera.position = Vector2.ZERO
	if host.has_method("_clamp_camera_to_world"):
		host._clamp_camera_to_world()
	update_viewbox()

func _on_gui_input(event: InputEvent) -> void:
	if host == null or host._camera == null or texture_rect == null:
		return

	# Mouse wheel zoom at cursor position
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton

		if mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_main_at_mouse(0.9)
			return
		if mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_main_at_mouse(1.1)
			return

		if mbe.button_index == MOUSE_BUTTON_LEFT or mbe.button_index == MOUSE_BUTTON_RIGHT:
			if mbe.pressed:
				dragging = true
				_set_main_camera_to_mouse()
			else:
				dragging = false

	if event is InputEventMouseMotion and dragging:
		_set_main_camera_to_mouse()

	update_viewbox()

func _set_main_camera_to_mouse() -> void:
	var mm_pos: Vector2 = texture_rect.get_local_mouse_position()
	var mm_size: Vector2 = texture_rect.size
	if mm_pos.x < 0.0 or mm_pos.y < 0.0 or mm_pos.x > mm_size.x or mm_pos.y > mm_size.y:
		return

	var wx0: float = host._world_left_px()
	var wx1: float = host._world_right_px()
	var wy0: float = host._world_bottom_px()
	var wy1: float = host._world_top_px()
	var world_w := wx1 - wx0
	var world_h := wy1 - wy0
	if world_w <= 0.0 or world_h <= 0.0:
		return

	var target_x := wx0 + (mm_pos.x / mm_size.x) * world_w
	var target_y := wy1 - (mm_pos.y / mm_size.y) * world_h

	host._camera.position = Vector2(target_x, target_y)
	if host.has_method("_clamp_camera_to_world"):
		host._clamp_camera_to_world()

func _zoom_main_at_mouse(factor: float) -> void:
	var cam: Camera2D = host.get("_camera") as Camera2D
	if cam == null:
		return

	var mm_pos: Vector2 = texture_rect.get_local_mouse_position()
	var mm_size: Vector2 = texture_rect.size
	if mm_pos.x < 0.0 or mm_pos.y < 0.0 or mm_pos.x > mm_size.x or mm_pos.y > mm_size.y:
		return

	var wx0: float = float(host.call("_world_left_px"))
	var wx1: float = float(host.call("_world_right_px"))
	var wy0: float = float(host.call("_world_bottom_px"))
	var wy1: float = float(host.call("_world_top_px"))
	var world_w: float = wx1 - wx0
	var world_h: float = wy1 - wy0

	var focus_x: float = wx0 + (mm_pos.x / mm_size.x) * world_w
	var focus_y: float = wy1 - (mm_pos.y / mm_size.y) * world_h

	var new_zoom: Vector2 = cam.zoom * factor

	var minz: float = float(host.get("MIN_ZOOM"))
	var maxz: float = float(host.get("MAX_ZOOM"))
	var clamped: float = clampf(new_zoom.x, minz, maxz)
	cam.zoom = Vector2(clamped, clamped)

	cam.position = Vector2(focus_x, focus_y)
	if host.has_method("_clamp_camera_to_world"):
		host.call("_clamp_camera_to_world")
