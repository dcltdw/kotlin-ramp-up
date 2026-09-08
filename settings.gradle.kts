plugins {
    // Lets Gradle download a JDK when the build asks for one that is not
    // installed. Needed because detekt has to run on an older JDK than the
    // project compiles with — see the detekt block in build.gradle.kts.
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "catalog-personalization"
