# Keep Flutter & plugin classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep SQLCipher JNI bindings
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# Keep ONNX Runtime JNI bindings
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Keep AndroidX Security Crypto (flutter_secure_storage)
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Keep Google ML Kit Text Recognition (on-device OCR)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Flutter Play Store Deferred Components (optional Play Core classes not bundled in offline builds)
-dontwarn com.google.android.play.core.**

# Keep DocSift native AutofillService & Biometric Auth Activity
-keep class com.docsift.docsift.** { *; }




