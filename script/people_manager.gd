# FILE: res://script/people_manager.gd
class_name PeopleManager
extends Node

signal count_changed(count: int)

@export var MOVE_SPEED_PX: float = 260.0
@export var PERSON_RADIUS_PX: float = 10.0
@export var MAX_VISITORS: int = 8
@export var VISITOR_REFRESH_SEC: float = 6.0
@export var POP_ADJUST_SEC: float = 1.5

var host: Node = null        # OpenTower
var build: Node = null       # TowerBuild
var layer: Node2D = null     # PeopleLayer (Node2D inside _world)

var _people: Array[PersonState] = []
var _t_pop: float = 0.0
var _t_vis: float = 0.0
var _desired_visitors: int = 0
var _next_id: int = 1
var _last_count: int = -1

func _ready() -> void:
	set_process(false)

func setup(_host: Node, _build: Node, _layer: Node2D) -> void:
	host = _host
	build = _build
	layer = _layer

	# Hard fail-safe to prevent Nil crashes / “no people”
	if host == null or build == null or layer == null:
		push_warning("PeopleManager.setup(): host/build/layer is null. Check OpenTower _ready() order/args.")
		set_process(false)
		return

	set_process(true)
	_reconcile_population()
	_emit_count_if_changed()
	layer.queue_redraw()

func get_people_count() -> int:
	return _people.size()

func draw_people() -> void:
	if layer == null:
		return
	for p: PersonState in _people:
		layer.draw_circle(p.pos, PERSON_RADIUS_PX, Color(1, 1, 1, 1))

func _process(delta: float) -> void:
	if host == null or build == null or layer == null:
		return

	_t_vis += delta
	_t_pop += delta

	# Change visitor target occasionally
	if _t_vis >= VISITOR_REFRESH_SEC:
		_t_vis = 0.0
		_desired_visitors = randi_range(0, MAX_VISITORS)

	# Reconcile occasionally
	if _t_pop >= POP_ADJUST_SEC:
		_t_pop = 0.0
		_reconcile_population()
		_emit_count_if_changed()

	# ALWAYS sanitize + tick movement
	_sanitize_people()
	_tick_people(delta)

	# Ensure old circles don’t “stick”
	layer.queue_redraw()

# --------------------------------------------------------------------
# Population rules
# - Spawn only after base exists (floor@0 or mezz@0)
# - If tenants exist: exactly capacity people (stay)
# - Else: random visitors come/go
# --------------------------------------------------------------------

func _reconcile_population() -> void:
	if not _has_any_base():
		if _people.size() > 0:
			_people.clear()
			if layer != null:
				layer.queue_redraw()
			_emit_count_if_changed()
		return

	var capacity: int = _capacity_people()
	var target_total: int = capacity if capacity > 0 else _desired_visitors

	while _people.size() < target_total:
		_spawn_person()

	while _people.size() > target_total:
		_people.pop_back()

	if capacity > 0:
		_assign_homes_to_fill_capacity()
	else:
		for p: PersonState in _people:
			p.has_home = false
			p.home_cell = Vector2i(999999, 999999)

func _capacity_people() -> int:
	var offices_count: int = int(build.offices.size())
	var apartments_count: int = int(build.apartments.size())
	return offices_count * 3 + apartments_count * 2

func _assign_homes_to_fill_capacity() -> void:
	var slots: Array[Vector2i] = []

	# offices: 3 each
	for key in build.offices.keys():
		var c: Vector2i = key as Vector2i
		slots.append(c); slots.append(c); slots.append(c)

	# apartments: 2 each
	for key2 in build.apartments.keys():
		var c2: Vector2i = key2 as Vector2i
		slots.append(c2); slots.append(c2)

	slots.shuffle()

	var n: int = mini(_people.size(), slots.size())
	for i in range(_people.size()):
		var p: PersonState = _people[i]
		if i < n:
			p.has_home = true
			p.home_cell = slots[i]
			p.goal = p.home_cell
			_repath(p)
		else:
			p.has_home = false
			p.home_cell = Vector2i(999999, 999999)

func _spawn_person() -> void:
	var p: PersonState = PersonState.new()
	p.id = _next_id
	_next_id += 1

	var spawn: Vector2i = _pick_spawn_cell()
	p.cell = spawn
	p.pos = _cell_center(spawn)

	p.has_home = false
	p.home_cell = Vector2i(999999, 999999)
	p.goal = _pick_random_goal_cell(spawn)
	_repath(p)

	_people.append(p)

func _has_any_base() -> bool:
	for key in build.floors.keys():
		var c: Vector2i = key as Vector2i
		if c.y == 0:
			return true
	for key2 in build.mezz2_cells.keys():
		var c2: Vector2i = key2 as Vector2i
		if c2.y == 0:
			return true
	for key3 in build.mezz3_cells.keys():
		var c3: Vector2i = key3 as Vector2i
		if c3.y == 0:
			return true
	return false

func _emit_count_if_changed() -> void:
	var now: int = _people.size()
	if now != _last_count:
		_last_count = now
		emit_signal("count_changed", now)

# --------------------------------------------------------------------
# IMPORTANT FIX:
# If a person becomes invalid (floor removed under them, out of bounds, etc):
# - visitors: despawn
# - home people: respawn to a valid base tile
# This removes the “one person outside forever” bug.
# --------------------------------------------------------------------

func _sanitize_people() -> void:
	# Walk backwards if we remove entries
	for i in range(_people.size() - 1, -1, -1):
		var p: PersonState = _people[i]

		var bad_cell: bool = (not build.in_bounds(p.cell)) or (not _is_walkable(p.cell))

		if bad_cell:
			if p.has_home:
				# Respawn “resident” onto valid base
				var sp: Vector2i = _pick_spawn_cell()
				p.cell = sp
				p.pos = _cell_center(sp)
				p.path.clear()
				p.path_index = 0
				p.goal = p.home_cell
				_repath(p)
			else:
				# Visitors just leave
				_people.remove_at(i)
				continue

		# If goal/home becomes invalid, reset it
		if p.has_home and ((not build.in_bounds(p.home_cell)) or (not _is_walkable(p.home_cell))):
			p.has_home = false
			p.home_cell = Vector2i(999999, 999999)

		if (not build.in_bounds(p.goal)) or (not _is_walkable(p.goal)):
			p.goal = p.home_cell if p.has_home else _pick_random_goal_cell(p.cell)
			_repath(p)

# --------------------------------------------------------------------
# Movement/pathing
# --------------------------------------------------------------------

func _tick_people(delta: float) -> void:
	for p: PersonState in _people:
		_tick_person(p, delta)

func _tick_person(p: PersonState, delta: float) -> void:
	if p.wait > 0.0:
		p.wait -= delta
		return

	# homebound and already home => stay
	if p.has_home and p.cell == p.home_cell:
		p.path.clear()
		p.path_index = 0
		return

	# need path?
	if p.path.is_empty() or p.path_index >= p.path.size():
		p.goal = p.home_cell if p.has_home else _pick_random_goal_cell(p.cell)
		_repath(p)

	# still no path => wait, try later
	if p.path.is_empty():
		p.wait = 0.8
		return

	var next_cell: Vector2i = p.path[p.path_index]
	var target_pos: Vector2 = _cell_center(next_cell)

	p.pos = p.pos.move_toward(target_pos, MOVE_SPEED_PX * delta)

	if p.pos.distance_to(target_pos) <= 0.5:
		p.pos = target_pos
		p.cell = next_cell
		p.path_index += 1

func _repath(p: PersonState) -> void:
	p.path = _bfs_path(p.cell, p.goal)
	if p.path.size() <= 1:
		p.path.clear()
		p.path_index = 0
	else:
		p.path_index = 1

func _cell_center(c: Vector2i) -> Vector2:
	var cs: float = float(host.CELL_SIZE)
	return Vector2((float(c.x) + 0.5) * cs, (float(c.y) + 0.5) * cs)

func _pick_spawn_cell() -> Vector2i:
	# Prefer x=0, but fall back to any base walkable at y=0
	var try0 := Vector2i(0, 0)
	if build.in_bounds(try0) and _is_walkable(try0):
		return try0

	var half_w: int = int(host.WORLD_WIDTH) >> 1
	for _i in range(128):
		var x: int = randi_range(-half_w, half_w - 1)
		var c := Vector2i(x, 0)
		if build.in_bounds(c) and _is_walkable(c):
			return c

	return Vector2i(0, 0)

func _pick_random_goal_cell(from_cell: Vector2i) -> Vector2i:
	# Prefer tenants sometimes
	if int(build.offices.size()) + int(build.apartments.size()) > 0 and randf() < 0.6:
		for key in build.offices.keys():
			var c: Vector2i = key as Vector2i
			if _is_walkable(c):
				return c
		for key2 in build.apartments.keys():
			var c2: Vector2i = key2 as Vector2i
			if _is_walkable(c2):
				return c2

	# Otherwise roam on base row
	var half_w: int = int(host.WORLD_WIDTH) >> 1
	for _i in range(128):
		var x: int = randi_range(-half_w, half_w - 1)
		var c := Vector2i(x, 0)
		if build.in_bounds(c) and _is_walkable(c):
			return c

	return from_cell

# --------------------------------------------------------------------
# Walkable rules + step rules
# Mezz2: platform at y=0 and y=1
# Mezz3: platform at y=0 and y=2
# Vertical movement ONLY via elevator/stairs/escalators
# --------------------------------------------------------------------

func _column_has_base(x: int) -> bool:
	return build.floors.has(Vector2i(x, 0)) or build.mezz2_cells.has(Vector2i(x, 0)) or build.mezz3_cells.has(Vector2i(x, 0))

func _is_walkable(c: Vector2i) -> bool:
	if build.floors.has(c):
		return true

	# tenants sit on floors; treat as walkable
	if build.offices.has(c) or build.apartments.has(c):
		return true

	# vertical tiles
	if build.stairs.has(c):
		return true
	if build.escalators_up.has(c):
		return true
	if build.escalators_down.has(c):
		return true

	# elevator only if column has base
	if build.elevators.has(c) and _column_has_base(c.x):
		return true

	# mezz platforms
	if build.mezz2_cells.has(c):
		return c.y == 0 or c.y == 1
	if build.mezz3_cells.has(c):
		return c.y == 0 or c.y == 2

	return false

func _can_step(a: Vector2i, b: Vector2i) -> bool:
	if not build.in_bounds(b):
		return false
	if not _is_walkable(b):
		return false

	# horizontal
	if a.y == b.y and abs(a.x - b.x) == 1:
		return _is_walkable(a)

	# vertical only via valid verticals
	if a.x == b.x and abs(a.y - b.y) == 1:
		var dy: int = b.y - a.y

		# elevator: both cells in shaft + base
		if build.elevators.has(a) and build.elevators.has(b) and _column_has_base(a.x):
			return true

		# stairs: both cells are stairs
		if build.stairs.has(a) and build.stairs.has(b):
			return true

		# escalators: directional from “from” cell
		if dy == 1 and build.escalators_up.has(a):
			return true
		if dy == -1 and build.escalators_down.has(a):
			return true

	return false

func _neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	var r := Vector2i(c.x + 1, c.y)
	if _can_step(c, r): out.append(r)

	var l := Vector2i(c.x - 1, c.y)
	if _can_step(c, l): out.append(l)

	var u := Vector2i(c.x, c.y + 1)
	if _can_step(c, u): out.append(u)

	var d := Vector2i(c.x, c.y - 1)
	if _can_step(c, d): out.append(d)

	return out

func _bfs_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if start == goal:
		return [start]

	if not _is_walkable(start) or not _is_walkable(goal):
		return empty

	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var came: Dictionary = {}
	came[start] = start

	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1

		for nxt: Vector2i in _neighbors(cur):
			if came.has(nxt):
				continue
			came[nxt] = cur
			if nxt == goal:
				return _reconstruct_path(came, start, goal)
			queue.append(nxt)

	return empty

func _reconstruct_path(came: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur: Vector2i = goal

	while cur != start:
		path.push_front(cur)
		cur = came[cur] as Vector2i

	path.push_front(start)
	return path
