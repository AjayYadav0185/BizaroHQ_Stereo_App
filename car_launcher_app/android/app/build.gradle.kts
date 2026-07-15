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
        // TopWay TS7 with SC7731E runs Android 8.1/9 - API 26-28
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Required for model_viewer_plus WebView rendering on Android 8-10
        // Enables multi-dex for older devices that need it
        multiDexEnabled = true

        // CRITICAL: TopWay TS7 uses ARMv7 (32-bit) Unisoc SC7731E
        // Must build for armeabi-v7a to ensure native libraries work
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // Ensure we target ARMv7 specifically for SC7731E compatibility
    splits {
        abi {
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            // Add your own signing config for production builds
            // Signing with debug keys for development
            signingConfig = signingConfigs.getByName("debug")
            // Enable minification for smaller APK size on 32GB storage
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Packaging options for native libraries
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
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