extends Node
## Autoload-ready interface boundary for AdMob. Deliberately unimplemented
## for the same reason as IapService — this defines the contract gameplay
## code (continue prompts, booster rewards) can already program against.
##
## Rules for the eventual implementation (see docs/GAME_DESIGN.md):
## - Rewarded ads only grant their reward after `ad_reward_earned` fires
##   (i.e. the ad actually completed) — never on request.
## - Interstitials must never interrupt an active chain reaction, a reward
##   animation, or player input; only offer them between levels.

signal rewarded_ad_ready(placement: String)
signal ad_reward_earned(placement: String)
signal ad_dismissed(placement: String)
signal ad_failed(placement: String, reason: String)

func load_rewarded(_placement: String) -> void:
	push_warning("AdsService.load_rewarded: AdMob not yet integrated")

func show_rewarded(_placement: String) -> void:
	push_warning("AdsService.show_rewarded: AdMob not yet integrated")

## Interstitials should only ever be requested from a natural break point
## (level-complete screen, map screen) — never mid-gameplay.
func maybe_show_interstitial(_placement: String) -> void:
	push_warning("AdsService.maybe_show_interstitial: AdMob not yet integrated")
