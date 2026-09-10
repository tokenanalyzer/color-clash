package com.colorclash.admob

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback

/**
 * Minimal native AdMob bridge for War of Love.
 *
 * Deliberately thin: it only loads/shows a rewarded ad and an interstitial
 * ad and reports every lifecycle step back to GDScript through a SINGLE
 * generic signal, `ad_event(event, message)`. ALL policy — reward-once
 * guarding, interstitial frequency caps, cooldowns, failure-safe fallback —
 * lives in GDScript (`scripts/services/ads_service.gd`), never here.
 *
 * Registered as the Godot singleton "ColorClashAdMob" via a
 * <meta-data android:name="org.godotengine.plugin.v1.ColorClashAdMob"> entry
 * in AndroidManifest.xml. Compiled straight into the app module (no separate
 * .aar); the only external dependency is play-services-ads.
 */
class ColorClashAdMob(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val PLUGIN_NAME = "ColorClashAdMob"
        const val SIGNAL_AD_EVENT = "ad_event"
    }

    @Volatile private var initialized = false
    private var rewardedAd: RewardedAd? = null
    private var interstitialAd: InterstitialAd? = null
    private var lastRewardedUnitId: String = ""
    private var lastInterstitialUnitId: String = ""

    override fun getPluginName() = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(
        // event, message
        SignalInfo(SIGNAL_AD_EVENT, String::class.java, String::class.java)
    )

    private fun send(event: String, message: String = "") {
        emitSignal(SIGNAL_AD_EVENT, event, message)
    }

    private fun ui(block: () -> Unit) {
        val a = activity
        if (a != null) a.runOnUiThread { block() } else block()
    }

    // ---------------------------------------------------------------- init --

    @UsedByGodot
    fun initialize(useTestDevices: Boolean) {
        if (initialized) {
            send("initialized", "already")
            return
        }
        ui {
            val ctx = activity?.applicationContext ?: godot.getContext()
            if (ctx == null) {
                send("init_failed", "no_context")
                return@ui
            }
            if (useTestDevices) {
                // With Google's TEST ad unit ids this is not required, but it
                // also silences the "Test Ad" checks for the emulator and is
                // harmless in production (it only affects debug builds where
                // the caller passes true).
                MobileAds.setRequestConfiguration(
                    RequestConfiguration.Builder()
                        .setTestDeviceIds(listOf(AdRequest.DEVICE_ID_EMULATOR))
                        .build()
                )
            }
            MobileAds.initialize(ctx) {
                initialized = true
                send("initialized", "")
            }
        }
    }

    @UsedByGodot
    fun isInitialized(): Boolean = initialized

    // ------------------------------------------------------------ rewarded --

    @UsedByGodot
    fun loadRewarded(adUnitId: String) {
        lastRewardedUnitId = adUnitId
        ui {
            val ctx = activity?.applicationContext ?: godot.getContext()
            if (ctx == null || !initialized) {
                send("rewarded_load_failed", "not_ready")
                return@ui
            }
            RewardedAd.load(
                ctx, adUnitId, AdRequest.Builder().build(),
                object : RewardedAdLoadCallback() {
                    override fun onAdLoaded(ad: RewardedAd) {
                        rewardedAd = ad
                        send("rewarded_loaded", "")
                    }
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        rewardedAd = null
                        send("rewarded_load_failed", error.message ?: "load_error")
                    }
                }
            )
        }
    }

    @UsedByGodot
    fun isRewardedReady(): Boolean = rewardedAd != null

    /** Shows a preloaded rewarded ad. Returns false if none is ready. */
    @UsedByGodot
    fun showRewarded(): Boolean {
        val ad = rewardedAd ?: run {
            send("rewarded_show_failed", "not_loaded")
            return false
        }
        val a = activity ?: run {
            send("rewarded_show_failed", "no_activity")
            return false
        }
        ui {
            ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                override fun onAdShowedFullScreenContent() = send("rewarded_shown", "")
                override fun onAdDismissedFullScreenContent() {
                    rewardedAd = null
                    send("rewarded_dismissed", "")
                }
                override fun onAdFailedToShowFullScreenContent(error: AdError) {
                    rewardedAd = null
                    send("rewarded_show_failed", error.message ?: "show_error")
                }
            }
            ad.show(a) { reward ->
                send("rewarded_earned", "${reward.type}:${reward.amount}")
            }
        }
        return true
    }

    // -------------------------------------------------------- interstitial --

    @UsedByGodot
    fun loadInterstitial(adUnitId: String) {
        lastInterstitialUnitId = adUnitId
        ui {
            val ctx = activity?.applicationContext ?: godot.getContext()
            if (ctx == null || !initialized) {
                send("interstitial_load_failed", "not_ready")
                return@ui
            }
            InterstitialAd.load(
                ctx, adUnitId, AdRequest.Builder().build(),
                object : InterstitialAdLoadCallback() {
                    override fun onAdLoaded(ad: InterstitialAd) {
                        interstitialAd = ad
                        send("interstitial_loaded", "")
                    }
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        interstitialAd = null
                        send("interstitial_load_failed", error.message ?: "load_error")
                    }
                }
            )
        }
    }

    @UsedByGodot
    fun isInterstitialReady(): Boolean = interstitialAd != null

    /** Shows a preloaded interstitial. Returns false if none is ready. */
    @UsedByGodot
    fun showInterstitial(): Boolean {
        val ad = interstitialAd ?: run {
            send("interstitial_show_failed", "not_loaded")
            return false
        }
        val a = activity ?: run {
            send("interstitial_show_failed", "no_activity")
            return false
        }
        ui {
            ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                override fun onAdShowedFullScreenContent() = send("interstitial_shown", "")
                override fun onAdDismissedFullScreenContent() {
                    interstitialAd = null
                    send("interstitial_dismissed", "")
                }
                override fun onAdFailedToShowFullScreenContent(error: AdError) {
                    interstitialAd = null
                    send("interstitial_show_failed", error.message ?: "show_error")
                }
            }
            ad.show(a)
        }
        return true
    }
}
