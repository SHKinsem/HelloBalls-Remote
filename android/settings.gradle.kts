pluginManagement {
    val uniVersions = java.util.Properties().apply {
        file("../vendor/uni-frame/integrations/android/toolchain.properties").inputStream().use { load(it) }
    }
    plugins {
        id("com.tencent.shadow.plugin") version uniVersions.getProperty("shadowVersion")
        id("com.android.application") version uniVersions.getProperty("agpVersion")
        id("org.jetbrains.kotlin.android") version uniVersions.getProperty("kotlinVersion")
    }
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        mavenLocal() // P1: Shadow built from pinned b2a7a74 in the cloud workspace.
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.tencent.shadow.plugin") apply false
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}

include(":app")
