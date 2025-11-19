import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    // Load flutter.sdk path from local.properties
    val properties = java.util.Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    val flutterSdkPath = properties.getProperty("flutter.sdk")
        ?: throw GradleException("flutter.sdk not set in local.properties")

    // Let Flutter's Gradle tools participate
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // ✅ THIS is where the Flutter plugin loader must be applied
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Android + Kotlin plugin versions (match Flutter’s tooling)
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

dependencyResolutionManagement {
    // Default from Flutter template
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

rootProject.name = "circuit_detector_app"
include(":app")
