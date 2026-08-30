extends Node
## Autoload "Economy". Soft-currency (coins) balance for offline/local play.
##
## SECURITY BOUNDARY: this is a client-trusted convenience store for the
## free coin economy only (level rewards, daily rewards, spending on
## boosters). It must never be extended to grant premium/purchased currency
## — that requires a trusted server-side path (Cloud Function + purchase
## receipt validation) per docs/SECURITY.md. Treat any future "hard
## currency" as a separate, server-authoritative balance, not an extension
## of `coins`.

signal coins_changed(new_balance: int)

const STARTER_COINS := 500

var coins: int = 0

func _ready() -> void:
	coins = SaveService.get_int("coins", STARTER_COINS)

func can_afford(amount: int) -> bool:
	return coins >= amount

func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_afford(amount):
		return false
	coins -= amount
	_persist()
	coins_changed.emit(coins)
	return true

func grant(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	_persist()
	coins_changed.emit(coins)

func _persist() -> void:
	SaveService.set_int("coins", coins)
	SaveService.save()
