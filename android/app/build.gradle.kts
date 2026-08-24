import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

val versionText = File(rootProject.projectDir, "../VERSION").readText().let { value ->
    if (!value.endsWith("\n") || value.count { it == '\n' } != 1) {
        throw GradleException("VERSION must contain exactly one newline-terminated version.")
    }
    value.dropLast(1)
}
val versionMatch = Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matchEntire(versionText)
    ?: throw GradleException("VERSION must be MAJOR.MINOR.PATCH with strict decimal components.")
val versionParts = versionMatch.groupValues.drop(1).map { component ->
    component.toLongOrNull() ?: throw GradleException("VERSION component is out of range.")
}
if (versionParts[0] > 2_100 || versionParts[1] > 999 || versionParts[2] > 999) {
    throw GradleException("VERSION components derive an Android version code outside 1...2100000000.")
}
val versionCodeValue = versionParts[0] * 1_000_000L + versionParts[1] * 1_000L + versionParts[2]
if (versionCodeValue !in 1L..2_100_000_000L) {
    throw GradleException("VERSION derives an Android version code outside 1...2100000000.")
}
val releaseSigningVariables = listOf(
    "ANDROID_RELEASE_STORE_FILE",
    "ANDROID_RELEASE_STORE_PASSWORD",
    "ANDROID_RELEASE_KEY_ALIAS",
    "ANDROID_RELEASE_KEY_PASSWORD",
)
val releaseSigningValues = releaseSigningVariables.associateWith { providers.environmentVariable(it).orNull }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val missingReleaseSigningVariables = releaseSigningVariables.filter { releaseSigningValues[it].isNullOrEmpty() }
if (releaseRequested && missingReleaseSigningVariables.isNotEmpty()) {
    throw GradleException("Release signing requires: ${missingReleaseSigningVariables.joinToString(", ")}")
}

android {
    namespace = "com.androidbridge"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.androidbridge"
        minSdk = 33
        targetSdk = 34
        versionCode = versionCodeValue.toInt()
        versionName = versionText
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    if (missingReleaseSigningVariables.isEmpty()) {
        signingConfigs.create("release") {
            storeFile = file(requireNotNull(releaseSigningValues["ANDROID_RELEASE_STORE_FILE"]))
            storePassword = requireNotNull(releaseSigningValues["ANDROID_RELEASE_STORE_PASSWORD"])
            keyAlias = requireNotNull(releaseSigningValues["ANDROID_RELEASE_KEY_ALIAS"])
            keyPassword = requireNotNull(releaseSigningValues["ANDROID_RELEASE_KEY_PASSWORD"])
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            if (missingReleaseSigningVariables.isEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    testOptions {
        unitTests.all { it.useJUnitPlatform() }
    }

    packaging {
        resources {
            // BouncyCastle jars each ship this OSGi manifest — keep one.
            excludes += "/META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }
}

dependencies {
    implementation(project(":protocol"))

    implementation(platform("androidx.compose:compose-bom:2024.09.03"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.lifecycle:lifecycle-service:2.8.6")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")

    testImplementation("io.kotest:kotest-runner-junit5:5.9.1")
    testImplementation("io.kotest:kotest-assertions-core:5.9.1")
    testImplementation("io.kotest:kotest-property:5.9.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
