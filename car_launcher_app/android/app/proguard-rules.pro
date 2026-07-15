# BizaroHQ Stereo - ProGuard Rules for TopWay TS7
# =================================================
# Device: TopWay TS7 (Unisoc SC7731E ARMv7)
# Android: 8.1/9 (API 26-28)

# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep MethodChannel classes
-keep class com.example.car_launcher_app.** { *; }

# Keep PT2313 Audio IC service
-keep class com.example.car_launcher_app.PT2313AudioService { *; }

# Keep Bluetooth LE service
-keep class com.example.car_launcher_app.BluetoothLeService { *; }

# Keep MainActivity
-keep class com.example.car_launcher_app.MainActivity { *; }

# Keep Android system service interfaces
-keep class android.media.** { *; }
-keep class android.bluetooth.** { *; }

# Keep GATT callback classes
-keep class android.bluetooth.le.** { *; }
-keep class android.bluetooth.BluetoothGatt** { *; }

# Keep I2C communication classes
-keep class java.io.RandomAccessFile { *; }
-keep class java.io.File { *; }

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }

# Keep serialization
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions

# Keep Flutter engine classes
-dontwarn io.flutter.embedding.**
-dontwarn com.google.auto.value.**

# Keep connectivity_plus
-keep class com.example.connectivity.** { *; }

# Keep geolocator
-keep class com.baseflow.geolocator.** { *; }

# Keep path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }