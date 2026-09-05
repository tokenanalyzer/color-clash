extends Node
## Autoload "GameData". Boot-time loader for every data-driven config file
## under game/data/. Everything here is read-only after _ready() — this is
## the single source of truth gameplay code consults for balancing values,
## so rebalancing only ever means editing JSON, never GDScript.

var colors: PieceColorPalette
var power_config: PowerConfig
var fever_config: FeverConfig
var boosters: Dictionary = {} # StringName -> Dictionary
## Flavor label per power-pair combo (data/power_combos.json), keyed
## "<power_a>+<power_b>" sorted alphabetically. board_view.gd derives the
## actual tint/sound from the pair itself — this is just the display name.
var power_combo_labels: Dictionary = {} # String -> String
var levels: LevelDatabase
var sfx: SfxConfig
var music: MusicConfig
## In-level "Need More Moves?" continue tiers (data/economy.json). Boosters
## keep their prices in data/boosters.json; this is only the extra-moves offer.
var continue_offers: ContinueOffers

func _ready() -> void:
	colors = PieceColorPalette.from_dict(JsonLoader.load_json("res://data/colors.json"))
	power_config = PowerConfig.from_dict(JsonLoader.load_json("res://data/powers.json"))
	fever_config = FeverConfig.from_dict(JsonLoader.load_json("res://data/fever.json"))

	var boosters_data := JsonLoader.load_json("res://data/boosters.json")
	for b in boosters_data.get("boosters", []):
		boosters[StringName(String(b["id"]))] = b

	power_combo_labels = JsonLoader.load_json("res://data/power_combos.json").get("combos", {})

	levels = LevelDatabase.from_dict(JsonLoader.load_json("res://data/levels.json"))
	sfx = SfxConfig.from_dict(JsonLoader.load_json("res://data/sfx.json"))
	music = MusicConfig.from_dict(JsonLoader.load_json("res://data/music.json"))
	continue_offers = ContinueOffers.from_dict(JsonLoader.load_json("res://data/economy.json"))
