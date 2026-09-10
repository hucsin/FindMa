plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.findma.elder"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.findma.elder"
        minSdk = 26          // Android 8.0+（DESIGN 4.1）
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        // 已绑定的自定义域名（DESIGN 6.1 / 11）
        buildConfigField("String", "API_BASE", "\"https://findma.izao.cc/api/v1\"")
        buildConfigField("String", "APP_USER_AGENT", "\"FindMa-Elder/${versionName}\"")

        // 应用内更新：设置页从这里下载新版本 APK
        buildConfigField("String", "UPDATE_URL", "\"https://dl.izao.cc/elder.apk\"")
    }

    buildFeatures {
        buildConfig = true
        viewBinding = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes += setOf("META-INF/*.kotlin_module")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // HTTPS 上报（DESIGN 7.1）
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // 精确闹钟被拒时的兜底调度（DESIGN 5.3）
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // 本地渲染绑定二维码（DESIGN 5.4：本地 ZXing 渲染，不依赖 GMS）
    implementation("com.google.zxing:core:3.5.2")
}
