plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter app plugin – integrates the Flutter module
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.circuit_detector_app"

    // High enough for camera plugin (it asked for 36)
    compileSdk = 36

    // Use the NDK version you actually have installed
    ndkVersion = "26.3.11579264"

    defaultConfig {
        applicationId = "com.example.circuit_detector_app"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    compileOptions {
        // AGP 8.x expects Java 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // Use debug keystore for now so `flutter run --release` works
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    // path from android/ to Flutter project root
    source = "../.."
}
