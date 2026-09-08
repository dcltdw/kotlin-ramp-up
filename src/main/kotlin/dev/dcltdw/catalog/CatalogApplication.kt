package dev.dcltdw.catalog

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class CatalogApplication

// Detekt's SpreadOperator rule is right in general — a spread copies the array.
// It fires once here, on the canonical Spring Boot entry point, where the copy
// happens once at startup on an argv-sized array. Suppressed narrowly rather
// than disabling the rule, so it still applies everywhere it matters.
@Suppress("SpreadOperator")
fun main(args: Array<String>) {
    runApplication<CatalogApplication>(*args)
}
