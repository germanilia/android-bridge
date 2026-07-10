pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "android_bridge"

// Shared protocol module lives at repo-root protocol/kotlin (canonical layout).
include(":protocol")
project(":protocol").projectDir = file("../protocol/kotlin")

include(":app")
