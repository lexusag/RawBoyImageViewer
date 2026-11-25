plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(libs.junit)
    testImplementation(libs.json)
}

// The Mac app's fixtures and sample files are the conformance suite: tests read them in place.
tasks.test {
    systemProperty("fixtures.dir", rootProject.file("../Packages/Tests/RawBoyBrowseKitTests/Fixtures").absolutePath)
    systemProperty("swift.tests.dir", rootProject.file("../Packages/Tests/RawBoyBrowseKitTests").absolutePath)
}
