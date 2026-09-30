plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.sunway.l850tdemo"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.sunway.l850tdemo"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("system") {
            // 方式一：使用密钥文件（推荐）
            storeFile = file("release.jks")  // 或 .jks 文件
            storePassword = "android"
            keyAlias = "platform"
            keyPassword = "android"

            // 方式二：使用 .pk8 + .pem 证书（Android 源码签名）
            // 需要转换为 keystore 格式，或使用 v1/v2 签名工具
        }

        create("release") {
            storeFile = file("release.jks")
            storePassword = "123456"
            keyAlias = "release"
            keyPassword = "release"
        }
    }

    // 启用ViewBinding核心配置
    buildFeatures {
        buildConfig = true // 启用 BuildConfig 生成
        viewBinding = true  // 开启ViewBinding
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(libs.appcompat)
    implementation(libs.material)
    implementation(libs.activity)
    implementation(libs.constraintlayout)
    testImplementation(libs.junit)
    androidTestImplementation(libs.ext.junit)
    androidTestImplementation(libs.espresso.core)

    // Lifecycle (ViewModel + LiveData)
    implementation(libs.viewmodel)
    implementation(libs.livedata)

    //
    implementation(files("libs/sdk850-v1.0-release.aar"))

    implementation("com.licheedev:android-serialport:2.1.4")

    compileOnly("org.projectlombok:lombok:1.18.30")
    annotationProcessor("org.projectlombok:lombok:1.18.30")

    implementation("com.github.CymChad:BaseRecyclerViewAdapterHelper:3.0.12")
    implementation("androidx.recyclerview:recyclerview:1.2.1")
}