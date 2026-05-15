class_name ContractState
extends RefCounted

signal active_changed(contracts: Array)

## Currently accepted contracts. Empty when none are active.
var active: Array[Contract] = []:
	set(v):
		active = v
		active_changed.emit(v)
