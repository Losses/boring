import java.io.File

// Root build of boring's Kotlin publication project (see settings.gradle.kts).
// The coordinates and POM below are the published identity of these artifacts.
plugins {
    kotlin("multiplatform") version "2.3.20" apply false
    id("com.android.kotlin.multiplatform.library") version "9.3.1" apply false
}

group = "org.tiqian"
version = providers.gradleProperty("publicationVersion")
    .getOrElse("0.1.0-SNAPSHOT")

// The driver packages this project into the nix store and runs it from there, so
// the project directory is read-only. mavenDir names the Maven repository the
// publication must fill; Gradle resolves a local repository through the
// maven.repo.local system property, so the project property is mapped onto it
// before any publishing repository is created. buildRoot redirects every
// project's build directory, which keeps the read-only tree untouched.
providers.gradleProperty("mavenDir").orNull?.takeIf { it.isNotBlank() }?.let {
    System.setProperty("maven.repo.local", File(it).absolutePath)
}
providers.gradleProperty("buildRoot").orNull?.takeIf { it.isNotBlank() }?.let { configured ->
    val root = File(configured)
    layout.buildDirectory.set(root.resolve("root"))
    subprojects {
        layout.buildDirectory.set(root.resolve(path.trimStart(':').replace(':', '/')))
    }
}

subprojects {
    group = rootProject.group
    version = rootProject.version
}
