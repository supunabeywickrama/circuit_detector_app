// Top-level Gradle file for the Android host app.
// For most Flutter projects, this file can stay minimal.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
