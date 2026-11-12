plugins {
    kotlin("jvm") version "2.3.0"
    application
}
repositories { mavenCentral(); google() }
dependencies { implementation("org.jetbrains.compose.ui:ui-graphics-desktop:1.9.2") }
kotlin { jvmToolchain(17) }
application { mainClass.set("ExportKt") }
// Only Android's pure theme files: Theme.kt needs material3 and fonts.
sourceSets { main { kotlin { srcDir("src/main/kotlin"); srcDir(System.getenv("THEME_DIR")); exclude("**/Theme.kt") } } }
