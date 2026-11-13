package com.shkinsem.helloballs_remote

import android.app.Application
import android.util.Log

/** Explicit subclass lets Shadow transform Flutter's default Android Application. */
class UniProjectApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Log.i("UniProject", "Downloaded application initialized: com.shkinsem.helloballs_remote; application-adapter-v2")
    }
}
