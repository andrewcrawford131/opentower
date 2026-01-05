# FILE: res://script/tower_build.gd
class_name TowerBuild
extends Node

signal changed

const SAVE_SCHEMA_VERSION: int = 1

enum BuildTool { FLOORS, MEZZ2, MEZZ3, ELEVATOR, STAIRS, ESCALATOR_UP, ESCALATOR_DOWN, OFFICE, APARTMENT, DEMOLISH }

var host: Node = null  # OpenTower (passed in setup)

var tool: int = BuildTool.FLOORS

# --- Build state ---
var floors: Dictionary = {}           # Vector2i -> true
var elevators: Dictionary = {}        # Vector2i -> true
var stairs: Dictionary = {}           # Vector2i -> true
var escalators_up: Dictionary = {}    # Vector2i -> true
var escalators_down: Dictionary = {}  # Vector2i -> true

# legacy (optional; keep empty unless you still use it)
var escalators: Dictionary = {}

var mezz2_cells: Dictionary = {}      # all covered cells
var mezz3_cells: Dictionary = {}      # all covered cells
var mezz_reserved: Dictionary = {}    # disallow floors due to mezz footprint

var offices: Dictionary = {}
var apartments: Dictionary = {}

func setup(_host: Node) -> void:
	host = _host

# --- Bounds / helpers ---
func in_bounds(cell: Vector2i) -> bool:
	var half_w: int = int(host.WORLD_WIDTH) >> 1
	return (cell.x >= -half_w and cell.x <= half_w - 1
		and cell.y >= -int(host.UNDERGROUND_DEPTH) and cell.y <= int(host.BUILD_HEIGHT))

func _any_mezz_on_ground() -> bool:
	for k in mezz2_cells.keys():
		if (k as Vector2i).y == 0:
			return true
	for k in mezz3_cells.keys():
		if (k as Vector2i).y == 0:
			return true
	return false

func mezz_span_height(cell: Vector2i) -> int:
	var x := cell.x
	var y := cell.y
	if mezz3_cells.has(Vector2i(x, y)) and mezz3_cells.has(Vector2i(x, y + 1)) and mezz3_cells.has(Vector2i(x, y + 2)):
		return 3
	if mezz2_cells.has(Vector2i(x, y)) and mezz2_cells.has(Vector2i(x, y + 1)):
		return 2
	return 1

func _collect_contiguous(dict: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var x := cell.x
	var y := cell.y
	while dict.has(Vector2i(x, y - 1)):
		y -= 1
	var out: Array[Vector2i] = []
	var yy := y
	while dict.has(Vector2i(x, yy)):
		out.append(Vector2i(x, yy))
		yy += 1
	return out

func _mezz_demolish_cells(cell: Vector2i) -> Array[Vector2i]:
	var x := cell.x
	var y := cell.y
	while mezz2_cells.has(Vector2i(x, y - 1)) or mezz3_cells.has(Vector2i(x, y - 1)):
		y -= 1

	# Full mezz-3 span
	if mezz3_cells.has(Vector2i(x, y)) and mezz3_cells.has(Vector2i(x, y + 1)) and mezz3_cells.has(Vector2i(x, y + 2)):
		return [Vector2i(x, y), Vector2i(x, y + 1), Vector2i(x, y + 2)]

	# Full mezz-2 span
	if mezz2_cells.has(Vector2i(x, y)) and mezz2_cells.has(Vector2i(x, y + 1)):
		return [Vector2i(x, y), Vector2i(x, y + 1)]

	return [cell]

func demolish_target_cells(cell: Vector2i) -> Array[Vector2i]:
	# Tenants
	if offices.has(cell) or apartments.has(cell):
		return [cell]

	# Verticals (stairs / esc-up delete as a group)
	if stairs.has(cell):
		return _collect_contiguous(stairs, cell)
	if escalators_up.has(cell):
		return _collect_contiguous(escalators_up, cell)
	if escalators_down.has(cell):
		return [cell]

	# Mezz
	if mezz2_cells.has(cell) or mezz3_cells.has(cell):
		return _mezz_demolish_cells(cell)

	# Elevator group
	if elevators.has(cell):
		return _collect_contiguous(elevators, cell)

	# Floor
	if floors.has(cell):
		return [cell]

	return []

# --- Rules / UI messaging ---
func why_blocked(t: int, cell: Vector2i) -> String:
	if not in_bounds(cell):
		return "Out of bounds"

	match t:
		BuildTool.FLOORS:
			if floors.has(cell):
				return "Already a floor"
			if mezz_reserved.has(cell):
				return "Blocked: mezz footprint"

			var above := Vector2i(cell.x, cell.y + 1)
			if stairs.has(above) or escalators_down.has(above) or elevators.has(above):
				return ""

			if cell.y == 0:
				return "Ground blocked by mezz" if _any_mezz_on_ground() else ""

			if cell.y < 0:
				var support_above := floors.has(above) or mezz2_cells.has(above) or mezz3_cells.has(above)
				if not support_above:
					return "Needs support above (floor or mezz)"
				var adj_und := floors.has(Vector2i(cell.x - 1, cell.y)) or floors.has(Vector2i(cell.x + 1, cell.y))
				var vertical_above := stairs.has(above) or escalators_down.has(above) or elevators.has(above)
				var elev_here_und := elevators.has(cell)
				return "" if (adj_und or vertical_above or elev_here_und) else "Needs adjacent floor or vertical above"

			var below := Vector2i(cell.x, cell.y - 1)
			var support_below := floors.has(below) or mezz2_cells.has(below) or mezz3_cells.has(below)
			if not support_below:
				return "Needs support below (floor or mezz)"

			var adj2 := floors.has(Vector2i(cell.x - 1, cell.y)) or floors.has(Vector2i(cell.x + 1, cell.y))
			var vertical_below := stairs.has(below) or escalators_up.has(below)
			var elevator_here := elevators.has(cell)

			if mezz2_cells.has(below) or mezz3_cells.has(below):
				return "" if (adj2 or vertical_below or elevator_here) else "Needs adjacent floor or stairs/esc-up below or elevator here"

			return "" if (adj2 or vertical_below or elevator_here) else "Needs adjacent floor or vertical access"

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span := 2 if t == BuildTool.MEZZ2 else 3
			if cell.y != 0:
				return "Mezz can only be built at ground"
			if t == BuildTool.MEZZ2 and mezz3_cells.size() > 0:
				return "Conflicts with existing Mezz-3"
			if t == BuildTool.MEZZ3 and mezz2_cells.size() > 0:
				return "Conflicts with existing Mezz-2"

			for i in range(span):
				var c2 := Vector2i(cell.x, cell.y + i)
				if floors.has(c2):
					return "Occupied by floor"
			return ""

		BuildTool.OFFICE:
			if not floors.has(cell):
				return "Office requires a floor"
			if elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell):
				return "Occupied by vertical"
			if mezz2_cells.has(cell) or mezz3_cells.has(cell):
				return "Occupied by mezzanine"
			if apartments.has(cell):
				return "Occupied by apartment"
			return ""

		BuildTool.APARTMENT:
			if not floors.has(cell):
				return "Apartment requires a floor"
			if elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell):
				return "Occupied by vertical"
			if mezz2_cells.has(cell) or mezz3_cells.has(cell):
				return "Occupied by mezzanine"
			if offices.has(cell):
				return "Occupied by office"
			return ""

		BuildTool.ELEVATOR:
			# Elevator can be placed even if there is no floor/mezz.
			if elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell):
				return "Occupied"
			# Optional safety: don't allow overwriting tenants
			if offices.has(cell) or apartments.has(cell):
				return "Occupied by tenant"
			return ""

		BuildTool.STAIRS, BuildTool.ESCALATOR_UP, BuildTool.ESCALATOR_DOWN:
			# These still require a floor/mezz
			if not floors.has(cell) and not mezz2_cells.has(cell) and not mezz3_cells.has(cell):
				return "Requires a floor"
			if elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell):
				return "Occupied"
			return ""

		BuildTool.DEMOLISH:
			if offices.has(cell) or apartments.has(cell):
				return ""
			if stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell):
				return ""

			var above := Vector2i(cell.x, cell.y + 1)
			if floors.has(above):
				return "Blocked: floor above"

			if floors.has(cell) or elevators.has(cell):
				return ""

			if mezz2_cells.has(cell) or mezz3_cells.has(cell):
				var mezz_cells := _mezz_demolish_cells(cell)
				var top_y := mezz_cells[mezz_cells.size() - 1].y
				if floors.has(Vector2i(cell.x, top_y + 1)):
					return "Blocked: floor above mezz"
				return ""

	return "Nothing here to demolish"

func can_build(t: int, cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false

	match t:
		BuildTool.FLOORS:
			if mezz_reserved.has(cell) or floors.has(cell):
				return false

			var above := Vector2i(cell.x, cell.y + 1)
			if stairs.has(above) or escalators_down.has(above) or elevators.has(above):
				return true

			if cell.y == 0:
				return not _any_mezz_on_ground()

			if cell.y < 0:
				var support_above := floors.has(above) or mezz2_cells.has(above) or mezz3_cells.has(above)
				if not support_above:
					return false
				var adj_und := floors.has(Vector2i(cell.x - 1, cell.y)) or floors.has(Vector2i(cell.x + 1, cell.y))
				var vertical_above := stairs.has(above) or escalators_down.has(above) or elevators.has(above)
				var elev_here_und := elevators.has(cell)
				return adj_und or vertical_above or elev_here_und

			var below := Vector2i(cell.x, cell.y - 1)

			var support_below := floors.has(below) or mezz2_cells.has(below) or mezz3_cells.has(below)
			var adj2 := floors.has(Vector2i(cell.x - 1, cell.y)) or floors.has(Vector2i(cell.x + 1, cell.y))
			var vertical_below := stairs.has(below) or escalators_up.has(below)

			# NEW: allow extending horizontally from an existing floor on the same level
			# or from a vertical anchor, even if there isn't a floor/mezz directly below.
			return support_below or adj2 or vertical_below or elevators.has(cell)

		BuildTool.ELEVATOR:
			var h := mezz_span_height(cell)
			for i in range(h):
				var c := Vector2i(cell.x, cell.y + i)

				# Make sure every spanned cell stays in bounds
				if not in_bounds(c):
					return false

				# Can't overlap other verticals / itself
				if elevators.has(c) or stairs.has(c) or escalators_up.has(c) or escalators_down.has(c):
					return false

				# Optional safety: don't allow overwriting tenants
				if offices.has(c) or apartments.has(c):
					return false

			return true

		BuildTool.STAIRS:
			var h2 := mezz_span_height(cell)
			for i in range(h2):
				var c2 := Vector2i(cell.x, cell.y + i)
				if not (floors.has(c2) or mezz2_cells.has(c2) or mezz3_cells.has(c2)):
					return false
				if elevators.has(c2) or stairs.has(c2) or escalators_up.has(c2) or escalators_down.has(c2):
					return false
			return true

		BuildTool.ESCALATOR_UP:
			var h3 := mezz_span_height(cell)
			for i in range(h3):
				var c3 := Vector2i(cell.x, cell.y + i)
				if not (floors.has(c3) or mezz2_cells.has(c3) or mezz3_cells.has(c3)):
					return false
				if elevators.has(c3) or stairs.has(c3) or escalators_up.has(c3) or escalators_down.has(c3):
					return false
			return true

		BuildTool.ESCALATOR_DOWN:
			var c4 := cell
			if not (floors.has(c4) or mezz2_cells.has(c4) or mezz3_cells.has(c4)):
				return false
			if elevators.has(c4) or stairs.has(c4) or escalators_up.has(c4) or escalators_down.has(c4):
				return false
			return true

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span := 2 if t == BuildTool.MEZZ2 else 3
			if cell.y != 0:
				return false

			if t == BuildTool.MEZZ2 and mezz3_cells.size() > 0:
				return false
			if t == BuildTool.MEZZ3 and mezz2_cells.size() > 0:
				return false

			for k in floors.keys():
				if (k as Vector2i).y == 0:
					return false

			for i in range(span):
				var c := Vector2i(cell.x, cell.y + i)
				if floors.has(c):
					return false
				if mezz2_cells.has(c) or mezz3_cells.has(c):
					return false
			return true

		BuildTool.OFFICE, BuildTool.APARTMENT:
			if not floors.has(cell):
				return false
			if elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell) or mezz2_cells.has(cell) or mezz3_cells.has(cell):
				return false
			if t == BuildTool.OFFICE:
				if offices.has(cell) or apartments.has(cell):
					return false
			else:
				if apartments.has(cell) or offices.has(cell):
					return false
			return true

		BuildTool.DEMOLISH:
			return floors.has(cell) or elevators.has(cell) or stairs.has(cell) or escalators_up.has(cell) or escalators_down.has(cell) or mezz2_cells.has(cell) or mezz3_cells.has(cell) or offices.has(cell) or apartments.has(cell)

	return false

# --- Mutations ---
func attempt_build(cell: Vector2i) -> void:
	if not in_bounds(cell):
		return

	match tool:
		BuildTool.FLOORS:
			if can_build(tool, cell):
				floors[cell] = true

		BuildTool.ELEVATOR:
			if can_build(tool, cell):
				var h := mezz_span_height(cell)
				for i in range(h):
					elevators[Vector2i(cell.x, cell.y + i)] = true

		BuildTool.STAIRS:
			if can_build(tool, cell):
				var h2 := mezz_span_height(cell)
				for i in range(h2):
					stairs[Vector2i(cell.x, cell.y + i)] = true

		BuildTool.ESCALATOR_UP:
			if can_build(tool, cell):
				var h3 := mezz_span_height(cell)
				for i in range(h3):
					escalators_up[Vector2i(cell.x, cell.y + i)] = true

		BuildTool.ESCALATOR_DOWN:
			if can_build(tool, cell):
				escalators_down[cell] = true

		BuildTool.MEZZ2, BuildTool.MEZZ3:
			var span := 2 if tool == BuildTool.MEZZ2 else 3
			if cell.y != 0:
				return
			if (tool == BuildTool.MEZZ2 and mezz3_cells.size() > 0) or (tool == BuildTool.MEZZ3 and mezz2_cells.size() > 0):
				return

			if can_build(tool, cell):
				for i in range(span):
					var c := Vector2i(cell.x, cell.y + i)
					if tool == BuildTool.MEZZ2:
						mezz2_cells[c] = true
					else:
						mezz3_cells[c] = true
					mezz_reserved[c] = true

		BuildTool.OFFICE:
			if can_build(tool, cell):
				offices[cell] = true

		BuildTool.APARTMENT:
			if can_build(tool, cell):
				apartments[cell] = true

		BuildTool.DEMOLISH:
			var above := Vector2i(cell.x, cell.y + 1)

			if offices.has(cell):
				offices.erase(cell)
				emit_signal("changed")
				return
			if apartments.has(cell):
				apartments.erase(cell)
				emit_signal("changed")
				return

			if stairs.has(cell):
				for c in _collect_contiguous(stairs, cell):
					stairs.erase(c)
				emit_signal("changed")
				return

			if escalators_up.has(cell):
				for c in _collect_contiguous(escalators_up, cell):
					escalators_up.erase(c)
				emit_signal("changed")
				return

			if escalators_down.has(cell):
				escalators_down.erase(cell)
				emit_signal("changed")
				return

			if floors.has(cell):
				if floors.has(above):
					return
				floors.erase(cell)
				emit_signal("changed")
				return

			if elevators.has(cell):
				var group := _collect_contiguous(elevators, cell)
				for c in group:
					if floors.has(Vector2i(c.x, c.y + 1)):
						return
				for c in group:
					elevators.erase(c)
				emit_signal("changed")
				return

			if mezz2_cells.has(cell) or mezz3_cells.has(cell):
				var mezz_cells := _mezz_demolish_cells(cell)
				var top_y := mezz_cells[mezz_cells.size() - 1].y
				if floors.has(Vector2i(cell.x, top_y + 1)):
					return
				for c in mezz_cells:
					if mezz2_cells.has(c): mezz2_cells.erase(c)
					if mezz3_cells.has(c): mezz3_cells.erase(c)
					mezz_reserved.erase(c)
				emit_signal("changed")
				return

	emit_signal("changed")

# --- Save/Load support (same schema as before) ---
func _dict_to_xy_array(dict_in: Dictionary) -> Array:
	var out: Array = []
	for k in dict_in.keys():
		var v2: Vector2i = k
		out.append([v2.x, v2.y])
	return out

func _xy_array_to_dict(arr: Array) -> Dictionary:
	var out := {}
	for item in arr:
		if item is Array and item.size() == 2:
			out[Vector2i(int(item[0]), int(item[1]))] = true
	return out

func serialize_state() -> Dictionary:
	return {
		"version": SAVE_SCHEMA_VERSION,
		"meta": {
			"timestamp": Time.get_unix_time_from_system(),
			"tool": int(tool),
		},
		"grid": {
			"floors": _dict_to_xy_array(floors),
			"mezz2": _dict_to_xy_array(mezz2_cells),
			"mezz3": _dict_to_xy_array(mezz3_cells),
			"elevators": _dict_to_xy_array(elevators),
			"stairs": _dict_to_xy_array(stairs),
			"escalators_up": _dict_to_xy_array(escalators_up),
			"escalators_down": _dict_to_xy_array(escalators_down),
			"offices": _dict_to_xy_array(offices),
			"apartments": _dict_to_xy_array(apartments),
		}
	}

func clear_world() -> void:
	floors.clear()
	mezz2_cells.clear()
	mezz3_cells.clear()
	mezz_reserved.clear()
	elevators.clear()
	stairs.clear()
	escalators_up.clear()
	escalators_down.clear()
	offices.clear()
	apartments.clear()

func _rebuild_mezz_reserved() -> void:
	for k in mezz2_cells.keys():
		mezz_reserved[k] = true
	for k in mezz3_cells.keys():
		mezz_reserved[k] = true

func deserialize_state(data: Dictionary) -> bool:
	if not data.has("version") or int(data.version) != SAVE_SCHEMA_VERSION:
		return false
	if not data.has("grid"):
		return false

	var g: Dictionary = data.grid
	clear_world()

	floors = _xy_array_to_dict(g.get("floors", []))
	mezz2_cells = _xy_array_to_dict(g.get("mezz2", []))
	mezz3_cells = _xy_array_to_dict(g.get("mezz3", []))
	elevators = _xy_array_to_dict(g.get("elevators", []))
	stairs = _xy_array_to_dict(g.get("stairs", []))
	escalators_up = _xy_array_to_dict(g.get("escalators_up", []))
	escalators_down = _xy_array_to_dict(g.get("escalators_down", []))
	offices = _xy_array_to_dict(g.get("offices", []))
	apartments = _xy_array_to_dict(g.get("apartments", []))

	_rebuild_mezz_reserved()

	if data.has("meta") and data.meta is Dictionary and data.meta.has("tool"):
		tool = int(data.meta.tool)

	emit_signal("changed")
	return true
