plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.circuit_detector_app"

    // ✅ Use Flutter’s provided values (recommended)
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.circuit_detector_app"
        minSdk = 21                   // or: flutter.minSdkVersion
        targetSdk = 34                // or: flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // Temporary: use debug signing until you set up release key
            signingConfig = signingConfigs.getByName("debug")

            // Disable shrinking for easier debugging now
            isMinifyEnabled = false
            isShrinkResources = false
        }

        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        // ✅ Java 17 is the default for Flutter templates
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    dependencies {
        implementation("androidx.core:core-ktx:1.13.1")
        implementation("androidx.appcompat:appcompat:1.7.0")
        implementation("com.google.android.material:material:1.12.0")
        implementation("androidx.activity:activity-ktx:1.9.3")
}

}

flutter {
    // Path to your Flutter module relative to this file
    source = "../.."
}
