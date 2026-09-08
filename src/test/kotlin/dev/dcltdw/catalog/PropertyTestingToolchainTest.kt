package dev.dcltdw.catalog

import io.kotest.property.Arb
import io.kotest.property.arbitrary.int
import io.kotest.property.checkAll
import kotlinx.coroutines.runBlocking
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

/**
 * Proves the property-testing toolchain is wired up and running, rather than
 * merely declared in the version catalog. MockK and Testcontainers are both on
 * the test classpath without a single test importing them; this exists so
 * kotest-property does not become a third.
 *
 * It asserts nothing about this project's domain, and it is meant to be
 * **deleted** once real property tests exist on the rules AST — at which point
 * the library is proven by work that matters.
 *
 * Note `runBlocking`: kotest-property's `checkAll` is a suspend function, so it
 * needs a coroutine scope even though nothing here is concurrent. That is the
 * one piece of ceremony to remember when using it from a plain JUnit test.
 */
class PropertyTestingToolchainTest {
    // Block bodies, not expression bodies. `= runBlocking { checkAll(...) }`
    // would make the test method return PropertyContext, and JUnit 5 requires
    // test methods to return Unit.

    @Test
    fun `checkAll generates cases and runs the assertion for each`() {
        var cases = 0

        runBlocking {
            // Type-inferred generators: kotest supplies an Arb<Int> for Int,
            // including the edge cases a hand-written test forgets — 0,
            // Int.MIN_VALUE, Int.MAX_VALUE.
            checkAll<Int, Int> { a, b ->
                cases++
                assertThat(a + b).isEqualTo(b + a)
            }
        }

        // The default is 1000 cases. Asserting on the count proves the
        // generator actually ran rather than the block being skipped.
        assertThat(cases).isEqualTo(1000)
    }

    @Test
    fun `an explicit Arb constrains the generated range`() {
        runBlocking {
            // The form used for domain generators later: an explicit Arb whose
            // range encodes a precondition, so invalid values are never
            // generated instead of being filtered out inside the test.
            checkAll(Arb.int(1..100), Arb.int(1..100)) { a, b ->
                assertThat(a + b).isBetween(2, 200)
            }
        }
    }
}
