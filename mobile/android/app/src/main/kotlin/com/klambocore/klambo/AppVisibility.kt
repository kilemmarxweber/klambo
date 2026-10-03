package com.klambocore.klambo

/** État partagé activité Flutter / service d'alertes. */
object AppVisibility {
    @Volatile
    var inForeground: Boolean = false

    @Volatile
    var serviceRunning: Boolean = false
}
