# scripts/autoloads/Net.gd
extends Node

# Which role this process plays. OFFLINE = single-player (local authority).
# SERVER = headless authoritative match server. CLIENT = renders and sends
# commands; never simulates.
enum Mode { OFFLINE, SERVER, CLIENT }

var mode: Mode = Mode.OFFLINE

func is_authority() -> bool:
	return mode != Mode.CLIENT

func is_headless_server() -> bool:
	return mode == Mode.SERVER
