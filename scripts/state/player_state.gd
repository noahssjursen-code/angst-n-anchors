class_name PlayerState
extends RefCounted

signal marks_changed(balance: int)
signal display_name_changed(name: String)

var marks: int = 0:
	set(v):
		marks = v
		marks_changed.emit(v)

var display_name: String = "Captain":
	set(v):
		display_name = v
		display_name_changed.emit(v)
