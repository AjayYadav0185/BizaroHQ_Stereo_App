plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.car_launcher_app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // MultiDex + desugaring required for Android 8-10 devices where
        // model_viewer_plus + Flutter plugins can exceed the 64K method limit.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.car_launcher_app"
        // minSdk 24 = Android 7.0. Covers Android 8 (API 26), 9 (API 28), 10 (API 29).
        // model_viewer_plus requires WebView which is available from API 21+, but
        // we target API 24+ for broader plugin compatibility.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Required for model_viewer_plus WebView rendering on Android 8-10
        // Enables multi-dex for older devices that need it
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Add your own signing config for production builds
            // Signing with debug keys for development
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// MultiDex dependency for Android 8-10 method limit workaround
dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    // Java desugaring for modern API features on older devices
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}