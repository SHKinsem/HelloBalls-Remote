package com.shkinsem.helloballs_remote

import android.app.Application
import android.content.Context
import android.util.Log

/** Explicit subclass lets Shadow transform Flutter's default Android Application. */
class UniProjectApplication : Application() {
    override fun createPackageContext(packageName: String, flags: Int): Context =
        if (packageName == this.packageName && flags == 0) this
        else super.createPackageContext(packageName, flags)

    override fun onCreate() {
        super.onCreate()
        Log.i("UniProject", "Downloaded application initialized: com.shkinsem.helloballs_remote; context-adapter-v3")
    }
}
