package dev.dcltdw.catalog

import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest

/**
 * Proves the Spring context wires up. Cheap, and it catches the class of
 * mistake — a missing bean, a bad property placeholder — that otherwise only
 * shows up when the container starts on EC2.
 */
@SpringBootTest
class CatalogApplicationTest {
    @Test
    fun `application context loads`() {
        // The @SpringBootTest annotation is the assertion: this fails if the
        // context cannot be built.
    }
}
