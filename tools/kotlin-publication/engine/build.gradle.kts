import java.io.File
import org.gradle.api.publish.PublishingExtension
import org.gradle.api.publish.maven.MavenPublication
import org.gradle.jvm.tasks.Jar
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The nine Maven publications of the generated Kotlin tree (bundle kotlin-f32).
//
// This module compiles the tree the boring driver generates and publishes the
// nine artifacts under the coordinates below. Nothing in here writes into the
// generated tree.
plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("maven-publish")
}

// The generated trees are driver outputs, not repository sources. The default
// is this repository's own kotlin-f32 emission (bun run gen:kotlin-f32); a caller
// that generates the tree somewhere else (a pack run writes it under its own
// outRoot) overrides the two properties. A relative override resolves against
// this Gradle project root, an absolute one is used as is.
fun generatedTree(property: String, default: File): File {
    val configured = providers.gradleProperty(property).orNull?.takeIf { it.isNotBlank() } ?: return default
    val candidate = File(configured)
    return if (candidate.isAbsolute) candidate else rootProject.projectDir.resolve(configured).normalize()
}


// The publication-name to artifactId suffix mapping: the kotlinMultiplatform
// publication is the root coordinate, jvm and android keep their own suffix,
// every other target is its lowercase name.
fun publicationSuffix(publicationName: String): String = when (publicationName) {
    "kotlinMultiplatform" -> ""
    "jvm" -> "-jvm"
    "android" -> "-android"
    else -> "-" + publicationName.lowercase()
}

val genDir = generatedTree("kotlinGenDir", rootProject.projectDir.parentFile.parentFile.resolve("reference/kotlin-f32/gen"))
val genTestsDir = generatedTree("kotlinGenTestsDir", rootProject.projectDir.parentFile.parentFile.resolve("reference/kotlin-f32/gen-tests"))

kotlin {
    // The generated tree carries no expect/actual classes, but the compiler
    // option keeps a future emission with one from turning into a build error.
    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }
    jvm()
    android {
        namespace = "org.tiqian.engine"
        compileSdk = 36
        minSdk = 23
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
    macosArm64()
    iosArm64()
    iosSimulatorArm64()
    linuxX64()
    linuxArm64()
    mingwX64()

    sourceSets {
        commonMain {
            kotlin.setSrcDirs(listOf(genDir))
        }
    }
}

// The generated suite carries @boring.test.Test cases and is not a JUnit suite,
// so it gets its own JVM compilation and runs through the generated TestMainKt.
// No dependencies are declared for this compilation on purpose. The generated
// suite imports only packages this tree emits (org.tiqian.*, std.UStringException)
// and kotlin.math.pow, with no kotlinx, platform, skiko or skia symbol anywhere
// in the emitted gen and gen-tests trees. The runtime classpath below carries
// the Kotlin standard library plus annotations. Check that observation before
// adding a dependency here.
val jvmGeneratedTestCompilation = kotlin.targets.getByName("jvm").compilations.create("generatedTest") {
    defaultSourceSet.dependsOn(kotlin.sourceSets.getByName("commonMain"))
}
jvmGeneratedTestCompilation.associateWith(kotlin.targets.getByName("jvm").compilations.getByName("main"))
jvmGeneratedTestCompilation.defaultSourceSet.kotlin.setSrcDirs(listOf(genTestsDir))

tasks.register<JavaExec>("generatedTestSuite") {
    group = "verification"
    description = "Runs the generated Kotlin test suite through gen-tests/TestMainKt."
    dependsOn(jvmGeneratedTestCompilation.compileTaskProvider)
    mainClass.set("TestMainKt")
    // The generated golden constants load their text from the bundle resource
    // directory, so it has to sit on the classpath exactly as the driver puts it.
    classpath = files(jvmGeneratedTestCompilation.output.allOutputs) +
        files(genDir.resolve("resources")) +
        configurations.named("jvmRuntimeClasspath").get()
    environment("BORING_TEST_TIMEOUT_MS", "600000")
    environment(
        "BORING_TEST_RESULTS",
        layout.buildDirectory.file("test-results/generated-suite.jsonl").get().asFile.absolutePath,
    )
    // The generated suite writes trace goldens at
    // <workingDir>/engine-haxe/out/kotlin-traces; the repository root is the
    // working directory the suite expects and boring's .gitignore already
    // excludes engine-haxe/, so the traces stay out of a commit.
    workingDir = rootProject.projectDir.parentFile.parentFile
}

// The artifactId and POM below are the published identity of these artifacts.
// They do not change with the location of this project.
afterEvaluate {
    extensions.configure<PublishingExtension>("publishing") {
        publications.withType(MavenPublication::class.java).configureEach {
            val publicationName = name
            artifactId = "tiqian-engine" + publicationSuffix(publicationName)
            artifact(
                tasks.register<Jar>("${publicationName}PublicationJavadocJar") {
                    archiveBaseName.set("${project.name}-$publicationName")
                    archiveClassifier.set("javadoc")
                },
            )
            pom {
                name.set("Tiqian Engine")
                description.set(
                    "The Tiqian CJK paragraph layout engine: document and layout data types, font " +
                        "and shaping contracts, line breaking, and Chinese composition rules.",
                )
                url.set("https://github.com/tiqian-cjk/tiqian")
                licenses {
                    license {
                        name.set("Mozilla Public License 2.0")
                        url.set("https://www.mozilla.org/MPL/2.0/")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("123Duo3")
                        name.set("123Duo3")
                        email.set("123duo3@gmail.com")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/tiqian-cjk/tiqian.git")
                    developerConnection.set("scm:git:ssh://git@github.com/tiqian-cjk/tiqian.git")
                    url.set("https://github.com/tiqian-cjk/tiqian")
                }
            }
        }
}
}

// The Kotlin plugin assigns the default artifactId of a native publication in
// its own projectsEvaluated callback, which is later than afterEvaluate; a final
// pass in the same event (registered after the plugin) keeps the coordinates.
val publishingExtension = extensions.getByType(PublishingExtension::class.java)
gradle.projectsEvaluated {
    publishingExtension.publications.withType(MavenPublication::class.java).configureEach {
        artifactId = "tiqian-engine" + publicationSuffix(name)
    }
}
