extends Node
## Autoload "AudioSettings". Owns the Music/SFX audio buses and every
## player-facing audio/haptics preference, persisted locally. Audio and
## Music (the SFX and adaptive-music autoloads) read the bus names from
## here; nothing else should touch AudioServer bus volume directly.

signal settings_changed()

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var music_enabled: bool = true
var sfx_enabled: bool = true
var haptics_enabled: bool = true
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0

func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_load()
	_apply()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _load() -> void:
	music_enabled = bool(SaveService.get_value("music_enabled", true))
	sfx_enabled = bool(SaveService.get_value("sfx_enabled", true))
	haptics_enabled = bool(SaveService.get_value("haptics_enabled", true))
	master_volume = float(SaveService.get_value("master_volume", 1.0))
	music_volume = float(SaveService.get_value("music_volume", 0.8))
	sfx_volume = float(SaveService.get_value("sfx_volume", 1.0))

func _persist() -> void:
	SaveService.set_value("music_enabled", music_enabled)
	SaveService.set_value("sfx_enabled", sfx_enabled)
	SaveService.set_value("haptics_enabled", haptics_enabled)
	SaveService.set_value("master_volume", master_volume)
	SaveService.set_value("music_volume", music_volume)
	SaveService.set_value("sfx_volume", sfx_volume)
	SaveService.save()

func _apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	var midx := AudioServer.get_bus_index(MUSIC_BUS)
	AudioServer.set_bus_volume_db(midx, linear_to_db(clampf(music_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(midx, not music_enabled)
	var sidx := AudioServer.get_bus_index(SFX_BUS)
	AudioServer.set_bus_volume_db(sidx, linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(sidx, not sfx_enabled)
	Haptics.enabled = haptics_enabled

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_apply()
	_persist()
	settings_changed.emit()

func set_sfx_enabled(value: bool) -> void:
	sfx_enabled = value
	_apply()
	_persist()
	settings_changed.emit()

func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_apply()
	_persist()
	settings_changed.emit()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply()
	_persist()
	settings_changed.emit()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply()
	_persist()
	settings_changed.emit()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply()
	_persist()
	settings_changed.emit()
