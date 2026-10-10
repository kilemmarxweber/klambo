package com.klambocore.klambo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** Relance l'écoute des messages après un redémarrage / mise à jour. */
class AlertBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val bootActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_USER_UNLOCKED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
        if (action !in bootActions) return
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val token = prefs.getString("flutter.klambo_auth_token", null)
        if (token.isNullOrBlank()) return
        val wanted = prefs.getBoolean("flutter.klambo_bg_wanted", true)
        if (!wanted) return
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, AlertConnectionService::class.java)
                    .setAction(AlertConnectionService.ACTION_START),
            )
        } catch (error: Exception) {
            android.util.Log.w("klambo", "boot/update FGS start failed: $action", error)
        }
    }
}
