# FILE: res://script/tower_hud.gd
class_name TowerHud
extends Node

signal tool_changed(tool: int)
signal slot_changed(slot: int)
signal save_requested(slot: int)
signal load_requested(slot: int)

# Keep host untyped to avoid circular/typed-call issues.
var host: Node = null
var build: TowerBuild = null

# --- Save UI state (owned by HUD, persisted by host) ---
var save_slots: Array = []          # Array of strings
var save_slot: int = 0

# --- Nodes (toolbar/hint) ---
var hud_layer: CanvasLayer = null
var toolbar_panel: PanelContainer = null
var tool_chip: Label = null

var hint_layer: CanvasLayer = null
var hint_panel: PanelContainer = null
var hint_label: Label = null

# --- Save HUD ---
var save_layer: CanvasLayer = null
var save_row: HBoxContainer = null
var slot_dd: OptionButton = null
var slot_info_label: Label = null

# --- Toast ---
var toast_layer: CanvasLayer = null
var toast_label: Label = null
var toast_timer: Timer = null

func setup(_host: Node, _build: TowerBuild, p_cfg: Dictionary = {}) -> void:
	host = _host
	build = _build

	# Optional config from OpenTower
	var v_slots: Variant = p_cfg.get("save_slots", null)
	if v_slots is Array:
		save_slots = v_slots
	var v_start: Variant = p_cfg.get("start_slot", null)
	if v_start != null:
		save_slot = int(v_start)

	_build_toolbar_and_hint()
	_build_save_hud()
	_build_toast()

	_relayout_all()
	update_tool_chip()
	update_hover(Vector2i.ZERO, true)

	# Follow window resize
	var win: Window = null
	if host != null:
		win = host.get_window()
	if win != null and not win.is_connected("size_changed", Callable(self, "_on_screen_resized")):
		win.connect("size_changed", Callable(self, "_on_screen_resized"))

func relayout() -> void:
	_relayout_all()

# Call this from OpenTower whenever hover cell/valid changes
func update_hover(cell: Vector2i, valid: bool) -> void:
	if hint_label == null or build == null:
		return

	var msg: String = ""
	if build.in_bounds(cell) and not valid:
		msg = build.why_blocked(build.tool, cell)

	hint_label.text = msg
	hint_panel.visible = (msg != "")

# OpenTower calls this after it computes timestamp text.
func set_slot_timestamp(ts_text: String) -> void:
	if slot_info_label != null:
		slot_info_label.text = "(" + ts_text + ")"

func toast(msg: String) -> void:
	if toast_label == null or toast_timer == null:
		return
	toast_label.text = msg
	toast_label.visible = true
	toast_timer.start()

# -------------------------------------------------------------------

func _build_toolbar_and_hint() -> void:
	# HUD layer (toolbar + chip)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)

	toolbar_panel = PanelContainer.new()
	toolbar_panel.position = Vector2(12, 8)
	hud_layer.add_child(toolbar_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_color = Color(1, 1, 1, 0.25)
	toolbar_panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	toolbar_panel.add_child(row)

	# Small left spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(32, 1)
	row.add_child(spacer)
	row.move_child(spacer, 0)

	_hud_add_btn(row, "Floors", Callable(self, "_on_tool_floors"))

	# Mezz dropdown
	var mezz_btn := MenuButton.new()
	mezz_btn.text = "Mezz"
	mezz_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(mezz_btn)
	var mezz_menu: PopupMenu = mezz_btn.get_popup()
	mezz_menu.clear()
	mezz_menu.add_item("Mezz 2", 2)
	mezz_menu.add_item("Mezz 3", 3)
	if not mezz_menu.is_connected("id_pressed", Callable(self, "_on_mezz_menu_id_pressed")):
		mezz_menu.connect("id_pressed", Callable(self, "_on_mezz_menu_id_pressed"))

	_hud_add_btn(row, "Elevator", Callable(self, "_on_tool_elevator"))
	_hud_add_btn(row, "Stairs", Callable(self, "_on_tool_stairs"))
	_hud_add_btn(row, "Esc Up", Callable(self, "_on_tool_escalator_up"))
	_hud_add_btn(row, "Esc Down", Callable(self, "_on_tool_escalator_down"))

	_hud_add_btn(row, "Office", Callable(self, "_on_tool_office"))
	_hud_add_btn(row, "Apartment", Callable(self, "_on_tool_apartment"))
	_hud_add_btn(row, "Demolish", Callable(self, "_on_tool_demolish"))

	# Tool chip
	tool_chip = Label.new()
	tool_chip.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0, 1.0))
	tool_chip.add_theme_font_size_override("font_size", 14)
	hud_layer.add_child(tool_chip)

	# Hint bar layer
	hint_layer = CanvasLayer.new()
	hint_layer.layer = 50
	add_child(hint_layer)

	hint_panel = PanelContainer.new()
	hint_panel.visible = false
	hint_panel.name = "HintBar"
	hint_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	hint_panel.position = Vector2(32, 108)
	hint_layer.add_child(hint_panel)

	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(1, 1, 0, 0.85)
	sb2.corner_radius_top_left = 6
	sb2.corner_radius_top_right = 6
	sb2.corner_radius_bottom_left = 6
	sb2.corner_radius_bottom_right = 6
	sb2.content_margin_left = 10
	sb2.content_margin_right = 10
	sb2.content_margin_top = 6
	sb2.content_margin_bottom = 6
	hint_panel.add_theme_stylebox_override("panel", sb2)

	hint_label = Label.new()
	hint_label.text = ""
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0, 0, 0))
	hint_label.add_theme_font_size_override("font_size", 20)
	hint_panel.add_child(hint_label)

func _build_save_hud() -> void:
	save_layer = CanvasLayer.new()
	save_layer.layer = 10
	add_child(save_layer)

	save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	save_layer.add_child(save_row)

	var lbl_save := Label.new()
	lbl_save.text = "Save & Load"
	save_row.add_child(lbl_save)

	slot_dd = OptionButton.new()
	# Populate from save_slots if present, else default 3.
	if save_slots.size() > 0:
		for i in range(save_slots.size()):
			slot_dd.add_item("Slot " + str(i + 1), i)
	else:
		slot_dd.add_item("Slot 1", 0)
		slot_dd.add_item("Slot 2", 1)
		slot_dd.add_item("Slot 3", 2)

	slot_dd.selected = save_slot
	slot_dd.item_selected.connect(Callable(self, "_on_slot_selected"))
	save_row.add_child(slot_dd)

	slot_info_label = Label.new()
	slot_info_label.name = "SlotInfo"
	slot_info_label.text = "(Empty)"
	save_row.add_child(slot_info_label)

	_hud_add_btn(save_row, "Save", Callable(self, "_on_save_pressed"))
	_hud_add_btn(save_row, "Load", Callable(self, "_on_load_pressed"))

	# Positioning on resize
	var root_win: Window = get_tree().root
	if root_win != null and not root_win.is_connected("size_changed", Callable(self, "_position_save_row")):
		root_win.connect("size_changed", Callable(self, "_position_save_row"))
	call_deferred("_position_save_row")

func _build_toast() -> void:
	toast_layer = CanvasLayer.new()
	toast_layer.layer = 200
	add_child(toast_layer)

	toast_label = Label.new()
	toast_label.visible = false
	toast_label.text = ""
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	toast_layer.add_child(toast_label)

	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 1.5
	add_child(toast_timer)
	toast_timer.timeout.connect(Callable(self, "_on_toast_timeout"))

func _relayout_all() -> void:
	_relayout_chip_and_hint()
	_position_save_row()
	_position_toast()

func _on_screen_resized() -> void:
	_relayout_all()

func _relayout_chip_and_hint() -> void:
	if toolbar_panel == null:
		return

	# Ensure sizes are ready
	call_deferred("_relayout_chip_and_hint_deferred")

func _relayout_chip_and_hint_deferred() -> void:
	if toolbar_panel == null:
		return
	var panel_pos: Vector2 = toolbar_panel.position
	var panel_size: Vector2 = toolbar_panel.size

	if tool_chip != null:
		tool_chip.position = Vector2(panel_pos.x + panel_size.x + 12.0, panel_pos.y + 2.0)

	if hint_panel != null:
		hint_panel.position = Vector2(panel_pos.x, panel_pos.y + panel_size.y + 8.0)

func _position_save_row() -> void:
	if save_row == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var size: Vector2 = save_row.get_minimum_size()
	save_row.position = Vector2(vp.x - size.x - 16.0, vp.y - size.y - 16.0)

func _position_toast() -> void:
	if toast_label == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	toast_label.position = Vector2(0, vp.y - 36.0)
	toast_label.custom_minimum_size = Vector2(vp.x, 0)

# -------------------------------------------------------------------
# Button helpers / handlers

func _hud_add_btn(row: HBoxContainer, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	row.add_child(b)
	if not b.is_connected("pressed", cb):
		b.connect("pressed", cb)

func _on_slot_selected(index: int) -> void:
	save_slot = index
	emit_signal("slot_changed", save_slot)

func _on_save_pressed() -> void:
	emit_signal("save_requested", save_slot)

func _on_load_pressed() -> void:
	emit_signal("load_requested", save_slot)

func _set_tool(t: int) -> void:
	if build == null:
		return
	build.tool = t
	update_tool_chip()
	emit_signal("tool_changed", t)

func _on_tool_floors() -> void: _set_tool(TowerBuild.BuildTool.FLOORS)
func _on_tool_elevator() -> void: _set_tool(TowerBuild.BuildTool.ELEVATOR)
func _on_tool_stairs() -> void: _set_tool(TowerBuild.BuildTool.STAIRS)
func _on_tool_escalator_up() -> void: _set_tool(TowerBuild.BuildTool.ESCALATOR_UP)
func _on_tool_escalator_down() -> void: _set_tool(TowerBuild.BuildTool.ESCALATOR_DOWN)
func _on_tool_office() -> void: _set_tool(TowerBuild.BuildTool.OFFICE)
func _on_tool_apartment() -> void: _set_tool(TowerBuild.BuildTool.APARTMENT)
func _on_tool_demolish() -> void: _set_tool(TowerBuild.BuildTool.DEMOLISH)

func _on_mezz_menu_id_pressed(id: int) -> void:
	if id == 2:
		_set_tool(TowerBuild.BuildTool.MEZZ2)
	elif id == 3:
		_set_tool(TowerBuild.BuildTool.MEZZ3)

func update_tool_chip() -> void:
	if tool_chip == null or build == null:
		return

	var tool_label := ""
	match build.tool:
		TowerBuild.BuildTool.FLOORS: tool_label = "Floors"
		TowerBuild.BuildTool.MEZZ2: tool_label = "Mezz 2"
		TowerBuild.BuildTool.MEZZ3: tool_label = "Mezz 3"
		TowerBuild.BuildTool.ELEVATOR: tool_label = "Elevator"
		TowerBuild.BuildTool.STAIRS: tool_label = "Stairs"
		TowerBuild.BuildTool.ESCALATOR_UP: tool_label = "Esc Up"
		TowerBuild.BuildTool.ESCALATOR_DOWN: tool_label = "Esc Down"
		TowerBuild.BuildTool.OFFICE: tool_label = "Office"
		TowerBuild.BuildTool.APARTMENT: tool_label = "Apartment"
		TowerBuild.BuildTool.DEMOLISH: tool_label = "Demolish"
		_: tool_label = "?"

	tool_chip.text = "Tool: " + tool_label

func _on_toast_timeout() -> void:
	if toast_label != null:
		toast_label.visible = false
