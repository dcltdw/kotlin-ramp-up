package dev.dcltdw.catalog.api

import com.fasterxml.jackson.databind.ObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.test.context.SpringBootTest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

/**
 * Starts the real servlet container on a random port and talks to it over HTTP
 * with the JDK client.
 *
 * MockMvc would be the conventional choice, but Spring Boot 4 moved its
 * autoconfiguration out of the modules this project depends on. Using the JDK
 * client instead costs nothing, exercises the actual server rather than a
 * mocked dispatcher, and does not break when Spring repackages its test
 * support.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PingControllerTest {
    @field:Value("\${local.server.port}")
    private var port: Int = 0

    private val http: HttpClient = HttpClient.newHttpClient()
    private val json = ObjectMapper()

    private fun get(path: String): HttpResponse<String> {
        val request =
            HttpRequest
                .newBuilder(URI.create("http://localhost:$port$path"))
                .GET()
                .build()
        return http.send(request, HttpResponse.BodyHandlers.ofString())
    }

    @Test
    fun `ping reports the service name, version and ok status`() {
        val response = get("/api/ping")
        assertThat(response.statusCode()).isEqualTo(200)

        val body = json.readTree(response.body())
        assertThat(body.path("service").asText()).isEqualTo("catalog-personalization")
        assertThat(body.path("version").asText()).isEqualTo("0.1.0")
        assertThat(body.path("status").asText()).isEqualTo("ok")
    }

    @Test
    fun `health endpoint reports UP`() {
        val response = get("/actuator/health")
        assertThat(response.statusCode()).isEqualTo(200)

        val body = json.readTree(response.body())
        assertThat(body.path("status").asText()).isEqualTo("UP")
    }
}
