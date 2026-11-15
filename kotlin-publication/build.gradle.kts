// Root build of boring's Kotlin publication project (see settings.gradle.kts).
// The coordinates and POM below are the ones the tiqian-engine publications have
// always carried; moving the publication host must not move them.
plugins {
    kotlin("multiplatform") version "2.3.20" apply false
    id("com.android.kotlin.multiplatform.library") version "9.3.1" apply false
}

group = "org.tiqian"
version = providers.gradleProperty("tiqianVersion")
    .orElse(providers.environmentVariable("TIQIAN_VERSION"))
    .getOrElse("0.1.0-SNAPSHOT")

subprojects {
    group = rootProject.group
    version = rootProject.version
}
