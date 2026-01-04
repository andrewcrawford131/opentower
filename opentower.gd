# FILE: res://opentower.gd
class_name OpenTower
extends Node2D

# ---- Tunables (edit later in Inspector) ----
@export var BUILD_HEIGHT: int = 64          # cells above ground (y>0)
@export var UNDERGROUND_DEPTH: int = 15     # cells below ground (y<0, positive value)
@export var WORLD_WIDTH: int = 64           # cells left→right
@export var CELL_SIZE: int = 128            # px per cell (grid scale)

const MinimapControllerScript := preload("res://script/minimap.gd")
var _minimap: MinimapController
const TowerRendererScript := preload("res://script/tower_renderer.gd")
var _renderer: TowerRenderer

# ---- Colors ----
@export var SKY_COLOR: Color = Color(0.55, 0.75, 1.0, 1.0)
@export var GROUND_COLOR: Color = Color(0.45, 0.30, 0.12, 1.0)
@export var GRID_COLOR: Color = Color(1, 1, 1, 0.25)
@export var AXIS_COLOR: Color = Color(1, 1, 1, 1)
@export var FLOOR_GROUND_COLOR: Color = Color(0.75, 0.65, 0.50, 1.0)
@export var FLOOR_UP_COLOR: Color = Color(0.70, 0.80, 0.95, 1.0)
@export var FLOOR_DOWN_COLOR: Color = Color(0.55, 0.60, 0.70, 1.0)
@export var ELEVATOR_COLOR: Color = Color(0.95, 0.80, 0.25, 1.0)
@export var STAIRS_COLOR: Color = Color(0.35, 0.85, 0.45, 1.0)
@export var ESCALATOR_COLOR: Color = Color(0.90, 0.55, 0.25, 1.0)
@export var HOVER_OK_COLOR: Color = Color(0.25, 1.0, 0.35, 0.40)
@export var HOVER_BAD_COLOR: Color = Color(1.00, 0.25, 0.25, 0.40)
@export var ESCALATOR_UP_COLOR: Color = Color(0.20, 0.65, 1.00, 1.0)
@export var ESCALATOR_DOWN_COLOR: Color = Color(1.00, 0.55, 0.20, 1.0)
const MEZZ2_COLOR: Color = Color(0.20, 0.70, 1.00, 0.70)  # bright cyan, semi-opaque
const MEZZ3_COLOR: Color = Color(0.60, 0.35, 1.00, 0.70)  # violet, semi-opaque
@export var OFFICE_COLOR: Color = Color(0.20, 0.70, 0.90, 1.0)
@export var APARTMENT_COLOR: Color = Color(0.50, 0.90, 0.50, 1.0)

func _get_cell_size() -> int:
	return CELL_SIZE

# ---- Internal nodes ----
var _camera: Camera2D
var _world: Node2D

# Pure draw layers (no scripts, no inner classes)
var _bg_layer: Node2D
var _build_layer: Node2D
var _grid_layer: Node2D

@export var GRID_SHOW_AXIS_LINES: bool = true

# Hover helpers for build preview
var _hover_cell: Vector2i = Vector2i.ZERO
var _hover_valid: bool = false

# Drag-build (replaces DragOverlay class)
var _drag_building: bool = false
var _drag_a_cell: Vector2i = Vector2i.ZERO
var _drag_b_cell: Vector2i = Vector2i.ZERO

# ---- Minimap config / refs ----
@export var MINIMAP_SIZE: int = 256
@export var MINIMAP_MARGIN: int = 16
@export var MINIMAP_FRUSTUM_COLOR: Color = Color(1, 0, 0, 1)
@export var MINIMAP_BORDER: int = 4
@export var MINIMAP_BORDER_BG: Color = Color(0, 0, 0, 0.5)
@export var MINIMAP_BORDER_COLOR: Color = Color(1, 1, 1, 1)
@export var MINIMAP_VIEWBOX_BORDER: int = 2
@export var MINIMAP_VIEWBOX_COLOR: Color = Color(1, 1, 1, 1)
@export var MINIMAP_HOME_TEXT: String = "Home"

# ---- Camera pan/zoom config ----
@export var PAN_SPEED: float = 800.0
@export var ZOOM_STEP: float = 0.1
@export var MIN_ZOOM: float = 0.25
@export var MAX_ZOOM: float = 3.0

# Public aliases so TowerRenderer can treat OpenTower like TowerBuild for now.
# After you declare: var _floors, _elevators, _stairs, etc...

var floors: Dictionary:
	get:
		return _floors

var elevators: Dictionary:
	get:
		return _elevators

var stairs: Dictionary:
	get:
		return _stairs

var escalators_up: Dictionary:
	get:
		return _escalators_up

var escalators_down: Dictionary:
	get:
		return _escalators_down

var mezz2_cells: Dictionary:
	get:
		return _mezz2_cells

var mezz3_cells: Dictionary:
	get:
		return _mezz3_cells


# ---- Camera pan config ----
const PAN_MOUSE_BUTTONS: Dictionary = {MOUSE_BUTTON_RIGHT: true}
var _is_dragging: bool = false

# ---- World extent helpers (in pixels) ----
func _world_left_px() -> float:
	return -float(WORLD_WIDTH * CELL_SIZE) * 0.5

func _world_right_px() -> float:
	return float(WORLD_WIDTH * CELL_SIZE) * 0.5

func _world_top_px() -> float:
	return float(BUILD_HEIGHT * CELL_SIZE)

func _world_bottom_px() -> float:
	return -float(UNDERGROUND_DEPTH * CELL_SIZE)

func _ready() -> void:
	# Window setup
	var screen_id: int = DisplayServer.window_get_current_screen()
	var size: Vector2i = DisplayServer.screen_get_size(screen_id)
	if size.x > 0 and size.y > 0:
		DisplayServer.window_set_size(size)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")

	# Camera
	_camera = Camera2D.new()
	_camera.position = Vector2.ZERO
	_camera.enabled = true
	add_child(_camera)

	# World container with reversed Y (so +Y is up)
	_world = Node2D.new()
	_world.name = "World"
	_world.scale = Vector2(1, -1)
	add_child(_world)

	# Create layers FIRST
	_bg_layer = Node2D.new()
	_bg_layer.name = "BgLayer"
	_bg_layer.z_index = -10
	_world.add_child(_bg_layer)

	_build_layer = Node2D.new()
	_build_layer.name = "BuildLayer"
	_build_layer.z_index = 5
	_world.add_child(_build_layer)

	_grid_layer = Node2D.new()
	_grid_layer.name = "GridLayer"
	_grid_layer.z_index = 10
	_world.add_child(_grid_layer)

	# NOW create + hook renderer (after layers exist)
	_renderer = TowerRendererScript.new()
	add_child(_renderer)
	_renderer.setup(self, self, _bg_layer, _build_layer, _grid_layer)

	_bg_layer.connect("draw", Callable(_renderer, "draw_background"))
	_grid_layer.connect("draw", Callable(_renderer, "draw_grid"))
	_build_layer.connect("draw", Callable(_renderer, "draw_build"))

	# Minimap, HUD, etc...
	_minimap = MinimapControllerScript.new()
	add_child(_minimap)
	_minimap.setup(self, {
		"size": MINIMAP_SIZE,
		"margin": MINIMAP_MARGIN,
		"frustum_color": MINIMAP_FRUSTUM_COLOR,
		"border": MINIMAP_BORDER,
		"border_bg": MINIMAP_BORDER_BG,
		"border_color": MINIMAP_BORDER_COLOR,
		"viewbox_border": MINIMAP_VIEWBOX_BORDER,
		"viewbox_color": MINIMAP_VIEWBOX_COLOR,
		"home_text": MINIMAP_HOME_TEXT,
	})

	get_window().connect("size_changed", Callable(self, "_on_screen_resized"))
	_init_building()

	_bg_layer.queue_redraw()
	_build_layer.queue_redraw()
	_grid_layer.queue_redraw()

func _on_screen_resized() -> void:
	# …your existing resize logic…
	if is_instance_valid(_hud_layer):
		# pass the same toolbar panel you created in _init_building()
		_layout_hud_helpers(_toolbar_panel)

func _process(delta: float) -> void:
	var move: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.y += 1.0
	if move != Vector2.ZERO:
		_camera.position += move.normalized() * PAN_SPEED * delta
		_clamp_camera_to_world()
		if is_instance_valid(_minimap):
			_minimap.update_viewbox()

	_update_hover_hint()

func _drag_get_mouse_cell() -> Vector2i:
	if has_method("_mouse_to_cell"):
		return call("_mouse_to_cell")
	var p: Vector2 = get_global_mouse_position()
	var cs: int = _get_cell_size()
	return Vector2i(floori(p.x / cs), floori(p.y / cs))

func _drag_rect_from(a: Vector2i, b: Vector2i) -> Rect2i:
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _drag_place_rect(rect: Rect2i) -> void:
	for yy in range(rect.position.y, rect.position.y + rect.size.y):
		for xx in range(rect.position.x, rect.position.x + rect.size.x):
			_drag_place_single(Vector2i(xx, yy))

func _drag_place_single(cell: Vector2i) -> void:
	_attempt_build(cell)

func _mouse_to_cell() -> Vector2i:
	var local: Vector2 = _world.to_local(get_global_mouse_position())
	return _world_to_cell(local)

func _unhandled_input(event: InputEvent) -> void:
	# Hover + drag pan
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		# Update hover preview first
		if is_instance_valid(_world) and has_method("_world_to_cell"):
			var local: Vector2 = _world.to_local(get_global_mouse_position())
			_hover_cell = _world_to_cell(local)
			_hover_valid = _can_build(_tool, _hover_cell)
			if has_method("_can_build"):
				_hover_valid = _can_build(_tool, _hover_cell)
						# Update drag-build rectangle
			if _drag_building:
				_drag_b_cell = _mouse_to_cell()
				if is_instance_valid(_build_layer):
					_build_layer.queue_redraw()
		# Pan while dragging
		if _is_dragging:
			_camera.position -= mm.relative
			_clamp_camera_to_world()
			if is_instance_valid(_minimap):
				_minimap.update_viewbox()

	# Mouse buttons (pan toggle, wheel zoom, left-click build)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		# Start/stop drag panning
		if PAN_MOUSE_BUTTONS.has(mb.button_index):
			_is_dragging = mb.pressed
		# Wheel zoom
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.0 - ZOOM_STEP)  # zoom in
			return
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 + ZOOM_STEP)  # zoom out
			return
		# Build on LMB
				# Build drag (LMB) - replaces DragOverlay class
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_building = true
				_drag_a_cell = _mouse_to_cell()
				_drag_b_cell = _drag_a_cell
				if is_instance_valid(_build_layer):
					_build_layer.queue_redraw()
			else:
				if _drag_building:
					_drag_building = false
					var rect := _drag_rect_from(_drag_a_cell, _drag_b_cell)
					_drag_place_rect(rect) # places via _attempt_build()
					if is_instance_valid(_build_layer):
						_build_layer.queue_redraw()
			return

	# Keyboard (zoom, fullscreen, escape)
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode in [KEY_PLUS, KEY_KP_ADD]:
				_zoom_by(1.0 - ZOOM_STEP)
			elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
				_zoom_by(1.0 + ZOOM_STEP)
			elif k.keycode == KEY_F11:
				var win: Window = get_window()
				if win.mode == Window.MODE_WINDOWED:
					win.mode = Window.MODE_FULLSCREEN
				else:
					win.mode = Window.MODE_WINDOWED
				_on_screen_resized()
			elif k.keycode == KEY_ESCAPE:
				var win2: Window = get_window()
				if win2.mode == Window.MODE_FULLSCREEN or win2.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
					win2.mode = Window.MODE_WINDOWED

	if event is InputEventKey and event.pressed and not event.echo:
		var ctrl: bool = event.ctrl_pressed
		if ctrl and event.keycode == KEY_S:
			var _ok: bool = save_game(_save_slot)
		elif ctrl and event.keycode == KEY_L:
			var _ok2: bool = load_game(_save_slot)
		elif event.keycode == KEY_1:
			_save_slot = 0
			_update_slot_info()
			_show_toast("Slot 1")
		elif event.keycode == KEY_2:
			_save_slot = 1
			_update_slot_info()
			_show_toast("Slot 2")
		elif event.keycode == KEY_3:
			_save_slot = 2
			_update_slot_info()
			_show_toast("Slot 3")

func _camera_half_view() -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(vp.x * _camera.zoom.x, vp.y * _camera.zoom.y) * 0.5

func _clamp_camera_to_world() -> void:
	var half: Vector2 = _camera_half_view()
	var left: float = _world_left_px() + half.x
	var right: float = _world_right_px() - half.x
	# X is regular
	var pos: Vector2 = _camera.position
	if left <= right:
		pos.x = clamp(pos.x, left, right)

	# Y is inverted because the world Node2D has scale.y = -1.
	var top_g: float = -_world_top_px()      # local +Y (up) becomes global negative
	var bottom_g: float = -_world_bottom_px() # local -Y (down) becomes global positive
	var min_y: float = top_g + half.y        # camera cannot go above this
	var max_y: float = bottom_g - half.y     # camera cannot go below this

	if min_y <= max_y:
		pos.y = clamp(pos.y, min_y, max_y)

	_camera.position = pos

func _zoom_by(factor: float) -> void:
	var z: Vector2 = _camera.zoom
	z *= factor
	var clamped: float = clamp(z.x, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(clamped, clamped)
	_clamp_camera_to_world()
	if is_instance_valid(_minimap):
		_minimap.update_viewbox()

# ---- Inner classes (kept here to avoid separate scripts) ----
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_instance_valid(_bg_layer):
			_bg_layer.queue_redraw()
		if is_instance_valid(_build_layer):
			_build_layer.queue_redraw()
		if is_instance_valid(_grid_layer):
			_grid_layer.queue_redraw()

# ---- Building system (floors & elevator) ----

enum BuildTool { FLOORS, MEZZ2, MEZZ3, ELEVATOR, STAIRS, ESCALATOR_UP, ESCALATOR_DOWN, OFFICE, APARTMENT, DEMOLISH }

var _tool: int = BuildTool.FLOORS
var _floors: Dictionary = {}     # keys: Vector2i(x,y)
var _elevators: Dictionary = {}  # keys: Vector2i(x,y)
var _hud_layer: CanvasLayer
var _stairs: Dictionary = {}      # key: Vector2i(x,y)
var _escalators: Dictionary = {}  # key: Vector2i(x,y)
var _escalators_up: Dictionary = {}    # key: Vector2i
var _escalators_down: Dictionary = {}  # key: Vector2i
var _mezz2_cells: Dictionary = {}      # all cells covered by any Mezz-2
var _mezz3_cells: Dictionary = {}      # all cells covered by any Mezz-3
var _mezz_reserved: Dictionary = {}    # cells where Floors are disallowed due to mezz
var _offices: Dictionary = {}          # office units on floors
var _apartments: Dictionary = {}       # apartment units on floors
var _hud_hint_label: Label
var _hud_tool_chip: Label
var _toolbar_panel: Control

func _init_building() -> void:
	# HUD: top toolbar
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_color = Color(1, 1, 1, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 8)
	_hud_layer.add_child(panel)
	_toolbar_panel = panel

	var row := HBoxContainer.new()

	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	_hud_add_btn(row, "Floors", Callable(self, "_on_tool_floors"))
	# New: Mezz menu (dropdown: Mezz 2 / Mezz 3)
	var mezz_btn := MenuButton.new()
	mezz_btn.text = "Mezz"
	mezz_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(mezz_btn)
	var mezz_menu := mezz_btn.get_popup()
	mezz_menu.clear()
	mezz_menu.add_item("Mezz 2", 2)
	mezz_menu.add_item("Mezz 3", 3)
	if not mezz_menu.is_connected("id_pressed", Callable(self, "_on_mezz_menu_id_pressed")):
		mezz_menu.connect("id_pressed", Callable(self, "_on_mezz_menu_id_pressed"))
	_hud_add_btn(row, "Elevator", Callable(self, "_on_tool_elevator"))
	_hud_add_btn(row, "Stairs", Callable(self, "_on_tool_stairs"))
	_hud_add_btn(row, "Esc Up", Callable(self, "_on_tool_escalator_up"))
	_hud_add_btn(row, "Esc Down", Callable(self, "_on_tool_escalator_down"))

	# Tenants
	_hud_add_btn(row, "Office", Callable(self, "_on_tool_office"))
	_hud_add_btn(row, "Apartment", Callable(self, "_on_tool_apartment"))

	_hud_add_btn(row, "Demolish", Callable(self, "_on_tool_demolish"))

	_nudge_tools_row(row)
	_build_save_hud()
	_setup_autosave()
	_update_slot_info()

	_tool = BuildTool.FLOORS
	
	_ensure_hint_bar()

	var msg: String = _why_blocked(_tool, _hover_cell)
	_hover_hint_label.text = msg
	_hover_hint_label.visible = msg != ""

	# Tiny status chip with the current tool
	_hud_tool_chip = Label.new()
	_hud_tool_chip.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0, 1.0))
	_hud_tool_chip.add_theme_font_size_override("font_size", 14)
	_hud_layer.add_child(_hud_tool_chip)

	await get_tree().process_frame  # ensure panel has size before positioning
	var panel_pos := panel.position
	var panel_size := panel.size
	# Chip to the right of the toolbar; hint just below the toolbar
	if is_instance_valid(_hud_tool_chip):
		_hud_tool_chip.position = Vector2(panel_pos.x + panel_size.x + 12.0, panel_pos.y + 2.0)

	if is_instance_valid(_hud_hint_label):
		_hud_hint_label.position = Vector2(panel_pos.x, panel_pos.y + panel_size.y + 8.0)

	_update_tool_chip()
	await get_tree().process_frame
	_layout_hud_helpers(_toolbar_panel)

func _on_save() -> void:
	save_game(_save_slot)

func _on_load() -> void:
	load_game(_save_slot)

func _on_slot_1() -> void:
	_save_slot = 0
	_show_toast("Slot 1")

func _on_slot_2() -> void:
	_save_slot = 1
	_show_toast("Slot 2")

func _on_slot_3() -> void:
	_save_slot = 2
	_show_toast("Slot 3")

func _on_slot_changed(index: int) -> void:
	_save_slot = clamp(index, 0, SAVE_SLOTS.size() - 1)
	_update_slot_info()
	_show_toast("Slot " + str(_save_slot + 1))

func _slot_timestamp(slot: int) -> String:
	var path: String = SAVE_SLOTS[clamp(slot, 0, SAVE_SLOTS.size() - 1)]
	if not FileAccess.file_exists(path):
		return "Empty"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Error"
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		return "Error"
	var data: Dictionary = parsed
	if not data.has("meta") or not (data.meta is Dictionary):
		return "No meta"
	if not data.meta.has("timestamp"):
		return "No time"
	var ts := int(data.meta.timestamp)
	return Time.get_datetime_string_from_unix_time(ts, true)

func _update_slot_info() -> void:
	var tools_parent: Control = _get_tools_parent()
	if tools_parent == null:
		return
	var row_save := tools_parent.get_child(0)
	if not (row_save is HBoxContainer):
		return
	var slot_info := row_save.get_node_or_null("SlotInfo")
	if slot_info == null:
		return
	var ts := _slot_timestamp(_save_slot)
	slot_info.text = "(" + ts + ")"

func _get_tools_parent() -> Control:
	# Row container lives under the toolbar panel created in _init_building.
	return _toolbar_panel

func _ensure_hint_bar() -> void:
	if _hover_hint_label != null:
		return
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 50
	add_child(_hint_layer)

	_hint_panel = PanelContainer.new()
	_hint_panel.name = "HintBar"
	_hint_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	_hint_panel.position = Vector2(32, 108)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 0, 0.85)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_hint_panel.add_theme_stylebox_override("panel", sb)
	_hint_layer.add_child(_hint_panel)

	_hover_hint_label = Label.new()
	_hover_hint_label.text = ""
	_hover_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hover_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hover_hint_label.add_theme_color_override("font_color", Color(0, 0, 0))
	_hover_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_panel.add_child(_hover_hint_label)

var _autosave_timer: Timer = null
var AUTOSAVE_SECONDS: float = 60.0

func _setup_autosave() -> void:
	if _autosave_timer != null:
		return
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.one_shot = false
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(Callable(self, "_on_autosave_timeout"))

	var tree := get_tree()
	if tree.has_signal("about_to_quit"):
		tree.connect("about_to_quit", Callable(self, "_on_about_to_quit"))
	else:
		var root: Window = tree.root
		if not root.is_connected("close_requested", Callable(self, "_on_main_close")):
			root.close_requested.connect(Callable(self, "_on_main_close"))

func _on_about_to_quit() -> void:
	save_game(_save_slot)

func _on_main_close() -> void:
	save_game(_save_slot)

func _nudge_tools_row(row: HBoxContainer) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(32, 1)
	row.add_child(spacer)
	row.move_child(spacer, 0)
	
var _save_hud_layer: CanvasLayer = null
var _save_row: HBoxContainer = null

func _build_save_hud() -> void:
	if _save_hud_layer != null:
		_position_save_hud()
		return

	_save_hud_layer = CanvasLayer.new()
	_save_hud_layer.layer = 10
	add_child(_save_hud_layer)

	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 8)
	_save_hud_layer.add_child(_save_row)

	var lbl_save: Label = Label.new()
	lbl_save.text = "Save & Load"
	_save_row.add_child(lbl_save)

	var slot_dd: OptionButton = OptionButton.new()
	slot_dd.add_item("Slot 1", 0)
	slot_dd.add_item("Slot 2", 1)
	slot_dd.add_item("Slot 3", 2)
	slot_dd.selected = _save_slot
	slot_dd.item_selected.connect(Callable(self, "_on_slot_changed"))
	_save_row.add_child(slot_dd)

	var slot_info: Label = Label.new()
	slot_info.name = "SlotInfo"
	slot_info.text = ""
	_save_row.add_child(slot_info)

	_hud_add_btn(_save_row, "Save", Callable(self, "_on_save"))
	_hud_add_btn(_save_row, "Load", Callable(self, "_on_load"))

	get_tree().root.size_changed.connect(_position_save_hud)
	call_deferred("_position_save_hud")

func _position_save_hud() -> void:
	if _save_row == null:
		return
	var vp: Vector2i = get_viewport().get_visible_rect().size
	var size: Vector2 = _save_row.get_minimum_size()
	var pos := Vector2(float(vp.x) - size.x - 16.0, float(vp.y) - size.y - 16.0)
	_save_row.position = pos

func _layout_hud_helpers(toolbar: Control) -> void:
	if not is_instance_valid(toolbar) or not is_instance_valid(_hud_hint_label):
		return
	await get_tree().process_frame  # ensure sizes are valid

	var pos := toolbar.position
	var size := toolbar.size
	_hud_hint_label.position = Vector2(pos.x, pos.y + size.y + 8.0)

	_update_hover_hint()

func _on_tool_floors() -> void:
	_tool = BuildTool.FLOORS
	_update_tool_chip()

func _update_hover_hint() -> void:
	_ensure_hint_bar()
	var msg: String = ""
	if _in_bounds(_hover_cell) and not _hover_valid:
		msg = _why_blocked(_tool, _hover_cell)
	_hover_hint_label.text = msg
	_hover_hint_label.visible = msg != ""

func _on_mezz_menu_id_pressed(id: int) -> void:
	if id == 2:
		_tool = BuildTool.MEZZ2
	elif id == 3:
		_tool = BuildTool.MEZZ3
	_update_tool_chip()

func _on_tool_stairs() -> void:
	_tool = BuildTool.STAIRS
	_update_tool_chip()
	
func _on_tool_escalator_up() -> void:
	_tool = BuildTool.ESCALATOR_UP
	_update_tool_chip()

func _on_tool_escalator_down() -> void:
	_tool = BuildTool.ESCALATOR_DOWN
	_update_tool_chip()

func _on_tool_elevator() -> void:
	_tool = BuildTool.ELEVATOR
	_update_tool_chip()

func _on_tool_office() -> void:
	_tool = BuildTool.OFFICE
	_update_tool_chip()

func _on_tool_apartment() -> void:
	_tool = BuildTool.APARTMENT
	_update_tool_chip()

func _on_tool_demolish() -> void:
	_tool = BuildTool.DEMOLISH
	_update_tool_chip()

var _toast_label: Label = null
var _toast_timer: Timer = null
var _hint_layer: CanvasLayer = null
var _hint_panel: PanelContainer = null
var _hover_hint_label: Label = null

func _ensure_toast_nodes() -> void:
	if _toast_label != null and _toast_timer != null:
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	_toast_label = Label.new()
	_toast_label.visible = false
	_toast_label.text = ""
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_top = 1.0
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast_label.position = Vector2(0, -24)

	layer.add_child(_toast_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 1.5
	layer.add_child(_toast_timer)
	_toast_timer.timeout.connect(Callable(self, "_on_toast_timeout"))

func _show_toast(msg: String) -> void:
	_ensure_toast_nodes()
	_toast_label.text = msg
	_toast_label.visible = true
	_toast_timer.start()

func _update_tool_chip() -> void:
	if not is_instance_valid(_hud_tool_chip):
		return
	var tool_label := ""
	match _tool:
		BuildTool.FLOORS:
			tool_label = "Floors"
		BuildTool.MEZZ2:
			tool_label = "Mezz 2"
		BuildTool.MEZZ3:
			tool_label = "Mezz 3"
		BuildTool.ELEVATOR:
			tool_label = "Elevator"
		BuildTool.STAIRS:
			tool_label = "Stairs"
		BuildTool.ESCALATOR_UP:
			tool_label = "Esc Up"
		BuildTool.ESCALATOR_DOWN:
			tool_label = "Esc Down"
		BuildTool.OFFICE:
			tool_label = "Office"
		BuildTool.APARTMENT:
			tool_label = "Apartment"
		BuildTool.DEMOLISH:
			tool_label = "Demolish"
		_:
			tool_label = "?"
	_hud_tool_chip.text = "Tool: " + tool_label

func _hud_add_btn(row: HBoxContainer, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	row.add_child(b)
	if not b.is_connected("pressed", cb):
		b.connect("pressed", cb)

func _world_to_cell(local: Vector2) -> Vector2i:
	# Round to nearest column/level centered on grid lines.
	var cx: int = int(floor(local.x / float(CELL_SIZE)))
	var cy: int = int(floor(local.y / float(CELL_SIZE)))
	return Vector2i(cx, cy)

func _in_bounds(cell: Vector2i) -> bool:
	var half_w: int = WORLD_WIDTH >> 1
	return (cell.x >= -half_w and cell.x <= half_w - 1
		and cell.y >= -UNDERGROUND_DEPTH and cell.y <= BUILD_HEIGHT)

func _update_hint_label(cell: Vector2i, ok: bool) -> void:
	if not is_instance_valid(_hover_hint_label):
		return
	var msg := "" if ok else _why_blocked(_tool, cell)
	_hover_hint_label.text = msg
	_hover_hint_label.visible = msg != ""

func _why_blocked(tool: int, cell: Vector2i) -> String:
	if not _in_bounds(cell):
		return "Out of bounds"

	match tool:
		BuildTool.FLOORS:
			if _floors.has(cell):
				return "Already a floor"

			if _mezz_reserved.has(cell):
				return "Blocked: mezz footprint"

			var above := Vector2i(cell.x, cell.y + 1)
			if _stairs.has(above) or _escalators_down.has(above) or _elevators.has(above):
				return ""

			if cell.y == 0:
				return "Ground blocked by mezz" if _any_mezz_on_ground() else ""

			if cell.y < 0:
				var support_above := _floors.has(above) or _mezz2_cells.has(above) or _mezz3_cells.has(above)
				if not support_above:
					return "Needs support above (floor or mezz)"
				var adj_und := _floors.has(Vector2i(cell.x - 1, cell.y)) or _floors.has(Vector2i(cell.x + 1, cell.y))
				var vertical_above := _stairs.has(above) or _escalators_down.has(above) or _elevators.has(above)
				var elev_here_und := _elevators.has(cell)
				return "" if (adj_und or vertical_above or elev_here_und) else "Needs adjacent floor or vertical above"

			var below := Vector2i(cell.x, cell.y - 1)
			var support_below := _floors.has(below) or _mezz2_cells.has(below) or _mezz3_cells.has(below)
			if not support_below:
				return "Needs support below (floor or mezz)"

			var adj2 := _floors.has(Vector2i(cell.x - 1, cell.y)) or _floors.has(Vector2i(cell.x + 1, cell.y))
			var vertical_below := _stairs.has(below) or _escalators_up.has(below)
			var elevator_here := _elevators.has(cell)

			if _mezz2_cells.has(below) or _mezz3_cells.has(below):
				return "" if (adj2 or vertical_below or elevator_here) else "Needs adjacent floor or stairs/esc-up below or elevator here"

			return "" if (adj2 or vertical_below or elevator_here) else "Needs adjacent floor or vertical access"

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span: int
			if tool == BuildTool.MEZZ2:
				span = 2
			else:
				span = 3

			# Mezz can only be placed at ground.
			if cell.y != 0:
				return "Mezz can only be built at ground"

			# Global exclusivity message.
			if tool == BuildTool.MEZZ2 and _mezz3_cells.size() > 0:
				return "Conflicts with existing Mezz-3"
			if tool == BuildTool.MEZZ3 and _mezz2_cells.size() > 0:
				return "Conflicts with existing Mezz-2"

			# Ground footprint must be free of floors.
			for i in range(span):
				var c2: Vector2i = Vector2i(cell.x, cell.y + i)
				if _floors.has(c2):
					return "Occupied by floor"

			return ""

		BuildTool.OFFICE:
			if not _floors.has(cell):
				return "Office requires a floor"
			if _elevators.has(cell) or _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell):
				return "Occupied by vertical"
			if _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
				return "Occupied by mezzanine"
			if _apartments.has(cell):
				return "Occupied by apartment"
			return ""

		BuildTool.APARTMENT:
			if not _floors.has(cell):
				return "Apartment requires a floor"
			if _elevators.has(cell) or _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell):
				return "Occupied by vertical"
			if _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
				return "Occupied by mezzanine"
			if _offices.has(cell):
				return "Occupied by office"
			return ""

		BuildTool.ELEVATOR, BuildTool.STAIRS, BuildTool.ESCALATOR_UP, BuildTool.ESCALATOR_DOWN:
			if not _floors.has(cell):
				return "Requires a floor"
			if _elevators.has(cell) or _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell):
				return "Occupied"
			return ""

		BuildTool.DEMOLISH:
			# Tenants first
			if _offices.has(cell) or _apartments.has(cell):
				return ""  # allowed

			# Verticals next
			if _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell):
				return ""  # allowed

			# Floors / Elevator / Mezz blocked if a floor exists above
			var above := Vector2i(cell.x, cell.y + 1)
			if _floors.has(above):
				return "Blocked: floor above"

			if _floors.has(cell) or _elevators.has(cell):
				return ""  # allowed now (no floor above)

			# Mezz: check full span; if a floor exists above the top of mezz, block
			if _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
				var mezz_cells := _mezz_demolish_cells(cell)
				var top_y := mezz_cells[mezz_cells.size() - 1].y
				if _floors.has(Vector2i(cell.x, top_y + 1)):
					return "Blocked: floor above mezz"
				return ""  # allowed

	return "Nothing here to demolish"

func _mezz_span_height(cell: Vector2i) -> int:
	# Returns 3 if the next 3 cells in this column are mezz3; 2 for mezz2; else 1.
	var x := cell.x
	var y := cell.y
	if _mezz3_cells.has(Vector2i(x, y)) and _mezz3_cells.has(Vector2i(x, y + 1)) and _mezz3_cells.has(Vector2i(x, y + 2)):
		return 3
	if _mezz2_cells.has(Vector2i(x, y)) and _mezz2_cells.has(Vector2i(x, y + 1)):
		return 2
	return 1

func _column_mezz_span(x: int) -> int:
	# Return mezz span by column, regardless of hovered Y.
	for k in _mezz3_cells.keys():
		if k.x == x:
			return 3
	for k in _mezz2_cells.keys():
		if k.x == x:
			return 2
	return 1

# Collect continuous vertical segment (same dict) through this cell.
func _collect_contiguous(dict: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var x := cell.x
	var y := cell.y
	# go down
	while dict.has(Vector2i(x, y - 1)):
		y -= 1
	var out: Array[Vector2i] = []
	# go up and collect
	var yy := y
	while dict.has(Vector2i(x, yy)):
		out.append(Vector2i(x, yy))
		yy += 1
	return out

# Return all cells that would be demolished for a click at `cell`.
# Groups: tenants (single), verticals (group), mezz (span), floors (single), elevator (group), esc-down (single).
func _demolish_target_cells(cell: Vector2i) -> Array[Vector2i]:
	# Tenants
	if _offices.has(cell) or _apartments.has(cell):
		return [cell]

	# Verticals (stairs / esc-up delete as a group)
	if _stairs.has(cell):
		return _collect_contiguous(_stairs, cell)
	if _escalators_up.has(cell):
		return _collect_contiguous(_escalators_up, cell)
	if _escalators_down.has(cell):
		return [cell]  # always 1

	# Mezz (full span)
	if _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
		return _mezz_demolish_cells(cell)

	# Elevator (group)
	if _elevators.has(cell):
		return _collect_contiguous(_elevators, cell)

	# Floors or empty
	if _floors.has(cell):
		return [cell]
	return []

# Returns all cells to demolish when targeting a mezz column from any of its tiles.
func _mezz_demolish_cells(cell: Vector2i) -> Array[Vector2i]:
	var x := cell.x
	var y := cell.y
	# Walk down to the lowest mezz tile in this contiguous column segment.
	while _mezz2_cells.has(Vector2i(x, y - 1)) or _mezz3_cells.has(Vector2i(x, y - 1)):
		y -= 1
	var cells: Array[Vector2i] = []

	# Full mezz-3 span
	if _mezz3_cells.has(Vector2i(x, y)) and _mezz3_cells.has(Vector2i(x, y + 1)) and _mezz3_cells.has(Vector2i(x, y + 2)):
		cells.append(Vector2i(x, y))
		cells.append(Vector2i(x, y + 1))
		cells.append(Vector2i(x, y + 2))
		return cells

	# Full mezz-2 span
	if _mezz2_cells.has(Vector2i(x, y)) and _mezz2_cells.has(Vector2i(x, y + 1)):
		cells.append(Vector2i(x, y))
		cells.append(Vector2i(x, y + 1))
		return cells

	# Not on mezz; return just the clicked cell.
	cells.append(cell)
	return cells

@export var STAIRS_SPAN: int = 2
@export var ESCALATOR_SPAN: int = 2

func _any_mezz_on_ground() -> bool:
	for k in _mezz2_cells.keys():
		if k.y == 0:
			return true
	for k in _mezz3_cells.keys():
		if k.y == 0:
			return true
	return false

func _any_floor_on_ground() -> bool:
	for k in _floors.keys():
		if k.y == 0:
			return true
	return false

func _any_mezz2_on_ground() -> bool:
	for k in _mezz2_cells.keys():
		if k.y == 0:
			return true
	return false

func _any_mezz3_on_ground() -> bool:
	for k in _mezz3_cells.keys():
		if k.y == 0:
			return true
	return false

func _can_build(tool: int, cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false

	match tool:
		BuildTool.FLOORS:
			# No mezz rows / no floor double-stack
			if _mezz_reserved.has(cell) or _floors.has(cell):
				return false

			# Build-down: stairs OR esc-down OR elevator directly ABOVE allows this floor
			var above := Vector2i(cell.x, cell.y + 1)
			if _stairs.has(above) or _escalators_down.has(above) or _elevators.has(above):
				return true

			# Ground rule
			if cell.y == 0:
				return not _any_mezz_on_ground()

			# ===== Underground branch (y < 0) =====
			if cell.y < 0:
				var support_above := _floors.has(above) or _mezz2_cells.has(above) or _mezz3_cells.has(above)
				if not support_above:
					return false

				var adj_und := _floors.has(Vector2i(cell.x - 1, cell.y)) or _floors.has(Vector2i(cell.x + 1, cell.y))
				var vertical_above := _stairs.has(above) or _escalators_down.has(above) or _elevators.has(above)
				var elev_here_und := _elevators.has(cell) # floors may co-exist with elevator
				return adj_und or vertical_above or elev_here_und

			# ===== Above-ground branch (y > 0) =====
			var below := Vector2i(cell.x, cell.y - 1)
			var support_below := _floors.has(below) or _mezz2_cells.has(below) or _mezz3_cells.has(below)
			if not support_below:
				return false

			var adj2 := _floors.has(Vector2i(cell.x - 1, cell.y)) or _floors.has(Vector2i(cell.x + 1, cell.y))
			var vertical_below := _stairs.has(below) or _escalators_up.has(below)
			var elevator_here := _elevators.has(cell)

			# If you want special mezz behavior later, keep this block; bool still required.
			if _mezz2_cells.has(below) or _mezz3_cells.has(below):
				return adj2 or vertical_below or elevator_here

			return adj2 or vertical_below or elevator_here

		BuildTool.ELEVATOR:
			return not _elevators.has(cell) and not _stairs.has(cell) and not _escalators_up.has(cell) and not _escalators_down.has(cell)

		# STAIRS: span matches column mezz; allowed on FLOOR or MEZZ
		BuildTool.STAIRS:
			var h: int = _mezz_span_height(cell)
			for i in range(h):
				var c := Vector2i(cell.x, cell.y + i)
				# support: floor OR mezz
				if not (_floors.has(c) or _mezz2_cells.has(c) or _mezz3_cells.has(c)):
					return false
				# cannot overlap other verticals
				if _elevators.has(c) or _stairs.has(c) or _escalators_up.has(c) or _escalators_down.has(c):
					return false
			return true

		BuildTool.ESCALATOR_UP:
			var h: int = _mezz_span_height(cell)
			for i in range(h):
				var c := Vector2i(cell.x, cell.y + i)
				if not (_floors.has(c) or _mezz2_cells.has(c) or _mezz3_cells.has(c)):
					return false
				if _elevators.has(c) or _stairs.has(c) or _escalators_up.has(c) or _escalators_down.has(c):
					return false
			return true

		BuildTool.ESCALATOR_DOWN:
			var h: int = 1  # always one tile
			for i in range(h):
				var c := Vector2i(cell.x, cell.y + i)
				if not (_floors.has(c) or _mezz2_cells.has(c) or _mezz3_cells.has(c)):
					return false
				if _elevators.has(c) or _stairs.has(c) or _escalators_up.has(c) or _escalators_down.has(c):
					return false
			return true

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span: int
			if tool == BuildTool.MEZZ2:
				span = 2
			else:
				span = 3

			# Only allowed starting at ground.
			if cell.y != 0:
				return false

			# Global exclusivity: if one mezz exists anywhere, block the other.
			if tool == BuildTool.MEZZ2 and _mezz3_cells.size() > 0:
				return false
			if tool == BuildTool.MEZZ3 and _mezz2_cells.size() > 0:
				return false

			# Any ground floor forbids mezz on ground.
			for k in _floors.keys():
				if k.y == 0:
					return false

			# Footprint must be empty of floors at ground.
			for i in range(span):
				var c: Vector2i = Vector2i(cell.x, cell.y + i)
				if _floors.has(c):
					return false

			# Do not overlap existing mezz in the span.
			for i in range(span):
				var c_check := Vector2i(cell.x, cell.y + i)
				if _mezz2_cells.has(c_check) or _mezz3_cells.has(c_check):
					return false

			return true

		BuildTool.OFFICE, BuildTool.APARTMENT:
			if not _floors.has(cell):
				return false
			# cannot overlap verticals or mezz or each other
			if _elevators.has(cell) or _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell) or _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
				return false
			if (tool == BuildTool.OFFICE and _offices.has(cell)) or (tool == BuildTool.APARTMENT and _apartments.has(cell)):
				return false
			if (tool == BuildTool.OFFICE and _apartments.has(cell)) or (tool == BuildTool.APARTMENT and _offices.has(cell)):
				return false
			return true

		BuildTool.DEMOLISH:
			return _floors.has(cell) or _elevators.has(cell) or _stairs.has(cell) or _escalators_up.has(cell) or _escalators_down.has(cell) or _mezz2_cells.has(cell) or _mezz3_cells.has(cell) or _offices.has(cell) or _apartments.has(cell)

	return false

func _attempt_build(cell: Vector2i) -> void:
	if not _in_bounds(cell):
		return

	match _tool:
		BuildTool.FLOORS:
			# Belt-and-braces: never stamp a floor into mezz footprint rows.
			if _can_build(_tool, cell):
				_floors[cell] = true

		BuildTool.ELEVATOR:
			if _can_build(_tool, cell):
				var h := _mezz_span_height(cell)  # 2/3 only when placed on mezz; 1 on floors
				for i in range(h):
					var c := Vector2i(cell.x, cell.y + i)
					_elevators[c] = true

		BuildTool.STAIRS:
			if _can_build(_tool, cell):
				var h := _mezz_span_height(cell)  # 2/3 only on mezz; 1 on floors
				for i in range(h):
					var c := Vector2i(cell.x, cell.y + i)
					_stairs[c] = true

		BuildTool.ESCALATOR_UP:
			if _can_build(_tool, cell):
				var h: int = _mezz_span_height(cell)  # 2/3 only on mezz; 1 on floors
				for i in range(h):
					var c := Vector2i(cell.x, cell.y + i)
					_escalators_up[c] = true

		BuildTool.ESCALATOR_DOWN:
			if _can_build(_tool, cell):
				var h: int = 1  # always one tile, even on mezz
				for i in range(h):
					var c := Vector2i(cell.x, cell.y + i)
					_escalators_down[c] = true

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span: int
			if _tool == BuildTool.MEZZ2:
				span = 2
			else:
				span = 3

			# Only build at ground.
			if cell.y != 0:
				return

			# Global exclusivity safety.
			if (_tool == BuildTool.MEZZ2 and _mezz3_cells.size() > 0) \
			or (_tool == BuildTool.MEZZ3 and _mezz2_cells.size() > 0):
				return

			# Do not overwrite existing mezz in the span.
			for i in range(span):
				var c_check := Vector2i(cell.x, cell.y + i)
				if _mezz2_cells.has(c_check) or _mezz3_cells.has(c_check):
					return

			# No floors inside the ground footprint.
			for i in range(span):
				var c_ground := Vector2i(cell.x, cell.y + i)
				if _floors.has(c_ground):
					return

			# Stamp.
			if _can_build(_tool, cell):
				for i in range(span):
					var c := Vector2i(cell.x, cell.y + i)
					if _tool == BuildTool.MEZZ2:
						_mezz2_cells[c] = true
					else:
						_mezz3_cells[c] = true
					_mezz_reserved[c] = true

		BuildTool.OFFICE:
			if _can_build(_tool, cell):
				_offices[cell] = true

		BuildTool.APARTMENT:
			if _can_build(_tool, cell):
				_apartments[cell] = true

		BuildTool.DEMOLISH:
			var above := Vector2i(cell.x, cell.y + 1)

			# 1) Tenants first
			if _offices.has(cell):
				_offices.erase(cell); return
			if _apartments.has(cell):
				_apartments.erase(cell); return

			# 2) Stairs / Escalators (group for stairs & esc-up; single for esc-down)
			if _stairs.has(cell):
				for c in _collect_contiguous(_stairs, cell):
					_stairs.erase(c)
				return
			if _escalators_up.has(cell):
				for c in _collect_contiguous(_escalators_up, cell):
					_escalators_up.erase(c)
				return
			if _escalators_down.has(cell):
				_escalators_down.erase(cell)
				return

			# 3) Floors / Elevator / Mezz — safety: do not demolish if a floor exists directly above the target(s)

			# Floor (single)
			if _floors.has(cell):
				if _floors.has(above):
					return
				_floors.erase(cell)
				return

			# Elevator (group)
			if _elevators.has(cell):
				var group := _collect_contiguous(_elevators, cell)
				# Block if any group member has a floor directly above
				for c in group:
					if _floors.has(Vector2i(c.x, c.y + 1)):
						return
				for c in group:
					_elevators.erase(c)
				return

			# Mezz (full span)
			if _mezz2_cells.has(cell) or _mezz3_cells.has(cell):
				var mezz_cells := _mezz_demolish_cells(cell)
				# Topmost y of the span
				var top_y := mezz_cells[mezz_cells.size() - 1].y
				if _floors.has(Vector2i(cell.x, top_y + 1)):
					return
				for c in mezz_cells:
					if _mezz2_cells.has(c): _mezz2_cells.erase(c)
					if _mezz3_cells.has(c): _mezz3_cells.erase(c)
					_mezz_reserved.erase(c)
				return

	_build_layer.queue_redraw()
	if is_instance_valid(_minimap):
		_minimap.update_viewbox()

func _row_has_access(level_y: int) -> bool:
	for key in _stairs.keys():
		var c: Vector2i = key
		if c.y == level_y:
			return true
	for key in _escalators.keys():
		var c2: Vector2i = key
		if c2.y == level_y:
			return true
	return false

# ---- Draw layer for floors & elevators ----
func _cascade_remove_unsupported() -> void:
	var changed := true
	while changed:
		changed = false
		var to_remove: Array[Vector2i] = []
		for key in _floors.keys():
			var c: Vector2i = key
			if c.y > 0 and not _floors.has(Vector2i(c.x, c.y - 1)):
				to_remove.append(c)
			elif c.y < 0 and not _floors.has(Vector2i(c.x, c.y + 1)):
				to_remove.append(c)
		if to_remove.size() > 0:
			changed = true
			for c in to_remove:
				_floors.erase(c)
	_build_layer.queue_redraw()

# === CONFIG: default save path (change if you like) ===
const SAVE_SCHEMA_VERSION: int = 1
const SAVE_SLOTS := ["user://slot1.json", "user://slot2.json", "user://slot3.json"]
var _save_slot: int = 0

# === JSON helpers: make Vector2i-keyed dictionaries JSON-safe ===
func _dict_to_xy_array(dict_in: Dictionary) -> Array:
	# Returns Array of Arrays: [[x,y], ...]
	var out: Array = []
	for k in dict_in.keys():
		var v2: Vector2i = k
		out.append([v2.x, v2.y])
	return out

func _xy_array_to_dict(arr: Array) -> Dictionary:
	# Returns Dictionary{ Vector2i: true }
	var out := {}
	for item in arr:
		if item is Array and item.size() == 2:
			var x := int(item[0])
			var y := int(item[1])
			out[Vector2i(x, y)] = true
	return out

# === Serialize whole world into a versioned Dictionary ===
func _serialize_state() -> Dictionary:
	return {
		"version": SAVE_SCHEMA_VERSION,
		"meta": {
			"timestamp": Time.get_unix_time_from_system(),
			"tool": int(_tool),
		},
		"grid": {
			"floors": _dict_to_xy_array(_floors),
			"mezz2": _dict_to_xy_array(_mezz2_cells),
			"mezz3": _dict_to_xy_array(_mezz3_cells),
			"elevators": _dict_to_xy_array(_elevators),
			"stairs": _dict_to_xy_array(_stairs),
			"escalators_up": _dict_to_xy_array(_escalators_up),
			"escalators_down": _dict_to_xy_array(_escalators_down),
			"offices": _dict_to_xy_array(_offices),
			"apartments": _dict_to_xy_array(_apartments),
		}
	}

# === Clear current world ===
func _clear_world() -> void:
	_floors.clear()
	_mezz2_cells.clear()
	_mezz3_cells.clear()
	_mezz_reserved.clear()
	_elevators.clear()
	_stairs.clear()
	_escalators_up.clear()
	_escalators_down.clear()
	_offices.clear()
	_apartments.clear()

# === Rebuild derived maps (mezz_reserved) after loading ===
func _rebuild_mezz_reserved() -> void:
	for k in _mezz2_cells.keys():
		_mezz_reserved[k] = true
	for k in _mezz3_cells.keys():
		_mezz_reserved[k] = true

# === Deserialize: validate, clear, repopulate, rebuild ===
func _deserialize_state(data: Dictionary) -> bool:
	if not data.has("version") or int(data.version) != SAVE_SCHEMA_VERSION:
		return false
	if not data.has("grid"):
		return false

	var g: Dictionary = data.grid
	_clear_world()

	_floors = _xy_array_to_dict(g.get("floors", []))
	_mezz2_cells = _xy_array_to_dict(g.get("mezz2", []))
	_mezz3_cells = _xy_array_to_dict(g.get("mezz3", []))
	_elevators = _xy_array_to_dict(g.get("elevators", []))
	_stairs = _xy_array_to_dict(g.get("stairs", []))
	_escalators_up = _xy_array_to_dict(g.get("escalators_up", []))
	_escalators_down = _xy_array_to_dict(g.get("escalators_down", []))
	_offices = _xy_array_to_dict(g.get("offices", []))
	_apartments = _xy_array_to_dict(g.get("apartments", []))

	_rebuild_mezz_reserved()

	if data.has("meta") and data.meta is Dictionary and data.meta.has("tool"):
		_tool = int(data.meta.tool)

	queue_redraw()
	return true

func save_game(slot: int = _save_slot) -> bool:
	var path: String = SAVE_SLOTS[clamp(slot, 0, SAVE_SLOTS.size() - 1)]
	var payload := _serialize_state()
	var json := JSON.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_toast("Save failed")
		return false
	f.store_string(json)
	f.flush()
	f.close()
	_show_toast("Saved to " + path)
	return true

func load_game(slot: int = _save_slot) -> bool:
	var path: String = SAVE_SLOTS[clamp(slot, 0, SAVE_SLOTS.size() - 1)]
	if not FileAccess.file_exists(path):
		_show_toast("No save in slot " + str(slot + 1))
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_show_toast("Load failed")
		return false
	var txt: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		_show_toast("Load failed")
		return false
	var data: Dictionary = parsed

	var ok: bool = _deserialize_state(data)
	if ok:
		_show_toast("Loaded slot " + str(slot + 1))
	else:
		_show_toast("Load failed")
	return ok


func _on_autosave_timeout() -> void:
	save_game(_save_slot)

func _on_toast_timeout() -> void:
	if _toast_label != null:
		_toast_label.visible = false
