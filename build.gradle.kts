import io.gitlab.arturbosch.detekt.Detekt
import io.gitlab.arturbosch.detekt.DetektCreateBaselineTask
import io.gitlab.arturbosch.detekt.getSupportedKotlinVersion

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
    alias(libs.plugins.detekt)
    alias(libs.plugins.kover)
    alias(libs.plugins.ktlint)
}

group = "dev.dcltdw"
version = "0.1.0"

java {
    // Java 21 rather than 25. Both are LTS and the plan allows either, but
    // detekt 1.23.8 cannot run on a JDK 25 and there is no detekt that can
    // yet. 21 costs nothing here and avoids building the whole toolchain
    // around a linter workaround.
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

kotlin {
    compilerOptions {
        // Treat JSR-305 @Nullable/@Nonnull as hard Kotlin types rather than
        // platform types. This is what makes the Day 4 Java adapter a real
        // null-safety exercise instead of a source of silent NPEs.
        freeCompilerArgs.addAll("-Xjsr305=strict")
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.actuator)
    implementation(libs.jackson.module.kotlin)
    implementation(libs.kotlin.reflect)
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.mockk)
    testImplementation(libs.testcontainers.junit.jupiter)
    testImplementation(libs.kotest.property)
    testImplementation(libs.kotlinx.coroutines.core)
}

detekt {
    buildUponDefaultConfig = true
    config.setFrom(files("$rootDir/config/detekt/detekt.yml"))
}

// Detekt 1.23.8 is built against Kotlin 2.0.21 and refuses to run on a newer
// compiler. Pin only detekt's own analysis classpath to the version it
// supports; the project itself still compiles with Kotlin 2.4.10. This is
// detekt's documented workaround and can go away when a detekt supporting
// Kotlin 2.4 ships.
configurations.matching { it.name == "detekt" }.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin") {
            useVersion(getSupportedKotlinVersion())
        }
    }
}

// Detekt runs in-process in the Gradle daemon rather than a forked JVM, so it
// sees whatever JDK the daemon runs on. That is pinned to 21 in
// gradle/gradle-daemon-jvm.properties; its bundled IntelliJ JavaVersion.parse()
// throws outright on "25".
tasks.withType<Detekt>().configureEach {
    jvmTarget = "21"
}
tasks.withType<DetektCreateBaselineTask>().configureEach {
    jvmTarget = "21"
}

kover {
    reports {
        filters {
            excludes {
                // The @SpringBootApplication class is a main() and an
                // annotation; there is nothing in it worth asserting.
                classes("dev.dcltdw.catalog.CatalogApplicationKt")
            }
        }

        verify {
            // Without a rule, koverVerify passes vacuously — it did until now,
            // so "coverage is enforced" was a claim the build did not support.
            rule {
                minBound(
                    minValue = 80,
                    coverageUnits = kotlinx.kover.gradle.plugin.dsl.CoverageUnit.LINE,
                )
            }

            // Deliberately LINE only, and deliberately 80 rather than higher.
            //
            // No BRANCH bound yet: there are no branches in the codebase today,
            // and a bound over zero branches measures nothing. Day 2's sealed
            // `when` blocks are almost entirely branches, so that is the point
            // to add one.
            //
            // 80 is a floor, not a target. The domain code on Day 2 is pure
            // functions with hand-written tests and should sit far above it;
            // the floor exists to catch a regression, not to define done. Set
            // it at today's actual 100% and the first hard-to-cover Spring
            // branch on Day 3 turns the gate into an argument to be won rather
            // than a signal.
        }
    }
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
}

// bootJar is the artifact that ships. The plain jar is not runnable on its own
// and only makes build/libs ambiguous for the Dockerfile's COPY.
tasks.named<Jar>("jar") {
    enabled = false
}
