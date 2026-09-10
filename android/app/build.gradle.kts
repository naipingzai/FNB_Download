plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
apply(plugin = "com.chaquo.python")

android {
    namespace = "com.advancedownloader.flutter_download_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.advancedownloader.flutter_download_manager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Chaquopy Python 配置
        python {
            version = "3.12"
            pip {
                // 原生引擎依赖（纯 Python / C 扩展兼容 Chaquopy）
                install("httpx[http2]")
                install("pyyaml")
                install("gmssl")
                install("lxml")
                install("aiofiles")
                install("aiosqlite")
                install("emoji")
                install("openpyxl")
                install("rich")
                install("fastapi")
                install("uvicorn")
                install("websockets")
                // pydantic 和 curl_cffi 由 compat shim 提供，无需 pip 安装
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
