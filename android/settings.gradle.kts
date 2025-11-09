// android/settings.gradle.kts
pluginManagement {
    // --- Load Flutter SDK path ---
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        props.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // --- Plugin repositories ---
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // --- Declare plugin versions (DO NOT apply here) ---
    plugins {
        id("com.android.application") version "8.7.0"
        id("com.android.library") version "8.7.0"
        id("org.jetbrains.kotlin.android") version "1.9.24"
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
    repositories {
        google()
        mavenCentral()
    }
}

// --- Flutter project name and app module ---
rootProject.name = "circuit_detector_app"
include(":app")
