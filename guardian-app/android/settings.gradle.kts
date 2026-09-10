pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// ───────────────────────────────────────────────────────────────────────────
// maplibre_gl 0.27.0 的 android/build.gradle 在 AGP >= 9 时不再自行应用 Kotlin
// 插件（AGP 9 若被插件重复应用 KGP 会破坏宿主构建），而是假设 AGP 会提供
// `kotlin { }` 扩展。但 Flutter 模板显式关闭了 AGP 的内置 Kotlin
// （gradle.properties: android.builtInKotlin=false），仍走 KGP 路线，
// 于是该插件评估时报 "Could not find method kotlin()"。
//
// 这里只针对这一个插件项目显式补上 KGP，其余项目不受影响。
// 待 maplibre_gl 适配 Flutter 的 KGP 模式后可删除本段。
// ───────────────────────────────────────────────────────────────────────────
// beforeProject 接收 IsolatedAction<Project>，在 Kotlin DSL 中是接收者形式，
// 因此 lambda 内 this 即 Project。
gradle.lifecycle.beforeProject {
    if (name == "maplibre_gl") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
}
