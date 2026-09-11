extends Node
## Autoload-ready interface boundary for Google Play Billing. Deliberately
## unimplemented — CURRENT PRIORITY is core gameplay, not monetization —
## but the shape exists now so billing can be wired in later without
## touching gameplay/economy code.
##
## SECURITY: purchase completion must NOT directly grant entitlements from
## the client. `purchase_completed` should only be treated as "pending
## server verification"; a trusted backend (Cloud Function) validates the
## Play purchase token and grants the entitlement server-side. See
## docs/SECURITY.md.

signal products_loaded(product_ids: Array[String])
signal purchase_completed(product_id: String, purchase_token: String)
signal purchase_failed(product_id: String, reason: String)
signal purchase_restored(product_id: String)

func query_products(_product_ids: Array[String]) -> void:
	push_warning("IapService.query_products: Google Play Billing not yet integrated")

func purchase(_product_id: String) -> void:
	push_warning("IapService.purchase: Google Play Billing not yet integrated")

func restore_purchases() -> void:
	push_warning("IapService.restore_purchases: Google Play Billing not yet integrated")
