extends Node
## Autoload "GameData". Boot-time loader for every data-driven config file
## under game/data/. Everything here is read-only after _ready() — this is
## the single source of truth gameplay code consults for balancing values,
## so rebalancing only ever means editing JSON, never GDScript.

var colors: PieceColorPalette
var power_config: PowerConfig
var fever_config: FeverConfig
var boosters: Dictionary = {} # StringName -> Dictionary
var levels: LevelDatabase

func _ready() -> void:
	colors = PieceColorPalette.from_dict(JsonLoader.load_json("res://data/colors.json"))
	power_config = PowerConfig.from_dict(JsonLoader.load_json("res://data/powers.json"))
	fever_config = FeverConfig.from_dict(JsonLoader.load_json("res://data/fever.json"))

	var boosters_data := JsonLoader.load_json("res://data/boosters.json")
	for b in boosters_data.get("boosters", []):
		boosters[StringName(String(b["id"]))] = b

	levels = LevelDatabase.from_dict(JsonLoader.load_json("res://data/levels.json"))
