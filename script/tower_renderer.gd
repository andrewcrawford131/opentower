# FILE: res://script/tower_renderer.gd
class_name TowerRenderer
extends Node

var host: Node = null          # OpenTower
var build: Node = null         # TowerBuild (optional; can be host if not extracted yet)

var bg_layer: Node2D
var build_layer: Node2D
var grid_layer: Node2D

func setup(_host: Node, _build: Node, _bg: Node2D, _build_layer: Node2D, _grid: Node2D) -> void:
	host = _host
	build = _build
	bg_layer = _bg
	build_layer = _build_layer
	grid_layer = _grid

func draw_background() -> void:
	# NOTE: host must provide _world_left_px/_world_right_px/_world_top_px/_world_bottom_px and SKY_COLOR/GROUND_COLOR
	var left: float = host._world_left_px()
	var right: float = host._world_right_px()
	var top_px: float = host._world_top_px()
	var bottom_px: float = host._world_bottom_px()

	if top_px > 0.0:
		bg_layer.draw_rect(Rect2(Vector2(left, 0.0), Vector2(right - left, top_px)), host.SKY_COLOR, true)
	if bottom_px < 0.0:
		bg_layer.draw_rect(Rect2(Vector2(left, bottom_px), Vector2(right - left, -bottom_px)), host.GROUND_COLOR, true)

func draw_grid() -> void:
	var left: float = host._world_left_px()
	var right: float = host._world_right_px()
	var top_px: float = host._world_top_px()
	var bottom_px: float = host._world_bottom_px()
	var step: float = float(host.CELL_SIZE)

	var x := left
	while x <= right + 0.5:
		grid_layer.draw_line(Vector2(x, bottom_px), Vector2(x, top_px), host.GRID_COLOR, 1.0)
		x += step

	var y := bottom_px
	while y <= top_px + 0.5:
		grid_layer.draw_line(Vector2(left, y), Vector2(right, y), host.GRID_COLOR, 1.0)
		y += step

	if host.GRID_SHOW_AXIS_LINES:
		grid_layer.draw_line(Vector2(0, bottom_px), Vector2(0, top_px), host.AXIS_COLOR, 2.0)
		grid_layer.draw_line(Vector2(left, 0), Vector2(right, 0), host.AXIS_COLOR, 2.0)

func draw_build() -> void:
	# If you haven’t extracted build yet, you can read dictionaries from host instead of build.
	# This version assumes build has the dictionaries; tweak if needed.
	var floors: Dictionary = build.floors
	var elevators: Dictionary = build.elevators
	var stairs: Dictionary = build.stairs
	var esc_up: Dictionary = build.escalators_up
	var esc_down: Dictionary = build.escalators_down
	var mezz2: Dictionary = build.mezz2_cells
	var mezz3: Dictionary = build.mezz3_cells

	for key in floors.keys():
		var cell: Vector2i = key
		var c: Color = host.FLOOR_GROUND_COLOR if cell.y == 0 else (host.FLOOR_UP_COLOR if cell.y > 0 else host.FLOOR_DOWN_COLOR)
		_draw_cell(build_layer, cell, c)

	for key in elevators.keys():
		_draw_elevator(build_layer, key, host.ELEVATOR_COLOR)
	for key in stairs.keys():
		_draw_stairs(build_layer, key, host.STAIRS_COLOR)
	for key in esc_up.keys():
		_draw_escalator(build_layer, key, host.ESCALATOR_UP_COLOR)
	for key in esc_down.keys():
		_draw_escalator(build_layer, key, host.ESCALATOR_DOWN_COLOR)

	for key in mezz2.keys():
		_draw_cell(build_layer, key, host.MEZZ2_COLOR)
	for key in mezz3.keys():
		_draw_cell(build_layer, key, host.MEZZ3_COLOR)

	# Hover + drag preview still live on host (easy to move later)
	var hc: Vector2i = host._hover_cell
	if host._in_bounds(hc):
		var col: Color = host.HOVER_OK_COLOR if host._hover_valid else host.HOVER_BAD_COLOR
		var r := Rect2(Vector2(hc.x * host.CELL_SIZE, hc.y * host.CELL_SIZE), Vector2(host.CELL_SIZE, host.CELL_SIZE))
		build_layer.draw_rect(r, col, true)

	if host._drag_building:
		var rect: Rect2i = host._drag_rect_from(host._drag_a_cell, host._drag_b_cell)
		var rp := Vector2(rect.position.x * host.CELL_SIZE, rect.position.y * host.CELL_SIZE)
		var rs := Vector2(rect.size.x * host.CELL_SIZE, rect.size.y * host.CELL_SIZE)
		build_layer.draw_rect(Rect2(rp, rs), Color(1, 1, 0, 0.12), true)
		build_layer.draw_rect(Rect2(rp, rs), Color(1, 1, 0, 0.8), false)

func _draw_cell(layer: CanvasItem, cell: Vector2i, color: Color) -> void:
	var tl := Vector2(cell.x * host.CELL_SIZE, cell.y * host.CELL_SIZE)
	layer.draw_rect(Rect2(tl, Vector2(host.CELL_SIZE, host.CELL_SIZE)), color, true)

func _draw_elevator(layer: CanvasItem, cell: Vector2i, color: Color) -> void:
	var tl := Vector2(cell.x * host.CELL_SIZE, cell.y * host.CELL_SIZE)
	var w := float(host.CELL_SIZE) * 0.25
	var rect_pos := Vector2(tl.x + (float(host.CELL_SIZE) - w) * 0.5, tl.y)
	layer.draw_rect(Rect2(rect_pos, Vector2(w, host.CELL_SIZE)), color, true)

func _draw_stairs(layer: CanvasItem, cell: Vector2i, color: Color) -> void:
	var tl := Vector2(cell.x * host.CELL_SIZE, cell.y * host.CELL_SIZE)
	var s := float(host.CELL_SIZE)
	layer.draw_colored_polygon(PackedVector2Array([tl, tl + Vector2(s, 0), tl + Vector2(0, s)]), color)

func _draw_escalator(layer: CanvasItem, cell: Vector2i, color: Color) -> void:
	var tl := Vector2(cell.x * host.CELL_SIZE, cell.y * host.CELL_SIZE)
	var w := float(host.CELL_SIZE) * 0.6
	var h := float(host.CELL_SIZE) * 0.25
	var pos := Vector2(tl.x + (float(host.CELL_SIZE) - w) * 0.5, tl.y + (float(host.CELL_SIZE) - h) * 0.5)
	layer.draw_rect(Rect2(pos, Vector2(w, h)), color, true)
