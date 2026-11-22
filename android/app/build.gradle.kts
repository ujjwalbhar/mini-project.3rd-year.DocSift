plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.docsift.docsift"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "26.3.11579264"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    packaging {
        jniLibs {
            // Android 15+ 16 KB page-size support: store .so uncompressed & 16 KB page-aligned.
            useLegacyPackaging = false
            // Dart FFI loads libonnxruntime.so directly; exclude unused Java JNI bridge.
            excludes += "**/libonnxruntime4j_jni.so"
        }
    }

    defaultConfig {
        applicationId = "com.docsift.docsift"
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    // Provides 16 KB ELF-aligned libonnxruntime.so (ABI-compatible with OrtGetApi(14)).
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.22.0")
}

// Mirror APKs from space-safe C:/Users/Public/DocSiftBuild back to <repo>/build/app/outputs/flutter-apk
// so Flutter CLI commands locate them with exit code 0.
tasks.matching {
    it.name == "assembleRelease" || it.name == "assembleDebug" || it.name == "assembleProfile" ||
    it.name == "packageRelease" || it.name == "packageDebug" || it.name == "packageProfile"
}.configureEach {
    if (name.startsWith("assemble")) {
        outputs.upToDateWhen { false }
    }
    doLast {
        val srcDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
        val dstDir = rootProject.projectDir.parentFile.resolve("build/app/outputs/flutter-apk")
        if (srcDir.exists()) {
            dstDir.mkdirs()
            srcDir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    file.copyTo(dstDir.resolve(file.name), overwrite = true)
                }
            }
        }
    }
}
