package com.shkinsem.helloballs_remote

import android.content.Context
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // FlutterEngine recreates its package context to locate assets. Keep the plugin's assets,
    // since asking Android for the host package would return the empty host asset bundle.
    override fun createPackageContext(packageName: String, flags: Int): Context =
        if (packageName == this.packageName && flags == 0) this
        else super.createPackageContext(packageName, flags)
}
