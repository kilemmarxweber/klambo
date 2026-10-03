package com.klambocore.klambo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** Relance l'écoute des messages après un redémarrage du téléphone. */
class AlertBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_USER_UNLOCKED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val token = context
            .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.klambo_auth_token", null)
        if (token.isNullOrBlank()) return
        ContextCompat.startForegroundService(
            context,
            Intent(context, AlertConnectionService::class.java),
        )
    }
}
