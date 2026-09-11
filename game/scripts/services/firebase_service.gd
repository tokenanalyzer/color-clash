extends Node
## Autoload-ready interface boundary for Firebase (Auth, Firestore, Cloud
## Functions, Remote Config, Analytics, Crashlytics, App Check).
## Deliberately unimplemented for the same reason as IapService/AdsService.
##
## Boundary rules (see docs/ARCHITECTURE.md, docs/SECURITY.md):
## - Core puzzle gameplay must keep working with every method here a no-op
##   (offline-first). Never gate board/level logic on a Firebase call.
## - Do not send every gameplay action to Firestore; sync_progress() is a
##   checkpoint call (e.g. on level complete / app pause), not per-move.
## - grant_entitlement-shaped operations belong behind call_trusted_function
##   (a Cloud Function), never as a local client-side write.

signal signed_in(user_id: String)
signal sign_in_failed(reason: String)
signal remote_config_updated()
signal cloud_save_synced()
signal cloud_save_failed(reason: String)

func sign_in_anonymously() -> void:
	push_warning("FirebaseService.sign_in_anonymously: Firebase not yet integrated")

func fetch_remote_config() -> void:
	push_warning("FirebaseService.fetch_remote_config: Firebase not yet integrated")

## Checkpoint sync of locally-authoritative progress (coins, level, boosters)
## to Firestore. Local SaveService remains the source of truth for offline
## continuity; this is a best-effort mirror, not a requirement to play.
func sync_progress(_snapshot: Dictionary) -> void:
	push_warning("FirebaseService.sync_progress: Firebase not yet integrated")

func log_analytics_event(_name: String, _params: Dictionary = {}) -> void:
	pass # safe no-op until Analytics is wired in

## The only path sensitive economy/entitlement operations may use once
## implemented — always a server-validated Cloud Function call, never a
## direct Firestore write of a balance from the client.
func call_trusted_function(_function_name: String, _payload: Dictionary) -> void:
	push_warning("FirebaseService.call_trusted_function: Cloud Functions not yet integrated")
