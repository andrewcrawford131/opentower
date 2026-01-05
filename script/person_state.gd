# FILE: res://script/person_state.gd
class_name PersonState
extends RefCounted

var id: int = 0
var cell: Vector2i = Vector2i.ZERO
var pos: Vector2 = Vector2.ZERO

var goal: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var path_index: int = 0

var has_home: bool = false
var home_cell: Vector2i = Vector2i(999999, 999999)

var wait: float = 0.0
