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
const TowerBuildScript := preload("res://script/tower_build.gd")
var _build: TowerBuild
const TowerHudScript := preload("res://script/tower_hud.gd")
var _hud: TowerHud

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
@export var HOVER_OK_COLOR: Color = Color(0.25, 1.0, 0.35, 0.40)
@export var HOVER_BAD_COLOR: Color = Color(1.00, 0.25, 0.25, 0.40)
@export var ESCALATOR_UP_COLOR: Color = Color(0.20, 0.65, 1.00, 1.0)
@export var ESCALATOR_DOWN_COLOR: Color = Color(1.00, 0.55, 0.20, 1.0)
const MEZZ2_COLOR: Color = Color(0.20, 0.70, 1.00, 0.70)  # bright cyan, semi-opaque
const MEZZ3_COLOR: Color = Color(0.60, 0.35, 1.00, 0.70)  # violet, semi-opaque
@export var OFFICE_COLOR: Color = Color(0.20, 0.70, 0.90, 1.0)
@export var APARTMENT_COLOR: Color = Color(0.50, 0.90, 0.50, 1.0)

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

# This scales ONLY the minimap camera fit.
# 1.0 = exact fit, <1.0 zooms OUT a bit, >1.0 zooms IN a bit.
@export var MINIMAP_ZOOM_MULT: float = 1.0
@export var MINIMAP_DEBUG: bool = false

# ---- Camera pan/zoom config ----
@export var PAN_SPEED: float = 800.0
@export var ZOOM_STEP: float = 0.1
@export var MIN_ZOOM: float = 0.25
@export var MAX_ZOOM: float = 3.0

# --- Save slots ---
const SAVE_SLOTS := ["user://slot1.json", "user://slot2.json", "user://slot3.json"]
var _save_slot: int = 0

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

func _on_build_changed() -> void:
	if is_instance_valid(_build_layer):
		_build_layer.queue_redraw()
	if is_instance_valid(_minimap):
		_minimap.update_viewbox()

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

	_build = TowerBuildScript.new()
	add_child(_build)
	_build.setup(self)
	_build.changed.connect(Callable(self, "_on_build_changed"))

	_hud = TowerHudScript.new()
	add_child(_hud)
	_hud.setup(self, _build, {"save_slots": SAVE_SLOTS, "start_slot": _save_slot})

	_hud.tool_changed.connect(Callable(self, "_on_hud_tool_changed"))
	_hud.slot_changed.connect(Callable(self, "_on_hud_slot_changed"))
	_hud.save_requested.connect(Callable(self, "_on_hud_save_requested"))
	_hud.load_requested.connect(Callable(self, "_on_hud_load_requested"))

	_hud.set_slot_timestamp(_slot_timestamp(_save_slot))

	# NOW create + hook renderer (after layers exist)
	_renderer = TowerRendererScript.new()
	add_child(_renderer)
	_renderer.setup(self, _build, _bg_layer, _build_layer, _grid_layer)

	_bg_layer.connect("draw", Callable(_renderer, "draw_background"))
	_grid_layer.connect("draw", Callable(_renderer, "draw_grid"))
	_build_layer.connect("draw", Callable(_renderer, "draw_build"))

	# Minimap (beta-world working version)
	_minimap = MinimapControllerScript.new()
	add_child(_minimap)
	_minimap.setup(self, _build, {
		"size": MINIMAP_SIZE,
		"margin": MINIMAP_MARGIN,
		"frustum_color": MINIMAP_FRUSTUM_COLOR,
		"border": MINIMAP_BORDER,
		"border_bg": MINIMAP_BORDER_BG,
		"border_color": MINIMAP_BORDER_COLOR,
		"viewbox_border": MINIMAP_VIEWBOX_BORDER,
		"viewbox_color": MINIMAP_VIEWBOX_COLOR,
		"home_text": MINIMAP_HOME_TEXT,
		"zoom_mult": MINIMAP_ZOOM_MULT,
	})

	get_window().connect("size_changed", Callable(self, "_on_screen_resized"))

	_setup_autosave()

	_bg_layer.queue_redraw()
	_build_layer.queue_redraw()
	_grid_layer.queue_redraw()

func _on_hud_tool_changed(_t: int) -> void:
	_hover_valid = _build.can_build(_build.tool, _hover_cell)
	if is_instance_valid(_build_layer):
		_build_layer.queue_redraw()
	if is_instance_valid(_hud):
		_hud.update_hover(_hover_cell, _hover_valid)

func _on_hud_slot_changed(slot: int) -> void:
	_save_slot = slot
	if is_instance_valid(_hud):
		_hud.set_slot_timestamp(_slot_timestamp(_save_slot))
		_hud.toast("Slot " + str(_save_slot + 1))

func _on_hud_save_requested(slot: int) -> void:
	_save_slot = slot
	save_game(_save_slot)
	if is_instance_valid(_hud):
		_hud.set_slot_timestamp(_slot_timestamp(_save_slot))

func _on_hud_load_requested(slot: int) -> void:
	_save_slot = slot
	load_game(_save_slot)
	if is_instance_valid(_hud):
		_hud.set_slot_timestamp(_slot_timestamp(_save_slot))

func _on_screen_resized() -> void:
	if is_instance_valid(_hud):
		_hud.relayout()
	if is_instance_valid(_minimap):
		_minimap.update_viewbox()

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
	_build.attempt_build(cell)

func _mouse_to_cell() -> Vector2i:
	var local: Vector2 = _world.to_local(get_global_mouse_position())
	return _world_to_cell(local)

func _unhandled_input(event: InputEvent) -> void:
	# Hover + drag pan
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		# Update hover preview first
		if is_instance_valid(_world):
			var local: Vector2 = _world.to_local(get_global_mouse_position())

			var prev_cell := _hover_cell
			var prev_valid := _hover_valid

			_hover_cell = _world_to_cell(local)
			_hover_valid = _build.can_build(_build.tool, _hover_cell)

			if is_instance_valid(_hud):
				_hud.update_hover(_hover_cell, _hover_valid)

			# Update drag rectangle endpoint
			if _drag_building:
				_drag_b_cell = _mouse_to_cell()

			# IMPORTANT: redraw whenever hover state changes (or while dragging)
			if is_instance_valid(_build_layer) and (_drag_building or _hover_cell != prev_cell or _hover_valid != prev_valid):
				_build_layer.queue_redraw()

		# Pan while dragging
		if _is_dragging:
			_camera.position -= Vector2(mm.relative.x, -mm.relative.y)
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
			_zoom_by(1.0 + ZOOM_STEP)  # zoom IN
			return
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 - ZOOM_STEP)  # zoom OUT
			return

		# Build drag (LMB)
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
					_drag_place_rect(rect)
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
			_on_hud_save_requested(_save_slot)
		elif ctrl and event.keycode == KEY_L:
			_on_hud_load_requested(_save_slot)
		elif event.keycode == KEY_1:
			_on_hud_slot_changed(0)
		elif event.keycode == KEY_2:
			_on_hud_slot_changed(1)
		elif event.keycode == KEY_3:
			_on_hud_slot_changed(2)

func _camera_half_view() -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(vp.x / _camera.zoom.x, vp.y / _camera.zoom.y) * 0.5

func _clamp_camera_to_world() -> void:
	var half: Vector2 = _camera_half_view()
	var left: float = _world_left_px() + half.x
	var right: float = _world_right_px() - half.x
	# X is regular
	var pos: Vector2 = _camera.position
	if left <= right:
		pos.x = clamp(pos.x, left, right)

	# Y is inverted because the world Node2D has scale.y = -1.
	var top_g: float = -_world_top_px()
	var bottom_g: float = -_world_bottom_px()
	var min_y: float = top_g + half.y
	var max_y: float = bottom_g - half.y

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_instance_valid(_bg_layer):
			_bg_layer.queue_redraw()
		if is_instance_valid(_build_layer):
			_build_layer.queue_redraw()
		if is_instance_valid(_grid_layer):
			_grid_layer.queue_redraw()

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

func _show_toast(msg: String) -> void:
	if is_instance_valid(_hud):
		_hud.toast(msg)
	else:
		print(msg)

func _world_to_cell(local: Vector2) -> Vector2i:
	var cx: int = int(floor(local.x / float(CELL_SIZE)))
	var cy: int = int(floor(local.y / float(CELL_SIZE)))
	return Vector2i(cx, cy)

func save_game(slot: int = _save_slot) -> bool:
	var path: String = SAVE_SLOTS[clamp(slot, 0, SAVE_SLOTS.size() - 1)]
	var payload := _build.serialize_state()
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

	var ok: bool = _build.deserialize_state(data)
	if ok:
		_show_toast("Loaded slot " + str(slot + 1))
	else:
		_show_toast("Load failed")
	return ok

func _on_autosave_timeout() -> void:
	save_game(_save_slot)
	if is_instance_valid(_hud):
		_hud.set_slot_timestamp(_slot_timestamp(_save_slot))
